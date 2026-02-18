//
//  MCPClient.swift
//  Nook
//
//  MCP client for a single server connection using JSON-RPC 2.0
//

import Foundation
import OSLog

actor MCPClient {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "MCPClient")

    let serverConfig: MCPServerConfig
    private var transport: (any MCPTransportProtocol)?
    private var requestId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var receiveTask: Task<Void, Never>?

    private(set) var connectionState: MCPConnectionState = .disconnected
    private(set) var discoveredTools: [MCPTool] = []

    init(serverConfig: MCPServerConfig) {
        self.serverConfig = serverConfig
    }

    // MARK: - Connection Lifecycle

    func connect() async throws {
        connectionState = .connecting

        do {
            let transport: any MCPTransportProtocol

            switch serverConfig.transport {
            case .stdio(let command, let args):
                let stdioTransport = StdioTransport(command: command, args: args, envVars: serverConfig.envVars)
                try stdioTransport.start()
                transport = stdioTransport

            case .sse(let url):
                let sseTransport = SSETransport(url: url)
                try await sseTransport.connect()
                transport = sseTransport
            }

            self.transport = transport

            // Start receiving messages
            startReceiving()

            // Initialize the MCP connection
            try await initialize()

            // Discover available tools
            try await listTools()

            connectionState = .connected
            Self.log.info("Connected to MCP server: \(self.serverConfig.name)")

        } catch {
            connectionState = .error(error.localizedDescription)
            Self.log.error("Failed to connect to MCP server \(self.serverConfig.name): \(error.localizedDescription)")
            throw error
        }
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil

        if let transport = transport {
            await transport.close()
        }
        transport = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPClientError.disconnected)
        }
        pendingRequests.removeAll()

        connectionState = .disconnected
        discoveredTools = []
        Self.log.info("Disconnected from MCP server: \(self.serverConfig.name)")
    }

    // MARK: - MCP Protocol Methods

    private func initialize() async throws {
        let params: [String: MCPAnyCodable] = [
            "protocolVersion": MCPAnyCodable("2024-11-05"),
            "capabilities": MCPAnyCodable([String: Any]()),
            "clientInfo": MCPAnyCodable([
                "name": "Nook",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ])
        ]

        let response = try await sendRequest(method: "initialize", params: params)

        if let error = response.error {
            throw MCPClientError.serverError(error.message)
        }

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized")
    }

    func listTools() async throws {
        let response = try await sendRequest(method: "tools/list")

        if let error = response.error {
            throw MCPClientError.serverError(error.message)
        }

        guard let result = response.result?.value as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return
        }

        var tools: [MCPTool] = []
        for toolDict in toolsArray {
            guard let name = toolDict["name"] as? String else { continue }
            let description = toolDict["description"] as? String ?? ""
            let inputSchema = toolDict["inputSchema"] as? [String: Any] ?? [:]

            tools.append(MCPTool(
                serverId: serverConfig.id,
                name: name,
                description: description,
                inputSchema: inputSchema
            ))
        }

        discoveredTools = tools
        Self.log.info("Discovered \(tools.count) tools from \(self.serverConfig.name)")
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let params: [String: MCPAnyCodable] = [
            "name": MCPAnyCodable(name),
            "arguments": MCPAnyCodable(arguments)
        ]

        let response = try await sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            throw MCPClientError.serverError(error.message)
        }

        guard let result = response.result?.value as? [String: Any],
              let content = result["content"] as? [[String: Any]] else {
            return "No result"
        }

        // Concatenate text content from the response
        var textParts: [String] = []
        for part in content {
            if let text = part["text"] as? String {
                textParts.append(text)
            }
        }

        return textParts.joined(separator: "\n")
    }

    // Default timeout for MCP requests (30 seconds)
    private let requestTimeout: TimeInterval = 30

    // MARK: - JSON-RPC Communication

    private func sendRequest(method: String, params: [String: MCPAnyCodable]? = nil) async throws -> JSONRPCResponse {
        guard let transport = transport else {
            throw MCPClientError.notConnected
        }

        requestId += 1
        let id = requestId
        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        return try await withTimeout(seconds: requestTimeout) { [self] in
            try await withCheckedThrowingContinuation { continuation in
                self.pendingRequests[id] = continuation

                Task {
                    do {
                        try await transport.send(data)
                    } catch {
                        await self.removePendingRequest(id: id, error: error)
                    }
                }
            }
        }
    }

    private func removePendingRequest(id: Int, error: Error) {
        if let cont = pendingRequests.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func cancelPendingRequest(id: Int) {
        pendingRequests.removeValue(forKey: id)
    }

    /// Wraps an async operation with a timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MCPClientError.timeout
            }

            // Return the first completed result and cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func sendNotification(method: String, params: [String: MCPAnyCodable]? = nil) async throws {
        guard let transport = transport else {
            throw MCPClientError.notConnected
        }

        // Notifications don't have an id field; use -1 as a marker (won't be used for matching)
        let request = JSONRPCRequest(id: -1, method: method, params: params)
        var data = try JSONEncoder().encode(request)

        // Remove the "id" field for proper notification format
        if var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict.removeValue(forKey: "id")
            data = try JSONSerialization.data(withJSONObject: dict)
        }

        try await transport.send(data)
    }

    /// Dispatches a decoded response to its pending continuation
    private func dispatchResponse(_ response: JSONRPCResponse) {
        if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(returning: response)
        }
    }

    private func startReceiving() {
        guard let transport = transport else { return }

        receiveTask = Task { [weak self] in
            for await data in transport.receive() {
                guard let self = self else { break }

                do {
                    let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                    await self.dispatchResponse(response)
                } catch {
                    Self.log.error("Failed to decode MCP response: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - MCP Client Errors

enum MCPClientError: LocalizedError {
    case notConnected
    case disconnected
    case serverError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP server"
        case .disconnected: return "Disconnected from MCP server"
        case .serverError(let msg): return "MCP server error: \(msg)"
        case .timeout: return "MCP request timed out"
        }
    }
}
