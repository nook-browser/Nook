// Licensed under GPL-3.0. See LICENSE.
//
//  MCPServerConfig.swift
//  NookSettings
//
//  The persisted half of the MCP model: what server to talk to.
//  Everything else (tools, connection state, JSON-RPC) is runtime and lives in the app.
//

import Foundation

// MARK: - MCP Server Configuration

public enum MCPTransportType: Codable, Equatable {
    case stdio(command: String, args: [String])
    case sse(url: String)

    public var displayName: String {
        switch self {
        case .stdio: return "Stdio"
        case .sse: return "SSE"
        }
    }
}

public struct MCPServerConfig: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var transport: MCPTransportType
    public var envVars: [String: String]
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        transport: MCPTransportType,
        envVars: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.envVars = envVars
        self.isEnabled = isEnabled
    }
}
