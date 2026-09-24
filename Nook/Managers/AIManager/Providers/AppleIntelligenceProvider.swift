// Licensed under GPL-3.0. See LICENSE.
//
//  AppleIntelligenceProvider.swift
//  Nook
//
//  Chat on the system language model (Apple Intelligence): no key, no network.
//

import Foundation
import FoundationModels
import NookSettings

struct AppleIntelligenceProvider: AIProviderProtocol {
    static let providerId = "apple-intelligence"
    static let modelId = "apple-on-device"

    /// Short on purpose: the default system prompt alone is about 800 tokens of a 4096-token context.
    static let instructions = """
        You are the assistant in Nook, a web browser. Answer questions about the page the person is viewing, \
        using the page text you are given. Be brief. When the page does not say, tell them so instead of guessing. \
        Use a tool only when they ask you to do something in the browser.
        """

    /// Observable: views reading this update when Apple Intelligence is turned on or off.
    static var isAvailable: Bool { model.isAvailable }

    // Budgets in estimated tokens for a 4096-token context on macOS 26 and 8192 on 27, keyed on the
    // OS because `contextSize` needs the 26.4 SDK.
    static var pageTokens: Int { if #available(macOS 27, *) { 3000 } else { 1200 } }
    static var toolOutputTokens: Int { if #available(macOS 27, *) { 600 } else { 400 } }
    private static var historyTokens: Int { if #available(macOS 27, *) { 1000 } else { 400 } }
    private static var responseTokens: Int { if #available(macOS 27, *) { 1500 } else { 800 } }

    /// Tools a small model can use in one step. The page is already in the prompt, so the page-reading
    /// tools would only overflow the context, and JavaScript stays with the larger models.
    private static let toolNames: Set<String> = [
        "navigateToURL", "clickElement", "getInteractiveElements", "searchInPage",
        "getSelectedText", "getTabList", "switchTab", "createTab",
    ]

    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// Runs a browser tool by name with its JSON arguments and returns what the model reads back.
    let runTool: @MainActor @Sendable (_ name: String, _ argumentsJSON: String) async -> String

    func sendMessage(
        messages: [AIMessage],
        model: String,
        config: AIGenerationConfig,
        tools: [AIToolDefinition],
        onStream: @escaping @Sendable (String) -> Void
    ) async throws -> AIResponse {
        let instructions = messages.first { $0.role == .system }?.content ?? Self.instructions
        let question = messages.last?.content ?? ""
        let browserTools: [any Tool] = try tools.filter { Self.toolNames.contains($0.name) }.map { try BrowserTool($0, run: runTool) }
        let options = GenerationOptions(temperature: config.temperature, maximumResponseTokens: min(config.maxTokens, Self.responseTokens))
        let earlier = Self.earlier(messages)

        func respond(to prompt: String) async throws -> String {
            let session = LanguageModelSession(model: Self.model, tools: browserTools, instructions: instructions)
            var text = ""
            do {
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    text = snapshot.content
                    onStream(text)
                }
            } catch {
                let ranTools = session.transcript.contains { if case .toolCalls = $0 { return true } else { return false } }
                throw FailedSession(error: error, ranTools: ranTools)
            }
            return text
        }

        do {
            return AIResponse(content: try await respond(to: earlier + question))
        } catch let failed as FailedSession where !earlier.isEmpty && failed.overflowed && !failed.ranTools {
            // Retrying after a tool ran would repeat what the tool did.
            do {
                return AIResponse(content: try await respond(to: question))
            } catch let failed as FailedSession {
                throw OnDeviceError(failed.error) ?? failed.error
            }
        } catch let failed as FailedSession {
            throw OnDeviceError(failed.error) ?? failed.error
        }
    }

    /// The newest earlier turns that fit the history budget, oldest first.
    private static func earlier(_ messages: [AIMessage]) -> String {
        var budget = historyTokens
        var lines: [String] = []
        for message in messages.dropLast().reversed() where message.role == .user || message.role == .assistant {
            let line = (message.role == .user ? "Person: " : "You: ") + message.content
            budget -= estimatedTokens(line)
            guard budget >= 0 else { break }
            lines.insert(line, at: 0)
        }
        return lines.isEmpty ? "" : "Earlier in this conversation:\n\(lines.joined(separator: "\n"))\n\n"
    }

    // MARK: - Token Estimates

    /// ponytail: a character heuristic, 4 ASCII characters or 1 other character per token, which
    /// overcounts accented Latin; use the model's own count once the SDK floor reaches 26.4.
    static func estimatedTokens(_ text: String) -> Int {
        (text.reduce(0) { $0 + quarterTokens($1) } + 3) / 4
    }

    /// The longest start of `text` within `tokens`, with an ellipsis when it was cut.
    static func fitted(_ text: String, tokens: Int) -> String {
        var budget = tokens * 4
        var end = text.startIndex
        for index in text.indices {
            budget -= quarterTokens(text[index])
            guard budget >= 0 else { return String(text[..<end]) + "…" }
            end = text.index(after: index)
        }
        return text
    }

    private static func quarterTokens(_ character: Character) -> Int {
        character.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 4) }
    }
}

// MARK: - Errors

/// A failed generation, noting whether a tool had already run.
private struct FailedSession: Error {
    let error: Error
    let ranTools: Bool

