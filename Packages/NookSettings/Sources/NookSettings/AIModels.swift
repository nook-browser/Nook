// Licensed under GPL-3.0. See LICENSE.
//
//  AIModels.swift
//  Nook
//
//  Core AI data models for the provider-agnostic AI system
//

import Foundation

// MARK: - Provider Configuration

public enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case gemini = "gemini"
    case openRouter = "openrouter"
    case ollama = "ollama"
    case openAICompatible = "openai_compatible"
    case appleIntelligence = "apple_intelligence"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        case .openAICompatible: return "OpenAI Compatible"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .gemini, .openRouter: return true
        case .ollama, .openAICompatible, .appleIntelligence: return false
        }
    }

    public var defaultBaseURL: String? {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434"
        case .openAICompatible, .appleIntelligence: return nil
        }
    }
}

public struct AIProviderConfig: Codable, Identifiable, Equatable {
    public let id: String
    public var displayName: String
    public var providerType: AIProviderType
    public var baseURL: String
    public var isEnabled: Bool
    public var customHeaders: [String: String]

    /// The API key is not part of the config: it lives in the Keychain, reached through the
    /// app-side `apiKey` extension in `Nook/Models/AI/AIKeychainStorage.swift`.
    public init(
        id: String = UUID().uuidString,
        displayName: String,
        providerType: AIProviderType,
        baseURL: String? = nil,
        isEnabled: Bool = true,
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.providerType = providerType
        self.baseURL = baseURL ?? providerType.defaultBaseURL ?? ""
        self.isEnabled = isEnabled
        self.customHeaders = customHeaders
    }

    // Custom CodingKeys to exclude apiKey from JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case providerType
        case baseURL
        case isEnabled
        case customHeaders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.providerType = try container.decode(AIProviderType.self, forKey: .providerType)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.customHeaders = try container.decode([String: String].self, forKey: .customHeaders)
        // apiKey is loaded from Keychain via computed property
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(providerType, forKey: .providerType)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(customHeaders, forKey: .customHeaders)
        // apiKey is NOT encoded - it's stored in Keychain
    }
}

// MARK: - Model Configuration

public struct AIModelCapabilities: Codable, Equatable {
    public var toolCalling: Bool
    public var streaming: Bool
    public var webSearch: Bool
    public var contextWindow: Int
    public var maxOutput: Int

    public init(
        toolCalling: Bool = false,
        streaming: Bool = true,
        webSearch: Bool = false,
        contextWindow: Int = 128_000,
        maxOutput: Int = 4096
    ) {
        self.toolCalling = toolCalling
        self.streaming = streaming
        self.webSearch = webSearch
        self.contextWindow = contextWindow
        self.maxOutput = maxOutput
    }
}

public struct AIModelConfig: Codable, Identifiable, Equatable {
    public let id: String
    public var displayName: String
    public var providerId: String
    public var isCustom: Bool
    public var capabilities: AIModelCapabilities

    public init(
        id: String,
        displayName: String,
        providerId: String,
        isCustom: Bool = false,
        capabilities: AIModelCapabilities = AIModelCapabilities()
    ) {
        self.id = id
        self.displayName = displayName
        self.providerId = providerId
        self.isCustom = isCustom
        self.capabilities = capabilities
    }
}

// MARK: - Generation Configuration

public struct AIGenerationConfig: Codable, Equatable {
    public var temperature: Double
    public var maxTokens: Int
    public var systemPrompt: String
    public var streamingEnabled: Bool
    public var webSearchEnabled: Bool
    public var webSearchEngine: String
    public var webSearchMaxResults: Int
    public var webSearchContextSize: String

    public static let defaultSystemPrompt = """
    You are the assistant in Nook, a web browser, shown in a narrow sidebar beside the page.

    The page the person is viewing arrives inside page_context tags: its title, URL and the first 8,000 characters of its text. Longer pages are cut off, so when the answer may be further down, use searchInPage or readPageContent before saying the page does not cover it.

    Answer the question asked, in the person's language, as briefly as it allows, and point to the part of the page you used. When the page does not say, tell them so. Never make up facts, figures or links. Short paragraphs and bullet lists read well in the sidebar; tables do not.

    When the person asks you to do something in the browser, do it with your tools rather than describing it. For a task with several steps, act, check the result with getInteractiveElements, and continue until it is done. Stop and ask before anything that spends money, sends a message, deletes data or submits a form for them.
    """

    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 4096,
        systemPrompt: String = AIGenerationConfig.defaultSystemPrompt,
        streamingEnabled: Bool = true,
        webSearchEnabled: Bool = false,
        webSearchEngine: String = "auto",
        webSearchMaxResults: Int = 5,
        webSearchContextSize: String = "medium"
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.streamingEnabled = streamingEnabled
        self.webSearchEnabled = webSearchEnabled
        self.webSearchEngine = webSearchEngine
        self.webSearchMaxResults = webSearchMaxResults
        self.webSearchContextSize = webSearchContextSize
    }
}

// MARK: - Browser Tool Configuration

public enum BrowserToolExecutionMode: String, Codable, CaseIterable, Identifiable {
    case auto = "auto"
    case askBeforeExecuting = "ask"
    case disabled = "disabled"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .askBeforeExecuting: return "Ask Before Executing"
        case .disabled: return "Disabled"
        }
    }
}

public struct BrowserToolsConfig: Codable, Equatable {
    public var executionMode: BrowserToolExecutionMode
    public var enabledTools: Set<String>

    public static let allToolNames: Set<String> = [
        "navigateToURL", "readPageContent", "clickElement",
        "getInteractiveElements",
        "extractStructuredData", "summarizePage", "searchInPage",
        "getTabList", "switchTab", "createTab", "getSelectedText",
        "executeJavaScript"
    ]

    public init(
        executionMode: BrowserToolExecutionMode = .askBeforeExecuting,
        enabledTools: Set<String> = BrowserToolsConfig.allToolNames
    ) {
        self.executionMode = executionMode
        self.enabledTools = enabledTools
    }
}

// MARK: - Full AI Configuration

public struct AIConfiguration: Codable {
    public var providers: [AIProviderConfig]
    public var models: [AIModelConfig]
    public var activeProviderId: String?
    public var activeModelId: String?
    public var generationConfig: AIGenerationConfig
    public var mcpServers: [MCPServerConfig]
    public var browserToolsConfig: BrowserToolsConfig

    public init(
        providers: [AIProviderConfig] = [],
        models: [AIModelConfig] = [],
        activeProviderId: String? = nil,
        activeModelId: String? = nil,
        generationConfig: AIGenerationConfig = AIGenerationConfig(),
        mcpServers: [MCPServerConfig] = [],
        browserToolsConfig: BrowserToolsConfig = BrowserToolsConfig()
    ) {
        self.providers = providers
        self.models = models
        self.activeProviderId = activeProviderId
        self.activeModelId = activeModelId
        self.generationConfig = generationConfig
        self.mcpServers = mcpServers
        self.browserToolsConfig = browserToolsConfig
    }
}
