//
//  GeminiProvider.swift
//  Nook
//
//  Google Gemini API provider implementation
//

import Foundation
import OSLog

struct GeminiProvider: AIProviderProtocol {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "GeminiProvider")

    let apiKey: String
    let baseURL: String

    init(apiKey: String, baseURL: String = "https://generativelanguage.googleapis.com/v1beta") {
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

        let url = URL(string: "\(baseURL)/models/\(model):generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        // Build request body
        var body: [String: Any] = [:]

        // System instruction
        let systemMessage = messages.first { $0.role == .system }
        if let systemContent = systemMessage?.content, !systemContent.isEmpty {
            body["system_instruction"] = [
                "parts": [["text": systemContent]]
            ]
        }

        // Build conversation contents
        var contents: [[String: Any]] = []
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                contents.append([
                    "role": "user",
                    "parts": [["text": message.content]]
                ])
            case .assistant:
                if !message.toolCalls.isEmpty {
                    var parts: [[String: Any]] = []
                    if !message.content.isEmpty {
                        parts.append(["text": message.content])
                    }
                    for toolCall in message.toolCalls {
                        parts.append([
                            "functionCall": [
                                "name": toolCall.name,
                                "args": toolCall.arguments
                            ]
                        ])
                    }
                    contents.append(["role": "model", "parts": parts])
                } else {
                    contents.append([
                        "role": "model",
                        "parts": [["text": message.content]]
                    ])
                }
            case .tool:
                for result in message.toolResults {
                    contents.append([
                        "role": "function",
                        "parts": [[
                            "functionResponse": [
                                "name": result.toolCallId,
                                "response": ["content": result.content]
                            ]
                        ]]
                    ])
                }
            case .system:
                break
            }
        }

        body["contents"] = contents

        // Add tools
        var allTools: [[String: Any]] = []

        // Add web search tool if enabled
        if config.webSearchEnabled {
            allTools.append(["google_search": [:] as [String: Any]])
        }

        // Add function calling tools
        if !tools.isEmpty {
            let functionDeclarations = tools.map { $0.toGeminiFormat() }
            allTools.append(["function_declarations": functionDeclarations])
        }

        if !allTools.isEmpty {
            body["tools"] = allTools
        }

        // Generation config
        body["generationConfig"] = [
            "temperature": config.temperature,
            "maxOutputTokens": config.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 429 {
                throw AIProviderError.rateLimited
            }
            throw AIProviderError.httpError(httpResponse.statusCode, errorBody)
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> AIResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse
        }

        var textContent = ""
        var toolCalls: [AIToolCall] = []

        for part in parts {
            if let text = part["text"] as? String {
                textContent += text
            }
            if let functionCall = part["functionCall"] as? [String: Any],
               let name = functionCall["name"] as? String {
                let args = functionCall["args"] as? [String: Any] ?? [:]
                // Extract Gemini's unique call ID for proper FunctionResponse correlation
                let callId = functionCall["id"] as? String ?? UUID().uuidString
                toolCalls.append(AIToolCall(id: callId, name: name, arguments: args))
            }
        }

        // Parse citations
        let citations = parseInlineCitations(from: textContent)

        let finishReason: AIFinishReason = toolCalls.isEmpty ? .stop : .toolCalls

        // Parse usage
        var usage: AIUsage?
        if let usageData = json?["usageMetadata"] as? [String: Any] {
            let prompt = usageData["promptTokenCount"] as? Int ?? 0
            let completion = usageData["candidatesTokenCount"] as? Int ?? 0
            usage = AIUsage(promptTokens: prompt, completionTokens: completion, totalTokens: prompt + completion)
        }

        return AIResponse(
            content: textContent,
            toolCalls: toolCalls,
            citations: citations,
            usage: usage,
            finishReason: finishReason
        )
    }

    private func parseInlineCitations(from text: String) -> [URLCitation] {
        var citations: [URLCitation] = []
        let pattern = "\\[(\\d+)\\]\\((https?://[^)]+)\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return citations
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let urlRange = Range(match.range(at: 2), in: text),
                  let fullRange = Range(match.range(at: 0), in: text) else { continue }

            let url = String(text[urlRange])
            let startIndex = text.distance(from: text.startIndex, to: fullRange.lowerBound)
            let endIndex = text.distance(from: text.startIndex, to: fullRange.upperBound)

            var title: String? = nil
            if let urlObj = URL(string: url), let host = urlObj.host {
                title = host.replacingOccurrences(of: "www.", with: "")
            }

            let citation = URLCitation(url: url, title: title, content: nil, startIndex: startIndex, endIndex: endIndex)
            if !citations.contains(where: { $0.url == citation.url }) {
                citations.append(citation)
            }
        }

        return citations
    }
}
