//
//  NookSettingsService.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import AppKit
import SwiftUI

@MainActor
@Observable
class NookSettingsService {
    let keyboardShortcutManager = KeyboardShortcutManager()
    private let userDefaults = UserDefaults.standard
    private let materialKey = "settings.currentMaterialRaw"
    private let searchEngineKey = "settings.searchEngine"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let blockXSTKey = "settings.blockCrossSiteTracking"
    private let debugToggleUpdateNotificationKey = "settings.debugToggleUpdateNotification"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
    private let sidebarPositionKey = "settings.sidebarPosition"
    private let topBarAddressViewKey = "settings.topBarAddressView"
    private let experimentalExtensionsKey = "settings.experimentalExtensions"
    private let geminiApiKeyKey = "settings.geminiApiKey"
    private let geminiModelKey = "settings.geminiModel"
    private let showAIAssistantKey = "settings.showAIAssistant"
    private let aiProviderKey = "settings.aiProvider"
    private let openRouterApiKeyKey = "settings.openRouterApiKey"
    private let openRouterModelKey = "settings.openRouterModel"
    private let ollamaEndpointKey = "settings.ollamaEndpoint"
    private let ollamaModelKey = "settings.ollamaModel"
    private let webSearchEnabledKey = "settings.webSearchEnabled"
    private let webSearchEngineKey = "settings.webSearchEngine"
    private let webSearchMaxResultsKey = "settings.webSearchMaxResults"
    private let webSearchContextSizeKey = "settings.webSearchContextSize"
    private let showLinkStatusBarKey = "settings.showLinkStatusBar"
    var currentSettingsTab: SettingsTabs = .general

    var currentMaterialRaw: Int {
        didSet {
            userDefaults.set(currentMaterialRaw, forKey: materialKey)
        }
    }

    var currentMaterial: NSVisualEffectView.Material {
        get {
            NSVisualEffectView.Material(rawValue: currentMaterialRaw)
                ?? .selection
        }
        set { currentMaterialRaw = newValue.rawValue }
    }

    var searchEngine: SearchProvider {
        didSet {
            userDefaults.set(searchEngine.rawValue, forKey: searchEngineKey)
        }
    }
    
    var tabUnloadTimeout: TimeInterval {
        didSet {
            userDefaults.set(tabUnloadTimeout, forKey: tabUnloadTimeoutKey)
            // Notify compositor manager of timeout change
            NotificationCenter.default.post(name: .tabUnloadTimeoutChanged, object: nil, userInfo: ["timeout": tabUnloadTimeout])
        }
    }

    var blockCrossSiteTracking: Bool {
        didSet {
            userDefaults.set(blockCrossSiteTracking, forKey: blockXSTKey)
            NotificationCenter.default.post(name: .blockCrossSiteTrackingChanged, object: nil, userInfo: ["enabled": blockCrossSiteTracking])
        }
    }
    
    var askBeforeQuit: Bool {
        didSet {
            userDefaults.set(askBeforeQuit, forKey: askBeforeQuitKey)
        }
    }
    
    var sidebarPosition: SidebarPosition {
        didSet {
            userDefaults.set(sidebarPosition.rawValue, forKey: sidebarPositionKey)
        }
    }
    
    var topBarAddressView: Bool {
        didSet {
            userDefaults.set(topBarAddressView, forKey: topBarAddressViewKey)
        }
    }

    var debugToggleUpdateNotification: Bool {
        didSet {
            userDefaults.set(debugToggleUpdateNotification, forKey: debugToggleUpdateNotificationKey)
        }
    }

    var experimentalExtensions: Bool {
        didSet {
            userDefaults.set(experimentalExtensions, forKey: experimentalExtensionsKey)
        }
    }

    var geminiApiKey: String {
        didSet {
            userDefaults.set(geminiApiKey, forKey: geminiApiKeyKey)
        }
    }

    var geminiModel: GeminiModel {
        didSet {
            userDefaults.set(geminiModel.rawValue, forKey: geminiModelKey)
        }
    }

    var showAIAssistant: Bool {
        didSet {
            userDefaults.set(showAIAssistant, forKey: showAIAssistantKey)
        }
    }

    var aiProvider: AIProvider {
        didSet {
            userDefaults.set(aiProvider.rawValue, forKey: aiProviderKey)
        }
    }

