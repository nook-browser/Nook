// Licensed under GPL-3.0. See LICENSE.
//
//  OpenAICompatibleProvider.swift
//  Nook
//
//  Generic OpenAI-compatible provider for LM Studio, vLLM, Together, Groq, etc.
//

import Foundation
import NookSettings
import OSLog

struct OpenAICompatibleProvider: AIProviderProtocol {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "OpenAICompatibleProvider")

    let apiKey: String
    let baseURL: String
    let customHeaders: [String: String]

    init(apiKey: String = "", baseURL: String, customHeaders: [String: String] = [:]) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.customHeaders = customHeaders
    }

    func sendMessage(
        messages: [AIMessage],
        model: String,
        config: AIGenerationConfig,
        tools: [AIToolDefinition],
        onStream: @escaping @Sendable (String) -> Void
    ) async throws -> AIResponse {
        // SECURITY: Require HTTPS for non-local connections to prevent MITM on API keys
        if let parsedBase = URL(string: baseURL) {
            let scheme = parsedBase.scheme?.lowercased() ?? ""
            let host = parsedBase.host?.lowercased() ?? ""
            let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if scheme != "https" && !isLocal {
                Self.log.warning("Custom provider requires HTTPS for non-local connections: \(self.baseURL)")
                throw AIProviderError.insecureURL(baseURL)
            }
        }

        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build messages in OpenAI format
        var messagesArray: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system:
                messagesArray.append(["role": "system", "content": message.content])
            case .user:
                messagesArray.append(["role": "user", "content": message.content])
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
                            "function": ["name": tc.name, "arguments": argsString]
                        ]
                    }
                    msg["tool_calls"] = toolCallsArray
                    messagesArray.append(msg)
                } else {
                    messagesArray.append(["role": "assistant", "content": message.content])
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

        var body: [String: Any] = [
            "model": model,
            "messages": messagesArray,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]

        if !tools.isEmpty {
            body["tools"] = tools.map { $0.toOpenAIFormat() }
        }

        while true {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.invalidResponse
            }

            // Each fix removes a key, so this resends at most twice
            if httpResponse.statusCode == 400, let fixed = Self.body(body, fixingRejectionIn: data) {
                body = fixed
                continue
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
    }

    /// OpenAI's reasoning models (GPT-5, o-series) reject `max_tokens` and any temperature but the
    /// default, and name the parameter in the error. Returns the body with it fixed, or nil.
    static func body(_ body: [String: Any], fixingRejectionIn data: Data) -> [String: Any]? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var body = body
        switch (json?["error"] as? [String: Any])?["param"] as? String {
        case "max_tokens":
            guard let limit = body.removeValue(forKey: "max_tokens") else { return nil }
            body["max_completion_tokens"] = limit
        case "temperature":
            guard body.removeValue(forKey: "temperature") != nil else { return nil }
        default:
            return nil
        }
        return body
    }

    private func parseResponse(_ data: Data) throws -> AIResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        let content = message["content"] as? String ?? ""

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

        let finishReasonStr = firstChoice["finish_reason"] as? String ?? "stop"
        let finishReason: AIFinishReason
        switch finishReasonStr {
        case "tool_calls": finishReason = .toolCalls
        case "length": finishReason = .maxTokens
        default: finishReason = toolCalls.isEmpty ? .stop : .toolCalls
        }

        var usage: AIUsage?
        if let usageData = json?["usage"] as? [String: Any] {
            let prompt = usageData["prompt_tokens"] as? Int ?? 0
            let completion = usageData["completion_tokens"] as? Int ?? 0
            usage = AIUsage(promptTokens: prompt, completionTokens: completion, totalTokens: prompt + completion)
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
