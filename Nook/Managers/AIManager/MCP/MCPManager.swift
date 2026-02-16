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

    func stopAll() {
        Task {
            for (_, client) in clients {
                await client.disconnect()
            }
            clients.removeAll()
            connectionStates.removeAll()
            allTools.removeAll()
        }
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
        disconnectServer(config.id)
        // Brief delay before reconnecting
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            connectServer(config)
        }
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
