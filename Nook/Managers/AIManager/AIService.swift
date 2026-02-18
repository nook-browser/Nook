//
//  AIService.swift
//  Nook
//
//  Central AI service orchestrator - manages providers, conversations, and tool execution
//

import Foundation
import OSLog
import WebKit

@MainActor
@Observable
class AIService {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AIService")

    let configService: AIConfigService

    // Conversation state
    var messages: [ChatMessage] = []
    var isLoading: Bool = false
    var streamingText: String = ""
    var isExecutingTools: Bool = false
    var currentToolName: String? = nil

    // References set externally after init
    weak var browserManager: BrowserManager?
    var browserToolExecutor: BrowserToolExecutor?
    var mcpManager: MCPManager?

    // Max agentic tool-call iterations to prevent infinite loops
    private let maxToolIterations = 20

    init(configService: AIConfigService) {
        self.configService = configService
    }

    // MARK: - Provider Factory

    private func createProvider() -> AIProviderProtocol? {
        guard let providerConfig = configService.activeProvider else { return nil }

        switch providerConfig.providerType {
        case .gemini:
            return GeminiProvider(apiKey: providerConfig.apiKey, baseURL: providerConfig.baseURL)
        case .openRouter:
            return OpenRouterProvider(apiKey: providerConfig.apiKey, baseURL: providerConfig.baseURL)
        case .ollama:
            return OllamaProvider(baseURL: providerConfig.baseURL)
        case .openAICompatible:
            return OpenAICompatibleProvider(
                apiKey: providerConfig.apiKey,
                baseURL: providerConfig.baseURL,
                customHeaders: providerConfig.customHeaders
            )
        }
    }

    // MARK: - Has API Key

    var hasApiKey: Bool {
        guard let provider = configService.activeProvider else { return false }
        if !provider.providerType.requiresAPIKey { return true }
        return !provider.apiKey.isEmpty
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, windowState: BrowserWindowState) async {
        guard !text.isEmpty, hasApiKey else { return }

        // Wire the current window state to the tool executor so browser tools know which window to act on
        browserToolExecutor?.windowState = windowState

        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        messages.append(userMessage)
        isLoading = true
        streamingText = ""

        do {
            // Extract page context
            let pageContext = await extractPageContext(windowState: windowState)
            let fullPrompt = pageContext + text

            guard let provider = createProvider() else {
                throw AIProviderError.invalidAPIKey
            }

            guard let modelId = configService.config.activeModelId else {
                throw AIProviderError.unsupportedFeature("No model selected")
            }

            let config = configService.generationConfig

            // Build initial message list
            var aiMessages: [AIMessage] = [
                AIMessage(role: .system, content: config.systemPrompt)
            ]

            // Add conversation history (exclude last user message, we'll add it with context)
            for msg in messages.dropLast() {
                let role: AIMessageRole = msg.role == .user ? .user : .assistant
                aiMessages.append(AIMessage(role: role, content: msg.content))
            }

            // Add current user message with page context
            aiMessages.append(AIMessage(role: .user, content: fullPrompt))

            // Collect available tools
            let tools = collectAvailableTools()

            // Agentic loop
            var response = try await provider.sendMessage(
                messages: aiMessages,
                model: modelId,
                config: config,
                tools: tools,
                onStream: { [weak self] chunk in
                    Task { @MainActor in
                        self?.streamingText += chunk
                    }
                }
            )

            var iterations = 0
            if response.finishReason == .toolCalls {
                isExecutingTools = true
            }
            while response.finishReason == .toolCalls && iterations < maxToolIterations {
                iterations += 1
                Self.log.info("Tool call iteration \(iterations): \(response.toolCalls.count) calls")

                // Add assistant message with tool calls
                aiMessages.append(AIMessage(
                    role: .assistant,
                    content: response.content,
                    toolCalls: response.toolCalls
                ))

                // Execute tool calls
                var toolResults: [AIToolResult] = []
                for toolCall in response.toolCalls {
                    currentToolName = toolCall.name
                    let result = await executeToolCall(toolCall)
                    toolResults.append(result)
                }

                // Add tool results
                aiMessages.append(AIMessage(
                    role: .tool,
                    content: "",
                    toolResults: toolResults
                ))

                // Send back to provider for next step
                streamingText = ""
                response = try await provider.sendMessage(
                    messages: aiMessages,
                    model: modelId,
                    config: config,
                    tools: tools,
                    onStream: { [weak self] chunk in
                        Task { @MainActor in
                            self?.streamingText += chunk
                        }
                    }
                )
            }
            isExecutingTools = false
            currentToolName = nil

            // Create assistant message
            var assistantMessage = ChatMessage(
                role: .assistant,
                content: response.content,
                timestamp: Date()
            )
            assistantMessage.citations = response.citations
            assistantMessage.usedWebSearch = config.webSearchEnabled && !response.citations.isEmpty
            messages.append(assistantMessage)

        } catch {
            isExecutingTools = false
            currentToolName = nil
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                timestamp: Date()
            )
            messages.append(errorMessage)
            Self.log.error("AI error: \(error.localizedDescription)")
        }

