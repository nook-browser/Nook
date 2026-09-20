// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookSettingsService.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import Foundation
import Observation


@MainActor
@Observable
public final class NookSettingsService {
    private let userDefaults = UserDefaults.standard
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
    private let browserControlServerKey = "settings.browserControlServer"
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
    private let youTubeHideShortsKey = "settings.youTubeHideShorts"
    private let youTubeHiddenHomeSectionsKey = "settings.youTubeHiddenHomeSections"
    private let youTubeVideosPerRowKey = "settings.youTubeVideosPerRow"
    private let youTubeFrameThumbnailsKey = "settings.youTubeFrameThumbnails"
    private let youTubeNoHoverPreviewKey = "settings.youTubeNoHoverPreview"
    private let legacySocialImageDownloadKey = "settings.socialImageDownload"
    private let instagramDownloadKey = "settings.instagramDownload"
    private let facebookDownloadKey = "settings.facebookDownload"
    private let vscoDownloadKey = "settings.vscoDownload"
    private let mediaDownloadSitesKey = "settings.mediaDownloadSites"
    private let facebookHideReelsKey = "settings.facebookHideReels"
    private let facebookHideSuggestedKey = "settings.facebookHideSuggested"

    public var searchEngineId: String {
        didSet {
            userDefaults.set(searchEngineId, forKey: searchEngineKey)
        }
    }

    public var customSearchEngines: [CustomSearchEngine] {
        didSet {
            if let data = try? JSONEncoder().encode(customSearchEngines) {
                userDefaults.set(data, forKey: customSearchEnginesKey)
            }
        }
    }