    var openRouterApiKey: String {
        didSet {
            userDefaults.set(openRouterApiKey, forKey: openRouterApiKeyKey)
        }
    }

    var openRouterModel: OpenRouterModel {
        didSet {
            userDefaults.set(openRouterModel.rawValue, forKey: openRouterModelKey)
        }
    }

    var ollamaEndpoint: String {
        didSet {
            userDefaults.set(ollamaEndpoint, forKey: ollamaEndpointKey)
        }
    }

    var ollamaModel: String {
        didSet {
            userDefaults.set(ollamaModel, forKey: ollamaModelKey)
        }
    }

    var webSearchEnabled: Bool {
        didSet {
            userDefaults.set(webSearchEnabled, forKey: webSearchEnabledKey)
        }
    }

    var webSearchEngine: String {
        didSet {
            userDefaults.set(webSearchEngine, forKey: webSearchEngineKey)
        }
    }

    var webSearchMaxResults: Int {
        didSet {
            userDefaults.set(webSearchMaxResults, forKey: webSearchMaxResultsKey)
        }
    }

    var webSearchContextSize: String {
        didSet {
            userDefaults.set(webSearchContextSize, forKey: webSearchContextSizeKey)
        }
    }
    
    var showLinkStatusBar: Bool {
        didSet {
            userDefaults.set(showLinkStatusBar, forKey: showLinkStatusBarKey)
        }
    }

    init() {
        // Register default values
        userDefaults.register(defaults: [
            materialKey: NSVisualEffectView.Material.hudWindow.rawValue,
            searchEngineKey: SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            tabUnloadTimeoutKey: 3600.0,
            blockXSTKey: false,
            debugToggleUpdateNotificationKey: false,
            askBeforeQuitKey: true,
            sidebarPositionKey: SidebarPosition.left.rawValue,
            topBarAddressViewKey: false,
            experimentalExtensionsKey: false,
            geminiApiKeyKey: "",
            geminiModelKey: GeminiModel.flash.rawValue,
            showAIAssistantKey: true,
            aiProviderKey: AIProvider.gemini.rawValue,
            openRouterApiKeyKey: "",
            openRouterModelKey: OpenRouterModel.gpt4o.rawValue,
            ollamaEndpointKey: "http://localhost:11434",
            ollamaModelKey: "llama3",
            webSearchEnabledKey: false,
            webSearchEngineKey: "auto",
            webSearchMaxResultsKey: 5,
            webSearchContextSizeKey: "medium",
            showLinkStatusBarKey: true
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.currentMaterialRaw = userDefaults.integer(forKey: materialKey)

        if let rawEngine = userDefaults.string(forKey: searchEngineKey),
           let provider = SearchProvider(rawValue: rawEngine)
        {
            self.searchEngine = provider
        } else {
            // Fallback to google if the stored value is somehow invalid
            self.searchEngine = .google
        }
        
        // Initialize tab unload timeout
        self.tabUnloadTimeout = userDefaults.double(forKey: tabUnloadTimeoutKey)
        self.blockCrossSiteTracking = userDefaults.bool(forKey: blockXSTKey)
        self.debugToggleUpdateNotification = userDefaults.bool(forKey: debugToggleUpdateNotificationKey)
        self.askBeforeQuit = userDefaults.bool(forKey: askBeforeQuitKey)
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.topBarAddressView = userDefaults.bool(forKey: topBarAddressViewKey)
        self.experimentalExtensions = userDefaults.bool(forKey: experimentalExtensionsKey)
        self.geminiApiKey = userDefaults.string(forKey: geminiApiKeyKey) ?? ""
        self.geminiModel = GeminiModel(rawValue: userDefaults.string(forKey: geminiModelKey) ?? GeminiModel.flash.rawValue) ?? .flash
        self.showAIAssistant = userDefaults.bool(forKey: showAIAssistantKey)
        self.aiProvider = AIProvider(rawValue: userDefaults.string(forKey: aiProviderKey) ?? AIProvider.gemini.rawValue) ?? .gemini
        self.openRouterApiKey = userDefaults.string(forKey: openRouterApiKeyKey) ?? ""
        self.openRouterModel = OpenRouterModel(rawValue: userDefaults.string(forKey: openRouterModelKey) ?? OpenRouterModel.gpt4o.rawValue) ?? .gpt4o
        self.ollamaEndpoint = userDefaults.string(forKey: ollamaEndpointKey) ?? "http://localhost:11434"
        self.ollamaModel = userDefaults.string(forKey: ollamaModelKey) ?? "llama3"
        self.webSearchEnabled = userDefaults.bool(forKey: webSearchEnabledKey)
        self.webSearchEngine = userDefaults.string(forKey: webSearchEngineKey) ?? "auto"
        self.webSearchMaxResults = userDefaults.integer(forKey: webSearchMaxResultsKey)
        self.webSearchContextSize = userDefaults.string(forKey: webSearchContextSizeKey) ?? "medium"
        self.showLinkStatusBar = userDefaults.bool(forKey: showLinkStatusBarKey)
    }
}

// MARK: - AI Provider

public enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case openRouter = "openrouter"
    case ollama = "ollama"
    
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        }
    }
    
    var isRecommended: Bool {
        return false
    }
}

