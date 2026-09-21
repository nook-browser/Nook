// Licensed under GPL-3.0. See LICENSE.
//
//  MCPTransport.swift
//  Nook
//
//  Transport abstractions for MCP server communication (stdio and SSE)
//

import Foundation
import OSLog

// MARK: - Transport Protocol

protocol MCPTransportProtocol: Sendable {
    func send(_ data: Data) async throws
    func receive() -> AsyncStream<Data>
    func close() async
}

// MARK: - Stdio Transport

final class StdioTransport: MCPTransportProtocol, @unchecked Sendable {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "StdioTransport")

    private let command: String
    private let args: [String]
    private let envVars: [String: String]
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let lock = NSLock()

    /// Maximum allowed size for a single stdio message (10 MB), the same as the SSE transport
    private static let maxMessageSize = 10 * 1024 * 1024

    init(command: String, args: [String] = [], envVars: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.envVars = envVars
    }

    func start() throws {
        // SECURITY: Validate that the command path exists and is executable before launching
        let fm = FileManager.default
        guard fm.fileExists(atPath: command) else {
            Self.log.warning("MCP command path does not exist: \(self.command)")
            throw MCPTransportError.invalidCommandPath
        }
        guard fm.isExecutableFile(atPath: command) else {
            Self.log.warning("MCP command path is not executable: \(self.command)")
            throw MCPTransportError.invalidCommandPath
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        // Pass only what a child needs to run. A deny-list of secret-looking names always
        // misses one, so anything else the server needs goes in its configured envVars.
        let inheritedKeys: Set<String> = ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "TMPDIR", "TERM"]
        var env = ProcessInfo.processInfo.environment.filter { (key, _) in
            inheritedKeys.contains(key) || key.hasPrefix("LC_")
        }

        // Apply user-specified env vars (these are intentional)
        for (key, value) in envVars {
            env[key] = value
        }
        process.environment = env

        try process.run()

        lock.lock()
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        lock.unlock()

        Self.log.info("Started MCP process: \(self.command)")
    }

    private func getStdinPipe() -> Pipe? {
        lock.lock()
        defer { lock.unlock() }
        return stdinPipe
    }

    private func getStdoutPipe() -> Pipe? {
        lock.lock()
        defer { lock.unlock() }
        return stdoutPipe
    }

    func send(_ data: Data) async throws {
        guard let stdinPipe = getStdinPipe() else {
            throw MCPTransportError.notConnected
        }

        var message = data
        if !message.isEmpty && message.last != UInt8(ascii: "\n") {
            message.append(UInt8(ascii: "\n"))
        }

        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: message)
        } catch {
            throw MCPTransportError.sendFailed
        }
    }

    // Track the receive task for cancellation
    private var receiveTask: Task<Void, Never>?

    func receive() -> AsyncStream<Data> {
        let pipe = getStdoutPipe()

        return AsyncStream { [weak self] continuation in
            guard let stdoutPipe = pipe else {
                continuation.finish()
                return
            }

            let handle = stdoutPipe.fileHandleForReading

            let task = Task.detached {
                var buffer = Data()

                while true {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        break
                    }

                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        continuation.finish()
                        break
                    }

                    buffer.append(chunk)

                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let messageData = buffer[buffer.startIndex..<newlineIndex]
                        buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                        if !messageData.isEmpty {
                            continuation.yield(Data(messageData))
                        }
                    }

                    // SECURITY: A child that never sends a newline would grow this without bound
                    if buffer.count > StdioTransport.maxMessageSize {
                        StdioTransport.log.warning("MCP stdio message exceeds maximum size limit (\(StdioTransport.maxMessageSize) bytes), closing stream")
                        continuation.finish()
                        break
                    }
                }
            }
            self?.receiveTask = task
        }
    }

    private func clearProcessState() -> (Process?, Pipe?) {
        lock.lock()
        defer { lock.unlock() }
        let proc = process
        let pipe = stdinPipe
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        return (proc, pipe)
    }

    func close() async {
        // Cancel the receive task first
        receiveTask?.cancel()
        receiveTask = nil

        let (proc, pipe) = clearProcessState()
        pipe?.fileHandleForWriting.closeFile()
        proc?.terminate()
        proc?.waitUntilExit()
        Self.log.info("Closed MCP process: \(self.command)")
    }
}

