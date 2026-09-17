//
//  MCPModels.swift
//  Nook
//
//  MCP (Model Context Protocol) data models
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

// MARK: - MCP Tool

public struct MCPTool: Identifiable, Equatable {
    public let id: String
    public let serverId: String
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]

    public var qualifiedName: String {
        "\(serverId).\(name)"
    }

    public init(serverId: String, name: String, description: String, inputSchema: [String: Any] = [:]) {
        self.id = "\(serverId).\(name)"
        self.serverId = serverId
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.description == rhs.description
    }
}

// MARK: - MCP Connection State

public enum MCPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - JSON-RPC Types

public struct JSONRPCRequest: Codable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: MCPAnyCodable]?

    public init(id: Int, method: String, params: [String: MCPAnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable {
    public let jsonrpc: String
    public let id: Int?
    public let result: MCPAnyCodable?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable {
    public let code: Int
    public let message: String
    public let data: MCPAnyCodable?
}

// MARK: - MCPAnyCodable Helper

public struct MCPAnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([MCPAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: MCPAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { MCPAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { MCPAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    public static func == (lhs: MCPAnyCodable, rhs: MCPAnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
