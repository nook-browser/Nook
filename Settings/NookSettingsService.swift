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
    private let userDefaults = UserDefaults.standard
    private let materialKey = "settings.currentMaterialRaw"
    private let searchEngineKey = "settings.searchEngine"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let tabManagementModeKey = "settings.tabManagementMode"
    private let startupLoadModeKey = "settings.startupLoadMode"
    private let blockXSTKey = "settings.blockCrossSiteTracking"
    private let adBlockerEnabledKey = "settings.adBlockerEnabled"
    private let adBlockerWhitelistKey = "settings.adBlockerWhitelist"
    private let adBlockerLastUpdateKey = "settings.adBlockerLastUpdate"
    private let debugToggleUpdateNotificationKey = "settings.debugToggleUpdateNotification"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
    private let sidebarPositionKey = "settings.sidebarPosition"
    private let topBarAddressViewKey = "settings.topBarAddressView"

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
    private let pinnedTabsLookKey = "settings.pinnedTabsLook"
    private let siteSearchEntriesKey = "settings.siteSearchEntries"
    private let didFinishOnboardingKey = "settings.didFinishOnboarding"
    private let tabLayoutKey = "settings.tabLayout"
    private let customSearchEnginesKey = "settings.customSearchEngines"
    private let appearanceModeKey = "settings.appearanceMode"
    private let pinnedExtensionIDsKey = "settings.pinnedExtensionIDs"
    private let tabOrganizerEnabledKey = "settings.tabOrganizerEnabled"
    private let tabOrganizerModelDownloadedKey = "settings.tabOrganizerModelDownloaded"
    private let tabOrganizerIdleTimeoutKey = "settings.tabOrganizerIdleTimeout"
    private let sponsorBlockEnabledKey = "settings.sponsorBlockEnabled"
    private let sponsorBlockCategoryOptionsKey = "settings.sponsorBlockCategoryOptions"
    private let siteRoutingRulesKey = "settings.siteRoutingRules"

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

    var searchEngineId: String {
        didSet {
            userDefaults.set(searchEngineId, forKey: searchEngineKey)
        }
    }

    var customSearchEngines: [CustomSearchEngine] {
        didSet {
            if let data = try? JSONEncoder().encode(customSearchEngines) {
                userDefaults.set(data, forKey: customSearchEnginesKey)
            }
        }
    }

    var siteRoutingRules: [SiteRoutingRule] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(siteRoutingRules) {
                userDefaults.set(data, forKey: siteRoutingRulesKey)
            }
        }
    }

    /// Resolves the current `searchEngineId` to a query template string.
    /// Checks built-in `SearchProvider` cases first, then custom engines.
    var resolvedSearchEngineTemplate: String {
        if let provider = SearchProvider(rawValue: searchEngineId) {
            return provider.queryTemplate
        }
        if let custom = customSearchEngines.first(where: { $0.id.uuidString == searchEngineId }) {
            return custom.urlTemplate
        }
        return SearchProvider.google.queryTemplate
    }
    
    var tabManagementMode: TabManagementMode {
        didSet {
            userDefaults.set(tabManagementMode.rawValue, forKey: tabManagementModeKey)
            NotificationCenter.default.post(
                name: .tabManagementModeChanged,
                object: nil,
                userInfo: ["mode": tabManagementMode.rawValue]
            )
        }
    }

    var startupLoadMode: StartupLoadMode {
        didSet {
            userDefaults.set(startupLoadMode.rawValue, forKey: startupLoadModeKey)
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

    var adBlockerEnabled: Bool {
        didSet {
            userDefaults.set(adBlockerEnabled, forKey: adBlockerEnabledKey)
            NotificationCenter.default.post(name: .adBlockerEnabledChanged, object: nil, userInfo: ["enabled": adBlockerEnabled])
        }
    }

    var adBlockerWhitelist: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(adBlockerWhitelist) {
                userDefaults.set(data, forKey: adBlockerWhitelistKey)
            }
        }
    }

    var pinnedExtensionIDs: [String] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedExtensionIDs) {
                userDefaults.set(data, forKey: pinnedExtensionIDsKey)
            }
        }
    }

    var adBlockerLastUpdate: Date? {
        didSet {
            userDefaults.set(adBlockerLastUpdate, forKey: adBlockerLastUpdateKey)
        }
    }

    var enabledOptionalFilterLists: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(enabledOptionalFilterLists) {
                userDefaults.set(data, forKey: "settings.enabledOptionalFilterLists")
            }
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

    var appearanceMode: AppearanceMode {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            NotificationCenter.default.post(name: .appearanceModeChanged, object: nil)
        }
    }

    var debugToggleUpdateNotification: Bool {
        didSet {
            userDefaults.set(debugToggleUpdateNotification, forKey: debugToggleUpdateNotificationKey)
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
    
    var pinnedTabsLook: PinnedTabsConfiguration {
        didSet {
            userDefaults.set(pinnedTabsLook, forKey: pinnedTabsLookKey)
        }
    }

    var siteSearchEntries: [SiteSearchEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(siteSearchEntries) {
                userDefaults.set(data, forKey: siteSearchEntriesKey)
            }
        }
    }
    
    var tabLayout: TabLayout {
        didSet {
            userDefaults.set(tabLayout.rawValue, forKey: tabLayoutKey)
            // When tabs are on top, URL bar can't be in the sidebar
            if tabLayout == .topOfWindow && !topBarAddressView {
                topBarAddressView = true
            }
        }
    }

    var didFinishOnboarding: Bool {
        didSet {
            userDefaults.set(didFinishOnboarding, forKey: didFinishOnboardingKey)
        }
    }

    var tabOrganizerEnabled: Bool {
        didSet {
            userDefaults.set(tabOrganizerEnabled, forKey: tabOrganizerEnabledKey)
        }
    }

    var tabOrganizerModelDownloaded: Bool {
        didSet {
            userDefaults.set(tabOrganizerModelDownloaded, forKey: tabOrganizerModelDownloadedKey)
        }
    }

    var tabOrganizerIdleTimeout: TimeInterval {
        didSet {
            userDefaults.set(tabOrganizerIdleTimeout, forKey: tabOrganizerIdleTimeoutKey)
        }
    }

    var sponsorBlockEnabled: Bool {
        didSet {
            userDefaults.set(sponsorBlockEnabled, forKey: sponsorBlockEnabledKey)
        }
    }

    /// Per-category skip options: category rawValue → skip option rawValue ("auto", "manual", "disabled")
    var sponsorBlockCategoryOptions: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(sponsorBlockCategoryOptions) {
                userDefaults.set(data, forKey: sponsorBlockCategoryOptionsKey)
            }
        }
    }

    init() {
        // Register default values
        userDefaults.register(defaults: [
            materialKey: NSVisualEffectView.Material.hudWindow.rawValue,
            searchEngineKey: SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            tabUnloadTimeoutKey: 3600.0,
            tabManagementModeKey: TabManagementMode.standard.rawValue,
            blockXSTKey: false,
            adBlockerEnabledKey: false,
            debugToggleUpdateNotificationKey: false,
            askBeforeQuitKey: true,
            sidebarPositionKey: SidebarPosition.left.rawValue,
            topBarAddressViewKey: false,

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
            showLinkStatusBarKey: true,
            pinnedTabsLookKey: "large",
            didFinishOnboardingKey: false,
            tabLayoutKey: TabLayout.sidebar.rawValue,
            appearanceModeKey: AppearanceMode.system.rawValue,
            tabOrganizerEnabledKey: false,
            tabOrganizerModelDownloadedKey: false,
            tabOrganizerIdleTimeoutKey: 300.0,
            sponsorBlockEnabledKey: false,
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.currentMaterialRaw = userDefaults.integer(forKey: materialKey)

        // searchEngineId: backward compatible — existing "google" string still works
        self.searchEngineId = userDefaults.string(forKey: searchEngineKey) ?? SearchProvider.google.rawValue

        if let ceData = userDefaults.data(forKey: customSearchEnginesKey),
           let decoded = try? JSONDecoder().decode([CustomSearchEngine].self, from: ceData) {
            self.customSearchEngines = decoded
        } else {
            self.customSearchEngines = []
        }

        if let srData = userDefaults.data(forKey: siteRoutingRulesKey),
           let decoded = try? JSONDecoder().decode([SiteRoutingRule].self, from: srData) {
            self.siteRoutingRules = decoded
        } else {
            self.siteRoutingRules = []
        }

        // Initialize tab unload timeout
        self.tabUnloadTimeout = userDefaults.double(forKey: tabUnloadTimeoutKey)

        // Initialize tab management mode (with migration from old timeout)
        let resolvedMode: TabManagementMode
        if userDefaults.object(forKey: tabManagementModeKey) == nil,
           let oldTimeout = userDefaults.object(forKey: tabUnloadTimeoutKey) as? Double {
            if oldTimeout <= 600 {
                resolvedMode = .powerSaving
            } else if oldTimeout <= 3600 {
                resolvedMode = .standard
            } else {
                resolvedMode = .performance
            }
            userDefaults.set(resolvedMode.rawValue, forKey: tabManagementModeKey)
        } else {
            resolvedMode = TabManagementMode(
                rawValue: userDefaults.string(forKey: tabManagementModeKey) ?? TabManagementMode.standard.rawValue
            ) ?? .standard
        }
        self.tabManagementMode = resolvedMode
        self.startupLoadMode = StartupLoadMode(
            rawValue: userDefaults.string(forKey: startupLoadModeKey) ?? ""
        ) ?? .favoritesAndSpace
        self.blockCrossSiteTracking = userDefaults.bool(forKey: blockXSTKey)
        self.adBlockerEnabled = userDefaults.bool(forKey: adBlockerEnabledKey)
        if let wlData = userDefaults.data(forKey: adBlockerWhitelistKey),
           let decoded = try? JSONDecoder().decode([String].self, from: wlData) {
            self.adBlockerWhitelist = decoded
        } else {
            self.adBlockerWhitelist = []
        }
        if let pinnedData = userDefaults.data(forKey: pinnedExtensionIDsKey),
           let pinnedIDs = try? JSONDecoder().decode([String].self, from: pinnedData) {
            self.pinnedExtensionIDs = pinnedIDs
        } else {
            self.pinnedExtensionIDs = []
        }
        self.adBlockerLastUpdate = userDefaults.object(forKey: adBlockerLastUpdateKey) as? Date
        if let optData = userDefaults.data(forKey: "settings.enabledOptionalFilterLists"),
           let optDecoded = try? JSONDecoder().decode([String].self, from: optData) {
            self.enabledOptionalFilterLists = optDecoded
        } else {
            self.enabledOptionalFilterLists = []
        }
        self.debugToggleUpdateNotification = userDefaults.bool(forKey: debugToggleUpdateNotificationKey)
        self.askBeforeQuit = userDefaults.bool(forKey: askBeforeQuitKey)
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.topBarAddressView = userDefaults.bool(forKey: topBarAddressViewKey)
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
        self.pinnedTabsLook = PinnedTabsConfiguration(rawValue: userDefaults.string(forKey: pinnedTabsLookKey) ?? "large") ?? .large
        self.tabLayout = TabLayout(rawValue: userDefaults.string(forKey: tabLayoutKey) ?? TabLayout.sidebar.rawValue) ?? .sidebar
        self.appearanceMode = AppearanceMode(rawValue: userDefaults.string(forKey: appearanceModeKey) ?? AppearanceMode.system.rawValue) ?? .system
        self.didFinishOnboarding = userDefaults.bool(forKey: didFinishOnboardingKey)
        self.tabOrganizerEnabled = userDefaults.bool(forKey: tabOrganizerEnabledKey)
        self.tabOrganizerModelDownloaded = userDefaults.bool(forKey: tabOrganizerModelDownloadedKey)
        self.tabOrganizerIdleTimeout = userDefaults.double(forKey: tabOrganizerIdleTimeoutKey)
        self.sponsorBlockEnabled = userDefaults.bool(forKey: sponsorBlockEnabledKey)
        if let sbData = userDefaults.data(forKey: sponsorBlockCategoryOptionsKey),
           let sbDecoded = try? JSONDecoder().decode([String: String].self, from: sbData) {
            self.sponsorBlockCategoryOptions = sbDecoded
        } else {
            self.sponsorBlockCategoryOptions = SponsorBlockCategory.defaultCategoryOptions
        }

        if let data = userDefaults.data(forKey: siteSearchEntriesKey),
           let decoded = try? JSONDecoder().decode([SiteSearchEntry].self, from: data) {
            self.siteSearchEntries = decoded
        } else {
            self.siteSearchEntries = SiteSearchEntry.defaultSites
        }
    }

    /// Call once after ExtensionManager is ready on first launch to pin all existing extensions.
    func migrateExtensionPinStateIfNeeded(installedExtensionIDs: [String]) {
        let migrationKey = "settings.pinnedExtensionIDsMigrated"
        guard !userDefaults.bool(forKey: migrationKey) else { return }
        userDefaults.set(true, forKey: migrationKey)

        // Pin all currently installed extensions so existing users
        // see the same URL bar they had before the library button was added
        if pinnedExtensionIDs.isEmpty {
            pinnedExtensionIDs = installedExtensionIDs
        }
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
    static let tabManagementModeChanged = Notification.Name("tabManagementModeChanged")
    static let blockCrossSiteTrackingChanged = Notification.Name("blockCrossSiteTrackingChanged")
    static let appearanceModeChanged = Notification.Name("appearanceModeChanged")
    static let adBlockerEnabledChanged = Notification.Name("adBlockerEnabledChanged")
    static let adBlockerStateChanged = Notification.Name("adBlockerStateChanged")
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

// MARK: - Tab Layout

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum TabLayout: String, CaseIterable, Identifiable {
    case sidebar
    case topOfWindow

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sidebar: return "Sidebar"
        case .topOfWindow: return "Top of Window"
        }
    }
}

// MARK: - Tab Management Mode

public enum TabManagementMode: String, CaseIterable, Identifiable {
    case powerSaving
    case standard
    case performance

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .powerSaving: return "Power Saving"
        case .standard: return "Standard"
        case .performance: return "Performance"
        }
    }

    var description: String {
        switch self {
        case .powerSaving: return "Aggressively unloads tabs to minimize memory and battery usage. Best for laptops on battery."
        case .standard: return "Balanced tab management for everyday browsing."
        case .performance: return "Keeps tabs loaded longer for power users with many tabs open."
        }
    }

    var icon: String {
        switch self {
        case .powerSaving: return "leaf.fill"
        case .standard: return "speedometer"
        case .performance: return "bolt.fill"
        }
    }

    var unloadTimeout: TimeInterval {
        switch self {
        case .powerSaving: return 300       // 5 minutes
        case .standard: return 1800         // 30 minutes
        case .performance: return 14400     // 4 hours
        }
    }

    var maxLoadedTabs: Int? {
        switch self {
        case .powerSaving: return 8
        case .standard: return nil
        case .performance: return nil
        }
    }

    var unloadsOnBackground: Bool {
        switch self {
        case .powerSaving: return true
        case .standard: return false
        case .performance: return false
        }
    }

    /// Number of tabs to keep loaded (in addition to current) under memory pressure.
    /// nil means use fraction-based approach instead.
    var memoryPressureKeepCount: Int? {
        switch self {
        case .powerSaving: return 2
        case .standard: return nil
        case .performance: return nil
        }
    }

    /// Fraction of loaded tabs to unload under memory pressure (used when keepCount is nil).
    var memoryPressureUnloadFraction: Double {
        switch self {
        case .powerSaving: return 1.0  // Not used — keepCount takes precedence for powerSaving
        case .standard: return 0.5
        case .performance: return 0.25
        }
    }
}

// MARK: - Startup Load Mode

public enum StartupLoadMode: String, CaseIterable, Identifiable {
    case nothing
    case favorites
    case favoritesAndSpace

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nothing: return "Last Tab Only"
        case .favorites: return "Last Tab & Favorites"
        case .favoritesAndSpace: return "Last Tab, Favorites & Space"
        }
    }

    var description: String {
        switch self {
        case .nothing: return "Only your last open tab is loaded. Other tabs load when selected."
        case .favorites: return "Your last open tab and favorites are loaded on start. Space tabs load when selected."
        case .favoritesAndSpace: return "Your last open tab, favorites, and current space tabs are loaded on start."
        }
    }
}
