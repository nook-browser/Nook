//
//  OllamaProvider.swift
//  Nook
//
//  Ollama local LLM provider implementation using /api/chat for proper multi-turn
//

import Foundation
import OSLog

struct OllamaProvider: AIProviderProtocol {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "OllamaProvider")

    let baseURL: String

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL
    }

    func sendMessage(
        messages: [AIMessage],
        model: String,
        config: AIGenerationConfig,
        tools: [AIToolDefinition],
        onStream: @escaping @Sendable (String) -> Void
    ) async throws -> AIResponse {
        let url = URL(string: "\(baseURL)/api/chat")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages in Ollama chat format
        var messagesArray: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system:
                messagesArray.append([
                    "role": "system",
                    "content": message.content
                ])
            case .user:
                messagesArray.append([
                    "role": "user",
                    "content": message.content
                ])
            case .assistant:
                if !message.toolCalls.isEmpty {
                    var msg: [String: Any] = [
                        "role": "assistant",
                        "content": message.content
                    ]
                    let toolCallsArray: [[String: Any]] = message.toolCalls.map { tc in
                        return [
                            "function": [
                                "name": tc.name,
                                "arguments": tc.arguments
                            ]
                        ]
                    }
                    msg["tool_calls"] = toolCallsArray
                    messagesArray.append(msg)
                } else {
                    messagesArray.append([
                        "role": "assistant",
                        "content": message.content
                    ])
                }
            case .tool:
                for result in message.toolResults {
                    messagesArray.append([
                        "role": "tool",
                        "content": result.content
                    ])
                }
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messagesArray,
            "stream": false,
            "options": [
                "temperature": config.temperature
            ]
        ]

        // Add tools if supported
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters
                    ]
                ]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIProviderError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                "API request failed. Make sure Ollama is running."
            )
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> AIResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let message = json?["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        let content = message["content"] as? String ?? ""

        // Parse tool calls from Ollama format
        var toolCalls: [AIToolCall] = []
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCallsArray {
                if let function = tc["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    let args = function["arguments"] as? [String: Any] ?? [:]
                    toolCalls.append(AIToolCall(name: name, arguments: args))
                }
            }
        }

        let finishReason: AIFinishReason = toolCalls.isEmpty ? .stop : .toolCalls

        // Parse token counts
        var usage: AIUsage?
        if let promptEval = json?["prompt_eval_count"] as? Int,
           let evalCount = json?["eval_count"] as? Int {
            usage = AIUsage(promptTokens: promptEval, completionTokens: evalCount, totalTokens: promptEval + evalCount)
        }

        return AIResponse(
            content: content,
            toolCalls: toolCalls,
            citations: [],
            usage: usage,
            finishReason: finishReason
        )
    }
}
