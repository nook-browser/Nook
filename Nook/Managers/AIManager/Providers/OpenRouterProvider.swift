//
//  OpenRouterProvider.swift
//  Nook
//
//  OpenRouter API provider implementation
//

import Foundation
import OSLog

struct OpenRouterProvider: AIProviderProtocol {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "OpenRouterProvider")

    let apiKey: String
    let baseURL: String

    init(apiKey: String, baseURL: String = "https://openrouter.ai/api/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func sendMessage(
        messages: [AIMessage],
        model: String,
        config: AIGenerationConfig,
        tools: [AIToolDefinition],
        onStream: @escaping @Sendable (String) -> Void
    ) async throws -> AIResponse {
        guard !apiKey.isEmpty else { throw AIProviderError.invalidAPIKey }

        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build messages array in OpenAI format
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
                    var msg: [String: Any] = ["role": "assistant"]
                    if !message.content.isEmpty {
                        msg["content"] = message.content
                    }
                    let toolCallsArray: [[String: Any]] = message.toolCalls.map { tc in
                        let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments)) ?? Data()
                        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                        return [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": tc.name,
                                "arguments": argsString
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
                        "tool_call_id": result.toolCallId,
                        "content": result.content
                    ])
                }
            }
        }

        // Determine effective model (apply :online suffix for web search)
        var effectiveModel = model
        if config.webSearchEnabled {
            effectiveModel = "\(model):online"
        }

        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": messagesArray,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        // Add tools if available
        if !tools.isEmpty {
            body["tools"] = tools.map { $0.toOpenAIFormat() }
        }

        // Add web search options
        if config.webSearchEnabled {
            body["web_search_options"] = [
                "search_context_size": config.webSearchContextSize
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw AIProviderError.rateLimited
            }
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.httpError(httpResponse.statusCode, errorBody)
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> AIResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        let content = message["content"] as? String ?? ""

        // Parse tool calls
        var toolCalls: [AIToolCall] = []
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCallsArray {
                guard let tcId = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String else { continue }

                let argsString = function["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argsString.utf8))) as? [String: Any] ?? [:]
                toolCalls.append(AIToolCall(id: tcId, name: name, arguments: args))
            }
        }

        // Parse citations from annotations
        var citations: [URLCitation] = []
        if let annotations = message["annotations"] as? [[String: Any]] {
            for annotation in annotations {
                if let type = annotation["type"] as? String,
                   type == "url_citation",
                   let urlCitation = annotation["url_citation"] as? [String: Any],
                   let url = urlCitation["url"] as? String,
                   let startIndex = urlCitation["start_index"] as? Int,
                   let endIndex = urlCitation["end_index"] as? Int {
                    let citation = URLCitation(
                        url: url,
                        title: urlCitation["title"] as? String,
                        content: urlCitation["content"] as? String,
                        startIndex: startIndex,
                        endIndex: endIndex
                    )
                    citations.append(citation)
                }
            }
        }

        // Parse finish reason
        let finishReasonStr = firstChoice["finish_reason"] as? String ?? "stop"
        let finishReason: AIFinishReason
        switch finishReasonStr {
        case "tool_calls": finishReason = .toolCalls
        case "length": finishReason = .maxTokens
        default: finishReason = toolCalls.isEmpty ? .stop : .toolCalls
        }

        // Parse usage
        var usage: AIUsage?
        if let usageData = json?["usage"] as? [String: Any] {
            let prompt = usageData["prompt_tokens"] as? Int ?? 0
            let completion = usageData["completion_tokens"] as? Int ?? 0
            usage = AIUsage(promptTokens: prompt, completionTokens: completion, totalTokens: prompt + completion)
        }

        return AIResponse(
            content: content,
            toolCalls: toolCalls,
            citations: citations,
            usage: usage,
            finishReason: finishReason
        )
    }
}