    public var siteRoutingRules: [SiteRoutingRule] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(siteRoutingRules) {
                userDefaults.set(data, forKey: siteRoutingRulesKey)
            }
        }
    }

    /// Resolves the current `searchEngineId` to a query template string.
    /// Checks built-in `SearchProvider` cases first, then custom engines.
    public var resolvedSearchEngineTemplate: String {
        if let provider = SearchProvider(rawValue: searchEngineId) {
            return provider.queryTemplate
        }
        if let custom = customSearchEngines.first(where: { $0.id.uuidString == searchEngineId }) {
            return custom.urlTemplate
        }
        return SearchProvider.google.queryTemplate
    }
    
    public var tabManagementMode: TabManagementMode {
        didSet {
            userDefaults.set(tabManagementMode.rawValue, forKey: tabManagementModeKey)
            NotificationCenter.default.post(
                name: .tabManagementModeChanged,
                object: nil,
                userInfo: ["mode": tabManagementMode.rawValue]
            )
        }
    }

    public var startupLoadMode: StartupLoadMode {
        didSet {
            userDefaults.set(startupLoadMode.rawValue, forKey: startupLoadModeKey)
        }
    }

    public var tabUnloadTimeout: TimeInterval {
        tabManagementMode.unloadTimeout
    }

    public var blockCrossSiteTracking: Bool {
        didSet {
            userDefaults.set(blockCrossSiteTracking, forKey: blockXSTKey)
            NotificationCenter.default.post(name: .blockCrossSiteTrackingChanged, object: nil, userInfo: ["enabled": blockCrossSiteTracking])
        }
    }

    public var adBlockerEnabled: Bool {
        didSet {
            userDefaults.set(adBlockerEnabled, forKey: adBlockerEnabledKey)
            NotificationCenter.default.post(name: .adBlockerEnabledChanged, object: nil, userInfo: ["enabled": adBlockerEnabled])
        }
    }

    public var adBlockerWhitelist: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(adBlockerWhitelist) {
                userDefaults.set(data, forKey: adBlockerWhitelistKey)
            }
        }
    }

    public var pinnedExtensionIDs: [String] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedExtensionIDs) {
                userDefaults.set(data, forKey: pinnedExtensionIDsKey)
            }
        }
    }

    public var adBlockerLastUpdate: Date? {
        didSet {
            userDefaults.set(adBlockerLastUpdate, forKey: adBlockerLastUpdateKey)
        }
    }

    public var enabledOptionalFilterLists: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(enabledOptionalFilterLists) {
                userDefaults.set(data, forKey: "settings.enabledOptionalFilterLists")
            }
        }
    }
    
    public var askBeforeQuit: Bool {
        didSet {
            userDefaults.set(askBeforeQuit, forKey: askBeforeQuitKey)
        }
    }
    
    public var sidebarPosition: SidebarPosition {
        didSet {
            userDefaults.set(sidebarPosition.rawValue, forKey: sidebarPositionKey)
        }
    }
    
    public var topBarAddressView: Bool {
        didSet {
            userDefaults.set(topBarAddressView, forKey: topBarAddressViewKey)
        }
    }

    public var appearanceMode: AppearanceMode {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            NotificationCenter.default.post(name: .appearanceModeChanged, object: nil)
        }
    }

    public var debugToggleUpdateNotification: Bool {
        didSet {
            userDefaults.set(debugToggleUpdateNotification, forKey: debugToggleUpdateNotificationKey)
        }
    }


    public var geminiApiKey: String

    public var geminiModel: GeminiModel {
        didSet {
            userDefaults.set(geminiModel.rawValue, forKey: geminiModelKey)
        }
    }

    public var showAIAssistant: Bool {
        didSet {
            userDefaults.set(showAIAssistant, forKey: showAIAssistantKey)
        }
    }

    /// Local MCP server (127.0.0.1:47823) that lets a coding agent drive this browser.
    /// Off by default: anything that can read the token file gets full control of the
    /// browser, including pages the user is signed in to. See DevMCPServer.
    public var browserControlServerEnabled: Bool {
        didSet {
            userDefaults.set(browserControlServerEnabled, forKey: browserControlServerKey)
        }
    }

    public var aiProvider: AIProvider {
        didSet {
            userDefaults.set(aiProvider.rawValue, forKey: aiProviderKey)
        }
    }

    public var openRouterApiKey: String

    public var openRouterModel: OpenRouterModel {
        didSet {
            userDefaults.set(openRouterModel.rawValue, forKey: openRouterModelKey)
        }
    }

    public var ollamaEndpoint: String {
        didSet {
            userDefaults.set(ollamaEndpoint, forKey: ollamaEndpointKey)
        }
    }

    public var ollamaModel: String {
        didSet {
            userDefaults.set(ollamaModel, forKey: ollamaModelKey)
        }
    }

    public var webSearchEnabled: Bool {
        didSet {
            userDefaults.set(webSearchEnabled, forKey: webSearchEnabledKey)
        }
    }

    public var webSearchEngine: String {
        didSet {
            userDefaults.set(webSearchEngine, forKey: webSearchEngineKey)
        }
    }

    public var webSearchMaxResults: Int {
        didSet {
            userDefaults.set(webSearchMaxResults, forKey: webSearchMaxResultsKey)
        }
    }

    public var webSearchContextSize: String {
        didSet {
            userDefaults.set(webSearchContextSize, forKey: webSearchContextSizeKey)
        }
    }
    
    public var showLinkStatusBar: Bool {
        didSet {
            userDefaults.set(showLinkStatusBar, forKey: showLinkStatusBarKey)
        }
    }
    
    public var siteSearchEntries: [SiteSearchEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(siteSearchEntries) {
                userDefaults.set(data, forKey: siteSearchEntriesKey)
            }
        }
    }
    
    public var tabLayout: TabLayout {
        didSet {
            userDefaults.set(tabLayout.rawValue, forKey: tabLayoutKey)
            // When tabs are on top, URL bar can't be in the sidebar
            if tabLayout == .topOfWindow && !topBarAddressView {
                topBarAddressView = true
            }
        }
    }

    public var didFinishOnboarding: Bool {
        didSet {
            userDefaults.set(didFinishOnboarding, forKey: didFinishOnboardingKey)
        }
    }

    public var tabOrganizerEnabled: Bool {
        didSet {
            userDefaults.set(tabOrganizerEnabled, forKey: tabOrganizerEnabledKey)
        }
    }

    public var tabOrganizerModelDownloaded: Bool {
        didSet {
            userDefaults.set(tabOrganizerModelDownloaded, forKey: tabOrganizerModelDownloadedKey)
        }
    }

    public var tabOrganizerIdleTimeout: TimeInterval {
        didSet {
            userDefaults.set(tabOrganizerIdleTimeout, forKey: tabOrganizerIdleTimeoutKey)
        }
    }

    public var sponsorBlockEnabled: Bool {
        didSet {
            userDefaults.set(sponsorBlockEnabled, forKey: sponsorBlockEnabledKey)
        }
    }

    /// Per-category skip options: category rawValue → skip option rawValue ("auto", "manual", "disabled")
    public var sponsorBlockCategoryOptions: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(sponsorBlockCategoryOptions) {
                userDefaults.set(data, forKey: sponsorBlockCategoryOptionsKey)
            }
        }
    }

    public var youTubeHideShorts: Bool {
        didSet { userDefaults.set(youTubeHideShorts, forKey: youTubeHideShortsKey) }
    }

    /// `YouTubeHomeSection` raw values.
    public var youTubeHiddenHomeSections: [String] {
        didSet { userDefaults.set(youTubeHiddenHomeSections, forKey: youTubeHiddenHomeSectionsKey) }
    }

    /// 0 leaves YouTube's automatic layout; otherwise `YouTubeTweaks.videosPerRowRange`.
    public var youTubeVideosPerRow: Int {
        didSet { userDefaults.set(youTubeVideosPerRow, forKey: youTubeVideosPerRowKey) }
    }

    /// Replace video thumbnails with a frame from the video.
    public var youTubeFrameThumbnails: Bool {
        didSet { userDefaults.set(youTubeFrameThumbnails, forKey: youTubeFrameThumbnailsKey) }
    }

    /// Stop YouTube playing a video preview when the pointer rests on a card.
    public var youTubeNoHoverPreview: Bool {
        didSet { userDefaults.set(youTubeNoHoverPreview, forKey: youTubeNoHoverPreviewKey) }
    }

    /// Domains that show the download button over photos and videos. Suffix match, so
    /// "instagram.com" covers "www.instagram.com".
    public var mediaDownloadSites: [String] {
        didSet { userDefaults.set(mediaDownloadSites, forKey: mediaDownloadSitesKey) }
    }

    /// Remove the Reels carousel from Facebook's news feed.
    public var facebookHideReels: Bool {
        didSet { userDefaults.set(facebookHideReels, forKey: facebookHideReelsKey) }
    }

    /// Remove posts and units from groups, pages, and people the viewer does not follow.
    public var facebookHideSuggested: Bool {
        didSet { userDefaults.set(facebookHideSuggested, forKey: facebookHideSuggestedKey) }
    }

    public init() {
        // Register default values
        userDefaults.register(defaults: [
            searchEngineKey: SearchProvider.google.rawValue,
            tabManagementModeKey: TabManagementMode.standard.rawValue,
            blockXSTKey: false,
            adBlockerEnabledKey: false,
            debugToggleUpdateNotificationKey: false,
            askBeforeQuitKey: true,
            sidebarPositionKey: SidebarPosition.left.rawValue,
            topBarAddressViewKey: false,

            geminiModelKey: GeminiModel.flash.rawValue,
            showAIAssistantKey: true,
            browserControlServerKey: false,
            aiProviderKey: AIProvider.gemini.rawValue,
            openRouterModelKey: OpenRouterModel.gpt4o.rawValue,
            ollamaEndpointKey: "http://localhost:11434",
            ollamaModelKey: "llama3",
            webSearchEnabledKey: false,
            webSearchEngineKey: "auto",
            webSearchMaxResultsKey: 5,
            webSearchContextSizeKey: "medium",
            showLinkStatusBarKey: true,
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
        self.geminiApiKey = ""  // In-memory only; persistent storage via AIKeychainStorage
        self.geminiModel = GeminiModel(rawValue: userDefaults.string(forKey: geminiModelKey) ?? GeminiModel.flash.rawValue) ?? .flash
        self.showAIAssistant = userDefaults.bool(forKey: showAIAssistantKey)
        self.browserControlServerEnabled = userDefaults.bool(forKey: browserControlServerKey)
        self.aiProvider = AIProvider(rawValue: userDefaults.string(forKey: aiProviderKey) ?? AIProvider.gemini.rawValue) ?? .gemini
        self.openRouterApiKey = ""  // In-memory only; persistent storage via AIKeychainStorage
        self.openRouterModel = OpenRouterModel(rawValue: userDefaults.string(forKey: openRouterModelKey) ?? OpenRouterModel.gpt4o.rawValue) ?? .gpt4o
        self.ollamaEndpoint = userDefaults.string(forKey: ollamaEndpointKey) ?? "http://localhost:11434"
        self.ollamaModel = userDefaults.string(forKey: ollamaModelKey) ?? "llama3"
        self.webSearchEnabled = userDefaults.bool(forKey: webSearchEnabledKey)
        self.webSearchEngine = userDefaults.string(forKey: webSearchEngineKey) ?? "auto"
        self.webSearchMaxResults = userDefaults.integer(forKey: webSearchMaxResultsKey)
        self.webSearchContextSize = userDefaults.string(forKey: webSearchContextSizeKey) ?? "medium"
        self.showLinkStatusBar = userDefaults.bool(forKey: showLinkStatusBarKey)
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
        self.youTubeHideShorts = userDefaults.bool(forKey: youTubeHideShortsKey)
        self.youTubeHiddenHomeSections = userDefaults.stringArray(forKey: youTubeHiddenHomeSectionsKey) ?? []
        self.youTubeVideosPerRow = userDefaults.integer(forKey: youTubeVideosPerRowKey)
        self.youTubeFrameThumbnails = userDefaults.bool(forKey: youTubeFrameThumbnailsKey)
        self.youTubeNoHoverPreview = userDefaults.bool(forKey: youTubeNoHoverPreviewKey)
        // One setting covered all three sites, then three per-site ones; both seed the site list.
        if let sites = userDefaults.stringArray(forKey: mediaDownloadSitesKey) {
            self.mediaDownloadSites = sites
        } else {
            let defaults = userDefaults
            let legacyDownload = defaults.bool(forKey: legacySocialImageDownloadKey)
            let legacy = [
                (instagramDownloadKey, "instagram.com"),
                (facebookDownloadKey, "facebook.com"),
                (vscoDownloadKey, "vsco.co")
            ]
            self.mediaDownloadSites = legacy
                .filter { defaults.object(forKey: $0.0) as? Bool ?? legacyDownload }
                .map(\.1)
        }
        self.facebookHideReels = userDefaults.bool(forKey: facebookHideReelsKey)
        self.facebookHideSuggested = userDefaults.bool(forKey: facebookHideSuggestedKey)

        if let data = userDefaults.data(forKey: siteSearchEntriesKey),
           let decoded = try? JSONDecoder().decode([SiteSearchEntry].self, from: data) {
            self.siteSearchEntries = decoded
        } else {
            self.siteSearchEntries = SiteSearchEntry.defaultSites
        }

        // Remove any leftover plaintext API keys from before Keychain migration
        cleanupPlaintextApiKeys()
    }

    /// Call once after ExtensionManager is ready on first launch to pin all existing extensions.
    public func migrateExtensionPinStateIfNeeded(installedExtensionIDs: [String]) {
        let migrationKey = "settings.pinnedExtensionIDsMigrated"
        guard !userDefaults.bool(forKey: migrationKey) else { return }
        userDefaults.set(true, forKey: migrationKey)

        // Pin all currently installed extensions so existing users
        // see the same URL bar they had before the library button was added
        if pinnedExtensionIDs.isEmpty {
            pinnedExtensionIDs = installedExtensionIDs
        }
    }

    /// Remove plaintext API keys that may exist from before Keychain migration
    public func cleanupPlaintextApiKeys() {
        userDefaults.removeObject(forKey: geminiApiKeyKey)
        userDefaults.removeObject(forKey: openRouterApiKeyKey)
    }
}

// MARK: - AI Provider

public enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case openRouter = "openrouter"
    case ollama = "ollama"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        }
    }
    
    public var isRecommended: Bool {
        return false
    }
}

