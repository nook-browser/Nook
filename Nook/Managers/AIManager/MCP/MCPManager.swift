//
//  MCPManager.swift
//  Nook
//
//  Manages multiple MCP server connections and aggregates tools
//

import Foundation
import OSLog

@MainActor
@Observable
class MCPManager {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "MCPManager")

    private var clients: [String: MCPClient] = [:]
    private(set) var connectionStates: [String: MCPConnectionState] = [:]
    private(set) var allTools: [MCPTool] = []

    // MARK: - Lifecycle

    func startEnabledServers(configs: [MCPServerConfig]) {
        for config in configs where config.isEnabled {
            connectServer(config)
        }
    }

    func stopAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
        connectionStates.removeAll()
        allTools.removeAll()
    }

    /// Synchronous version for app termination when async is not available
    func stopAllSync() {
        // Use a semaphore to wait for async cleanup
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await stopAll()
            semaphore.signal()
        }
        // Wait up to 5 seconds for cleanup
        _ = semaphore.wait(timeout: .now() + 5)
    }

    // MARK: - Server Management

    func connectServer(_ config: MCPServerConfig) {
        let client = MCPClient(serverConfig: config)
        clients[config.id] = client
        connectionStates[config.id] = .connecting

        Task {
            do {
                try await client.connect()
                connectionStates[config.id] = .connected
                refreshTools()
                Self.log.info("Connected to MCP server: \(config.name)")
            } catch {
                connectionStates[config.id] = .error(error.localizedDescription)
                Self.log.error("Failed to connect to MCP server \(config.name): \(error.localizedDescription)")
            }
        }
    }

    func disconnectServer(_ serverId: String) {
        guard let client = clients[serverId] else { return }

        Task {
            await client.disconnect()
            clients.removeValue(forKey: serverId)
            connectionStates[serverId] = .disconnected
            refreshTools()
        }
    }

    func reconnectServer(_ config: MCPServerConfig) {
        Task {
            await disconnectServerAsync(config.id)
            // Brief delay before reconnecting
            try? await Task.sleep(nanoseconds: 500_000_000)
            connectServer(config)
        }
    }

    /// Async version of disconnectServer that waits for completion
    func disconnectServerAsync(_ serverId: String) async {
        guard let client = clients[serverId] else { return }
        await client.disconnect()
        clients.removeValue(forKey: serverId)
        connectionStates[serverId] = .disconnected
        refreshTools()
    }

    // MARK: - Tool Calling

    func callTool(serverId: String, name: String, arguments: [String: Any]) async throws -> String {
        guard let client = clients[serverId] else {
            throw MCPClientError.notConnected
        }
        return try await client.callTool(name: name, arguments: arguments)
    }

    // MARK: - Tool Discovery

    func toolsForServer(_ serverId: String) async -> [MCPTool] {
        guard let client = clients[serverId] else { return [] }
        return await client.discoveredTools
    }

    private func refreshTools() {
        Task {
            var tools: [MCPTool] = []
            for (_, client) in clients {
                let clientTools = await client.discoveredTools
                tools.append(contentsOf: clientTools)
            }
            allTools = tools
        }
    }

    // MARK: - Connection State

    func connectionState(for serverId: String) -> MCPConnectionState {
        connectionStates[serverId] ?? .disconnected
    }

    var hasConnectedServers: Bool {
        connectionStates.values.contains { $0.isConnected }
    }
}