    var overflowed: Bool { OnDeviceError(error) == .pageTooLong }
}

/// The framework's errors that a person can act on, in plain words. Matched by case name: macOS 27
/// throws the 27 SDK's `LanguageModelError`, which CI's Xcode may not have, in place of the 26 SDK's
/// `GenerationError`. Switch to the typed error once the SDK floor is 27.
private enum OnDeviceError: LocalizedError {
    case pageTooLong
    case unsupportedLanguage
    case declined

    init?(_ error: Error) {
        guard String(reflecting: type(of: error)).hasPrefix("FoundationModels.") else { return nil }
        switch Mirror(reflecting: error).children.first?.label {
        case "exceededContextWindowSize", "contextSizeExceeded": self = .pageTooLong
        case "unsupportedLanguageOrLocale": self = .unsupportedLanguage
        case "guardrailViolation", "refusal": self = .declined
        default: return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .pageTooLong: return "This page is too long for the on-device model."
        case .unsupportedLanguage: return "The on-device model doesn't support this page's language."
        case .declined: return "Apple Intelligence can't answer questions about this content."
        }
    }
}

// MARK: - Browser Tool

/// One browser tool as the framework sees it. Calls go back through `AIService`, so they get the
/// same approval prompts, per-tool switches and private-window refusal as every other provider's.
private struct BrowserTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @MainActor @Sendable (String, String) async -> String

    init(_ definition: AIToolDefinition, run: @escaping @MainActor @Sendable (String, String) async -> String) throws {
        let properties = definition.parameters["properties"] as? [String: [String: Any]] ?? [:]
        let required = definition.parameters["required"] as? [String] ?? []
        let root = DynamicGenerationSchema(name: definition.name, properties: properties.sorted { $0.key < $1.key }.map { key, spec in
            DynamicGenerationSchema.Property(
                name: key,
                description: spec["description"] as? String,
                schema: Self.schema(forJSONType: spec["type"] as? String),
                isOptional: !required.contains(key)
            )
        })
        self.name = definition.name
        self.description = definition.description
        self.parameters = try GenerationSchema(root: root, dependencies: [])
        self.run = run
    }

    func call(arguments: GeneratedContent) async throws -> String {
        await run(name, arguments.jsonString)
    }

    /// The browser tools take strings, booleans and integers only.
    private static func schema(forJSONType type: String?) -> DynamicGenerationSchema {
        switch type {
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        case "integer": return DynamicGenerationSchema(type: Int.self)
        default: return DynamicGenerationSchema(type: String.self)
        }
    }
}