// MARK: - Gemini Model

public enum GeminiModel: String, CaseIterable, Identifiable {
    case flash = "gemini-flash-latest"
    case pro = "gemini-2.5-pro"
    
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .flash: return "Gemini Flash"
        case .pro: return "Gemini 2.5 Pro"
        }
    }
    
    var description: String {
        switch self {
        case .flash: return "Fast responses, great for quick questions"
        case .pro: return "Most capable model, best for complex analysis"
        }
    }
    
    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .pro: return "star.fill"
        }
    }
}

// MARK: - OpenRouter Model

public enum OpenRouterModel: String, CaseIterable, Identifiable {
    case deepseekChatV31 = "deepseek/deepseek-chat-v3.1:free"
    case glm45air = "z-ai/glm-4.5-air:free"
    case llama4scout = "meta-llama/llama-4-scout:free"
    case llama4maverick = "meta-llama/llama-4-maverick:free"
    case grok4fast = "openai/grok-4-fast"
    case gpt4o = "openai/gpt-4o"
    case claudesonnet45 = "anthropic/claude-sonnet-4.5"
    case llama370b = "meta-llama/llama-3-70b-instruct"
    case gpt5mini = "openai/gpt-5-mini"
    case gpt5 = "openai/gpt-5"

    
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .deepseekChatV31: return "DeepSeek Chat V3.1 (Free)"
        case .glm45air: return "GLM 4.5 Air (Free)"
        case .llama4scout: return "Llama 4 Scout (Free)"
        case .llama4maverick: return "Llama 4 Maverick (Free)"
        case .grok4fast: return "Grok 4 Fast"
        case .gpt4o: return "GPT-4o"
        case .claudesonnet45: return "Claude Sonnet 4.5"
        case .llama370b: return "Llama 3 70B"
        case .gpt5mini: return "GPT-5 Mini"
        case .gpt5: return "GPT-5"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
    static let blockCrossSiteTrackingChanged = Notification.Name("blockCrossSiteTrackingChanged")
}

// MARK: - Environment Key
private struct NookSettingsServiceKey: EnvironmentKey {
    @MainActor
    static var defaultValue: NookSettingsService {
        // This should never be called since we always inject from NookApp
        // But EnvironmentKey protocol requires a default value
        return NookSettingsService()
    }
}

extension EnvironmentValues {
    var nookSettings: NookSettingsService {
        get { self[NookSettingsServiceKey.self] }
        set { self[NookSettingsServiceKey.self] = newValue }
    }
}


import AppKit
import Foundation

public let materials: [(name: String, value: NSVisualEffectView.Material)] = [
    ("titlebar", .titlebar),
    ("menu", .menu),
    ("popover", .popover),
    ("sidebar", .sidebar),
    ("headerView", .headerView),
    ("sheet", .sheet),
    ("windowBackground", .windowBackground),
    ("Arc", .hudWindow),
    ("fullScreenUI", .fullScreenUI),
    ("toolTip", .toolTip),
    ("contentBackground", .contentBackground),
    ("underWindowBackground", .underWindowBackground),
    ("underPageBackground", .underPageBackground),
]

public func nameForMaterial(_ material: NSVisualEffectView.Material) -> String {
    materials.first(where: { $0.value == material })?.name
        ?? "raw(\(material.rawValue))"
}