        isLoading = false
        streamingText = ""
    }

    // MARK: - Clear Messages

    func clearMessages() {
        messages.removeAll()
    }

    // MARK: - Tool Collection

    private func collectAvailableTools() -> [AIToolDefinition] {
        var tools: [AIToolDefinition] = []

        // Browser tools
        let browserConfig = configService.browserToolsConfig
        if browserConfig.executionMode != .disabled {
            if let browserToolExecutor = browserToolExecutor {
                tools.append(contentsOf: browserToolExecutor.availableToolDefinitions(enabledTools: browserConfig.enabledTools))
            }
        }

        // MCP tools
        if let mcpManager = mcpManager {
            for tool in mcpManager.allTools {
                tools.append(AIToolDefinition(
                    name: tool.qualifiedName,
                    description: tool.description,
                    parameters: tool.inputSchema
                ))
            }
        }

        return tools
    }

    // MARK: - Tool Execution

    private func executeToolCall(_ toolCall: AIToolCall) async -> AIToolResult {
        // Check if it's a browser tool
        if let browserToolExecutor = browserToolExecutor,
           BrowserToolsConfig.allToolNames.contains(toolCall.name) {
            do {
                return try await browserToolExecutor.execute(toolCall)
            } catch {
                return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "Error: \(error.localizedDescription)", isError: true)
            }
        }

        // Check if it's an MCP tool
        if let mcpManager = mcpManager,
           toolCall.name.contains(".") {
            let parts = toolCall.name.split(separator: ".", maxSplits: 1)
            if parts.count == 2 {
                let serverId = String(parts[0])
                let toolName = String(parts[1])
                do {
                    let result = try await mcpManager.callTool(serverId: serverId, name: toolName, arguments: toolCall.arguments)
                    return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: result)
                } catch {
                    return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "MCP Error: \(error.localizedDescription)", isError: true)
                }
            }
        }

        return AIToolResult(toolCallId: toolCall.id, toolName: toolCall.name, content: "Unknown tool: \(toolCall.name)", isError: true)
    }

    // MARK: - Page Context Extraction

    func extractPageContext(windowState: BrowserWindowState) async -> String {
        guard let browserManager = browserManager,
              let currentTab = browserManager.currentTab(for: windowState),
              let webView = browserManager.getWebView(for: currentTab.id, in: windowState.id) else {
            return ""
        }

        let script = """
        (function() {
            const title = document.title;
            const url = window.location.href;

            const clone = document.body.cloneNode(true);
            const scripts = clone.querySelectorAll('script, style, noscript');
            scripts.forEach(el => el.remove());

            let text = clone.innerText || clone.textContent || '';
            text = text.replace(/\\s+/g, ' ').trim();

            if (text.length > 8000) {
                text = text.substring(0, 8000) + '...';
            }

            return {
                title: title,
                url: url,
                content: text
            };
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)

            if let dict = result as? [String: Any],
               let title = dict["title"] as? String,
               let url = dict["url"] as? String,
               let content = dict["content"] as? String {
                return """
                [Current Page Context]
                Title: \(title)
                URL: \(url)

                Page Content:
                \(content)

                ---
                User Question:\u{0020}
                """
            }
        } catch {
            Self.log.error("Failed to extract page content: \(error.localizedDescription)")
        }

        return ""
    }
}