// MARK: - SSE Transport

final class SSETransport: MCPTransportProtocol, @unchecked Sendable {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "SSETransport")

    private let url: String
    private var task: URLSessionDataTask?
    private var postEndpoint: String?
    private let lock = NSLock()

    // Track the receive task for cancellation
    private var receiveTask: Task<Void, Never>?

    /// Maximum allowed size for a single SSE message (10 MB)
    private static let maxMessageSize = 10 * 1024 * 1024

    init(url: String) {
        self.url = url
    }

    func connect() async throws {
        guard let parsedURL = URL(string: url) else {
            throw MCPTransportError.invalidURL
        }

        // Require HTTPS for non-local connections to prevent MITM attacks
        let scheme = parsedURL.scheme?.lowercased() ?? ""
        let host = parsedURL.host?.lowercased() ?? ""
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if scheme != "https" && !isLocal {
            Self.log.warning("MCP SSE transport requires HTTPS for non-local connections. Got: \(scheme)://\(host)")
            throw MCPTransportError.invalidURL
        }

        Self.log.info("Connected to SSE endpoint: \(self.url)")
    }

    private func getPostEndpoint() -> String {
        lock.lock()
        defer { lock.unlock() }
        return postEndpoint ?? url
    }

    func send(_ data: Data) async throws {
        let endpoint = getPostEndpoint()
        guard let postURL = URL(string: endpoint) else {
            throw MCPTransportError.invalidURL
        }

        var request = URLRequest(url: postURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPTransportError.sendFailed
        }
    }

    func receive() -> AsyncStream<Data> {
        let sseURL = URL(string: url)

        return AsyncStream { [weak self] continuation in
            guard let sseURL = sseURL else {
                continuation.finish()
                return
            }

            let task = Task.detached {
                do {
                    var request = URLRequest(url: sseURL)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            break
                        }

                        if line.hasPrefix("data: ") {
                            let dataStr = String(line.dropFirst(6))
                            if let data = dataStr.data(using: .utf8) {
                                // SECURITY: Discard messages that exceed the maximum size limit
                                if data.count > SSETransport.maxMessageSize {
                                    Self.log.warning("SSE message exceeds maximum size limit (\(data.count) bytes > \(SSETransport.maxMessageSize) bytes) — discarding")
                                    continue
                                }
                                continuation.yield(data)
                            }
                        }
                    }
                } catch {
                    Self.log.error("SSE receive error: \(error.localizedDescription)")
                }
                continuation.finish()
            }
            self?.receiveTask = task
        }
    }

    private func clearTask() -> URLSessionDataTask? {
        lock.lock()
        defer { lock.unlock() }
        let t = task
        task = nil
        return t
    }

    func close() async {
        // Cancel the receive task first
        receiveTask?.cancel()
        receiveTask = nil

        let t = clearTask()
        t?.cancel()
        Self.log.info("Closed SSE connection: \(self.url)")
    }
}

// MARK: - Transport Errors

enum MCPTransportError: LocalizedError {
    case notConnected
    case invalidURL
    case sendFailed
    case processNotRunning
    case invalidCommandPath
    case messageTooLarge

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Transport not connected"
        case .invalidURL: return "Invalid URL"
        case .sendFailed: return "Failed to send message"
        case .processNotRunning: return "Process is not running"
        case .invalidCommandPath: return "Command path does not exist or is not executable"
        case .messageTooLarge: return "Message exceeds maximum allowed size"
        }
    }
}
