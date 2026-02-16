//
//  AIProvider.swift
//  Nook
//
//  Provider protocol and shared message types for AI communication
//

import Foundation

// MARK: - Provider Protocol

protocol AIProviderProtocol {
    func sendMessage(
        messages: [AIMessage],
        model: String,
        config: AIGenerationConfig,
        tools: [AIToolDefinition],
        onStream: @escaping @Sendable (String) -> Void
    ) async throws -> AIResponse
}

// MARK: - Message Types

struct AIMessage: Equatable {
    let role: AIMessageRole
    let content: String
    var toolCalls: [AIToolCall]
    var toolResults: [AIToolResult]

    init(role: AIMessageRole, content: String, toolCalls: [AIToolCall] = [], toolResults: [AIToolResult] = []) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}

enum AIMessageRole: String, Equatable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Response Types

struct AIResponse: Equatable {
    let content: String
    let toolCalls: [AIToolCall]
    let citations: [URLCitation]
    let usage: AIUsage?
    let finishReason: AIFinishReason

    init(
        content: String = "",
        toolCalls: [AIToolCall] = [],
        citations: [URLCitation] = [],
        usage: AIUsage? = nil,
        finishReason: AIFinishReason = .stop
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.citations = citations
        self.usage = usage
        self.finishReason = finishReason
    }
}

enum AIFinishReason: String, Equatable {
    case stop
    case toolCalls = "tool_calls"
    case maxTokens = "max_tokens"
    case error
}

struct AIUsage: Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - Tool Types

struct AIToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    let arguments: [String: Any]

    init(id: String = UUID().uuidString, name: String, arguments: [String: Any] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    static func == (lhs: AIToolCall, rhs: AIToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

struct AIToolResult: Equatable {
    let toolCallId: String
    let content: String
    let isError: Bool

    init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

// MARK: - Tool Definition

struct AIToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]

    func toGeminiFormat() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "parameters": parameters
        ]
    }

    func toOpenAIFormat() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case httpError(Int, String)
    case rateLimited
    case networkError(Error)
    case unsupportedFeature(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid or missing API key"
        case .invalidResponse: return "Failed to parse response"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .rateLimited: return "Rate limit exceeded. Please try again later."
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .unsupportedFeature(let feature): return "\(feature) is not supported by this provider"
        }
    }
}
