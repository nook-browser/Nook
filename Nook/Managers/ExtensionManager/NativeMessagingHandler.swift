// Licensed under GPL-3.0. See LICENSE.
//
//  NativeMessagingHandler.swift
//  Nook
//
//  Native messaging support for browser extensions.
//  Handles launching host processes and communicating via stdin/stdout.
//

import Foundation
import os
import WebKit

// MARK: - Native Messaging Handler

/// One native host conversation. Host lookup and process I/O run off the main thread;
/// every callback into WebKit or the caller is delivered on the main thread.
final class NativeMessagingHandler: NSObject {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "NativeMessaging")

    static let errorDomain = "NativeMessaging"
    enum ErrorCode: Int {
        case hostNotFound = 1
        case noInputPipe = 2
        case hostClosed = 4
        case badResponse = 5
        case timedOut = 6
    }

    /// Chrome caps host-to-browser messages at 1 MB.
    private static let maxResponseSize = 1024 * 1024

    let applicationId: String
    private let callerOrigins: Set<String>

    // Port mode state (main thread only)
    private weak var port: WKWebExtension.MessagePort?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var pendingMessages: [Any] = []
    private var isClosed = false
    private let writeQueue = DispatchQueue(label: "com.nook.native-messaging.write")

    // Read on the pipe's readability queue only
    private var outputBuffer = Data()

    /// Called on the main thread once a port conversation ends.
    var onClose: (() -> Void)?

    init(applicationId: String, extensionContext: WKWebExtensionContext) {
        self.applicationId = applicationId
        self.callerOrigins = Self.origins(for: extensionContext)
        super.init()
    }

    /// How the calling extension identifies itself to host manifests: Chrome `allowed_origins`
    /// entries (`chrome-extension://<id>/`, or `nook-extension://<id>/` for Nook-specific hosts).
    /// Firefox `allowed_extensions` is not honored: a gecko ID is only what the extension's own
    /// manifest claims, and nothing here verifies it the way AMO signing does.
    private static func origins(for context: WKWebExtensionContext) -> Set<String> {
        let id = context.uniqueIdentifier
        var origins: Set<String> = ["nook-extension://\(id)/"]
        if ExtensionStore.isValidExtensionID(id) {
            origins.insert("chrome-extension://\(id)/")
        }
        return origins
    }

    private static func error(_ code: ErrorCode, _ description: String) -> NSError {
        NSError(domain: errorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: description])
    }

    // MARK: - Single-shot messages

    /// Launch the host, send one message, read one reply (5 s timeout), terminate.
    func sendMessage(_ message: Any, completion: @escaping (Any?, Error?) -> Void) {
        let finish: (Any?, Error?) -> Void = { response, error in
            DispatchQueue.main.async { completion(response, error) }
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard let executable = resolveHostExecutable() else {
                return finish(nil, Self.error(.hostNotFound, "Native messaging host \(applicationId) not found or not allowed for this extension"))
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = callerOrigins.sorted().filter { $0.hasPrefix("chrome-extension://") }
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                try Self.write(message, to: input.fileHandleForWriting)
            } catch {
                process.terminate()
                return finish(nil, error)
            }

            var response: Any?
            var readError: Error?
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                defer { done.signal() }
                let handle = output.fileHandleForReading
                let lengthData = handle.readData(ofLength: 4)
                guard lengthData.count == 4 else {
                    readError = Self.error(.hostClosed, "Host closed without response")
                    return
                }
                let length = Int(lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                guard length <= Self.maxResponseSize else {
                    readError = Self.error(.badResponse, "Host response too large")
                    return
                }
                let jsonData = handle.readData(ofLength: length)
                if let json = try? JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed]) {
                    response = json
                } else {
                    readError = Self.error(.badResponse, "Failed to parse host response")
                }
            }

            let timedOut = done.wait(timeout: .now() + 5) == .timedOut
            // Terminating closes the pipes, which also unblocks a reader stuck after a timeout.
            process.terminate()
            if timedOut {
                finish(nil, Self.error(.timedOut, "Host response timed out"))
            } else {
                finish(response, readError)
            }
        }
    }

    // MARK: - Long-lived ports

    /// Connect a `runtime.connectNative` port to a host process. `hostAvailability` is called on
    /// the main thread; on `false` the port is left open so the caller can handle it in-process.
    func connect(port: WKWebExtension.MessagePort, hostAvailability: @escaping (Bool) -> Void) {
        self.port = port

        // WebKit calls port handlers on the main thread. The handler is (message, error).
        port.messageHandler = { [weak self] message, error in
            guard error == nil, let message else { return }
            self?.post(message)
        }
        port.disconnectHandler = { [weak self] _ in
            self?.close(disconnectPort: false)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let executable = self.resolveHostExecutable() else {
                DispatchQueue.main.async { hostAvailability(false) }
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = self.callerOrigins.sorted().filter { $0.hasPrefix("chrome-extension://") }
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    self?.handleOutput(data)
                }
            }
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.close(disconnectPort: true) }
            }

            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                Self.logger.error("Failed to launch host \(self.applicationId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { hostAvailability(false) }
                return
            }

            DispatchQueue.main.async {
                guard !self.isClosed else {
                    process.terminate()
                    return
                }
                self.process = process
                self.inputHandle = input.fileHandleForWriting
                let queued = self.pendingMessages
                self.pendingMessages.removeAll()
                queued.forEach { self.post($0) }
                hostAvailability(true)
            }
        }
    }

    /// Main thread. Messages sent before the host finishes launching are queued.
    private func post(_ message: Any) {
        guard !isClosed else { return }
        guard let inputHandle else {
            pendingMessages.append(message)
            return
        }
        writeQueue.async {
            do {
                try Self.write(message, to: inputHandle)
            } catch {
                Self.logger.error("Failed to write to host: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Main thread.
    private func close(disconnectPort: Bool) {
        guard !isClosed else { return }
        isClosed = true
        if let process, process.isRunning { process.terminate() }
        process = nil
        inputHandle = nil
        pendingMessages.removeAll()
        if disconnectPort { port?.disconnect() }
        onClose?()
        onClose = nil
    }

    // MARK: - Host lookup

    private static let manifestDirectories = [
        "Library/Application Support/Nook/NativeMessagingHosts",
        "Library/Application Support/Google/Chrome/NativeMessagingHosts",
        "Library/Application Support/Chromium/NativeMessagingHosts",
        "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
        "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
        "Library/Application Support/Mozilla/NativeMessagingHosts",
    ]

    /// Find a host manifest for `applicationId` that allows the calling extension, and return
    /// its validated executable. Mirrors Chrome's rules: the manifest `name` must match, the
    /// type must be stdio, the path must be absolute, and the caller must be listed in
    /// `allowed_origins`.
    private func resolveHostExecutable() -> URL? {
        // Host names are dot-separated lowercase alphanumerics and underscores; this also keeps
        // the manifest filename from escaping the host directories.
        guard !applicationId.isEmpty,
              applicationId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }),
              !applicationId.hasPrefix("."), !applicationId.contains("..")
        else {
            Self.logger.error("Rejected invalid native host name \(self.applicationId, privacy: .public)")
            return nil
        }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let manifestName = "\(applicationId).json"
        var manifestPaths: [URL] = []
        for dir in Self.manifestDirectories {
            manifestPaths.append(home.appendingPathComponent(dir).appendingPathComponent(manifestName))
            manifestPaths.append(URL(fileURLWithPath: "/\(dir)").appendingPathComponent(manifestName))
        }

        for manifestURL in manifestPaths {
            guard let data = try? Data(contentsOf: manifestURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard json["name"] as? String == applicationId,
                  (json["type"] as? String ?? "stdio") == "stdio",
                  let binaryPath = json["path"] as? String, binaryPath.hasPrefix("/")
            else {
                Self.logger.error("Ignoring malformed host manifest \(manifestURL.path, privacy: .public)")
                continue
            }

            let allowedOrigins = Set(json["allowed_origins"] as? [String] ?? [])
            guard !allowedOrigins.isDisjoint(with: callerOrigins) else {
                Self.logger.info("Host manifest \(manifestURL.path, privacy: .public) does not allow this extension")
                continue
            }

            let canonicalURL = URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath()
            let canonicalPath = canonicalURL.path
            let allowedPrefixes = [
                "\(home.path)/Library/",
                "/Applications/",
                "/usr/local/",
                "/usr/bin/",
                "/opt/",
                "/Library/",
            ]
            guard !binaryPath.contains(".."),
                  fm.isExecutableFile(atPath: canonicalPath),
                  allowedPrefixes.contains(where: { canonicalPath.hasPrefix($0) })
            else {
                Self.logger.error("SECURITY: Refusing host binary \(canonicalPath, privacy: .public) from \(manifestURL.path, privacy: .public)")
                continue
            }

            Self.logger.info("Using native host \(canonicalPath, privacy: .public) from \(manifestURL.path, privacy: .public)")
            return canonicalURL
        }
        return nil
    }

    // MARK: - Framing

    /// Native messaging protocol: 4-byte native-endian length, then UTF-8 JSON.
    private static func write(_ message: Any, to handle: FileHandle) throws {
        // JSONSerialization raises an Objective-C exception (not a Swift error) on invalid input.
        guard JSONSerialization.isValidJSONObject(message) || message is String || message is NSNumber else {
            throw error(.badResponse, "Message is not JSON-serializable")
        }
        let jsonData = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        var length = UInt32(jsonData.count)
        try handle.write(contentsOf: Data(bytes: &length, count: 4))
        try handle.write(contentsOf: jsonData)
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        while outputBuffer.count >= 4 {
            let length = Int(outputBuffer.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard length <= Self.maxResponseSize else {
                Self.logger.error("Host message exceeds 1 MB; closing port")
                outputBuffer.removeAll()
                DispatchQueue.main.async { [weak self] in self?.close(disconnectPort: true) }
                return
            }
            let totalNeeded = 4 + length
            guard outputBuffer.count >= totalNeeded else { break }

            let jsonData = outputBuffer.subdata(in: outputBuffer.startIndex + 4..<outputBuffer.startIndex + totalNeeded)
            outputBuffer.removeSubrange(outputBuffer.startIndex..<outputBuffer.startIndex + totalNeeded)

            if let json = try? JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed]) {
                DispatchQueue.main.async { [weak self] in
                    self?.port?.sendMessage(json) { _ in }
                }
            } else {
                Self.logger.error("Failed to parse JSON from host (\(jsonData.count) bytes)")
            }
        }
    }
}