// MARK: - Gemini Model

public enum GeminiModel: String, CaseIterable, Identifiable {
    case flash = "gemini-flash-latest"
    case pro = "gemini-2.5-pro"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .flash: return "Gemini Flash"
        case .pro: return "Gemini 2.5 Pro"
        }
    }
    
    public var description: String {
        switch self {
        case .flash: return "Fast responses, great for quick questions"
        case .pro: return "Most capable model, best for complex analysis"
        }
    }
    
    public var icon: String {
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
    
    public var displayName: String {
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
    public static let tabManagementModeChanged = Notification.Name("tabManagementModeChanged")
    public static let blockCrossSiteTrackingChanged = Notification.Name("blockCrossSiteTrackingChanged")
    public static let appearanceModeChanged = Notification.Name("appearanceModeChanged")
    public static let adBlockerEnabledChanged = Notification.Name("adBlockerEnabledChanged")
    public static let adBlockerStateChanged = Notification.Name("adBlockerStateChanged")
}

// MARK: - Tab Layout

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum TabLayout: String, CaseIterable, Identifiable {
    case sidebar
    case topOfWindow

    public var id: String { rawValue }

    public var displayName: String {
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

    public var displayName: String {
        switch self {
        case .powerSaving: return "Power Saving"
        case .standard: return "Standard"
        case .performance: return "Performance"
        }
    }

    public var description: String {
        switch self {
        case .powerSaving: return "Aggressively unloads tabs to minimize memory and battery usage. Best for laptops on battery."
        case .standard:
            return "Balanced tab management for everyday browsing. Keeps up to "
                + "\(Self.memoryScaledTabCap) tabs loaded on this Mac, unloading the least recently used."
        case .performance: return "No limit on loaded tabs. For power users with lots of memory."
        }
    }

    public var icon: String {
        switch self {
        case .powerSaving: return "leaf.fill"
        case .standard: return "speedometer"
        case .performance: return "bolt.fill"
        }
    }

    public var unloadTimeout: TimeInterval {
        switch self {
        case .powerSaving: return 300       // 5 minutes
        case .standard: return 1800         // 30 minutes
        case .performance: return 14400     // 4 hours
        }
    }

    /// Ceiling on pages kept loaded. `nil` means no ceiling.
    ///
    /// This is a backstop, not the everyday policy: `unloadTimeout` and memory pressure do the
    /// routine work, which is what Chrome, Edge, Firefox and Safari all rely on. None of them
    /// caps by tab count, and WebKit removed its own 20-WebProcess limit years ago, so a cap that
    /// binds constantly would evict pages the user is actively cycling through.
    ///
    /// `standard` scales with the machine instead of picking a fixed number, the way WebKit sizes
    /// its own caches. At a measured median of ~150 MB per WebContent process, 1.5 tabs per GB
    /// budgets roughly a fifth of memory for web content: 12 tabs at 8 GB, 24 at 16 GB, 48 at 32 GB.
    /// The floor keeps small machines usable; the ceiling is where the timeout dominates anyway.
    public var maxLoadedTabs: Int? {
        switch self {
        case .powerSaving: return 8
        case .standard: return Self.memoryScaledTabCap
        case .performance: return nil
        }
    }

    static let memoryScaledTabCap: Int = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return min(48, max(8, Int((gigabytes * 1.5).rounded())))
    }()

    public var unloadsOnBackground: Bool {
        switch self {
        case .powerSaving: return true
        case .standard: return false
        case .performance: return false
        }
    }

    /// Number of tabs to keep loaded (in addition to current) under memory pressure.
    /// nil means use fraction-based approach instead.
    public var memoryPressureKeepCount: Int? {
        switch self {
        case .powerSaving: return 2
        case .standard: return nil
        case .performance: return nil
        }
    }

    /// Fraction of loaded tabs to unload under memory pressure (used when keepCount is nil).
    public var memoryPressureUnloadFraction: Double {
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

    public var displayName: String {
        switch self {
        case .nothing: return "Last Tab Only"
        case .favorites: return "Last Tab & Favorites"
        case .favoritesAndSpace: return "Last Tab, Favorites & Space"
        }
    }

    public var description: String {
        switch self {
        case .nothing: return "Only your last open tab is loaded. Other tabs load when selected."
        case .favorites: return "Your last open tab and favorites are loaded on start. Space tabs load when selected."
        case .favoritesAndSpace: return "Your last open tab, favorites, and current space tabs are loaded on start."
        }
    }
}
