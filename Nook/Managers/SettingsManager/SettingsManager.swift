//
//  SettingsManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

enum StartupTabMode: String, CaseIterable, Identifiable {
    case customURL
    case none
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .customURL: return "Open custom page"
        case .none: return "Open empty window"
        }
    }
}

@Observable
class SettingsManager {
    let keyboardShortcutManager = KeyboardShortcutManager()
    private let userDefaults = UserDefaults.standard
    private static let materialKey = "settings.currentMaterialRaw"
    private static let searchEngineKey = "settings.searchEngine"
    private static let liquidGlassKey = "settings.isLiquidGlassEnabled"
    private static let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private static let blockXSTKey = "settings.blockCrossSiteTracking"
    private static let debugToggleUpdateNotificationKey = "settings.debugToggleUpdateNotification"
    private static let askBeforeQuitKey = "settings.askBeforeQuit"
    private static let restoreSessionOnLaunchKey = "settings.restoreSessionOnLaunch"
    private static let startupTabModeKey = "settings.startupTabMode"
    private static let startupTabURLKey = "settings.startupTabURL"
    private static let sidebarPositionKey = "settings.sidebarPosition"
    private static let topBarAddressViewKey = "settings.topBarAddressView"
    private static let experimentalExtensionsKey = "settings.experimentalExtensions"
    private static let geminiApiKeyKey = "settings.geminiApiKey"
    private static let geminiModelKey = "settings.geminiModel"
    private static let showAIAssistantKey = "settings.showAIAssistant"
    var currentSettingsTab: SettingsTabs = .general

    // Stored properties
    var isLiquidGlassEnabled: Bool {
        didSet {
            userDefaults.set(isLiquidGlassEnabled, forKey: Self.liquidGlassKey)
        }
    }

    var currentMaterialRaw: Int {
        didSet {
            userDefaults.set(currentMaterialRaw, forKey: Self.materialKey)
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
            userDefaults.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }
    
    var tabUnloadTimeout: TimeInterval {
        didSet {
            userDefaults.set(tabUnloadTimeout, forKey: Self.tabUnloadTimeoutKey)
            // Notify compositor manager of timeout change
            NotificationCenter.default.post(name: .tabUnloadTimeoutChanged, object: nil, userInfo: ["timeout": tabUnloadTimeout])
        }
    }

    var blockCrossSiteTracking: Bool {
        didSet {
            userDefaults.set(blockCrossSiteTracking, forKey: Self.blockXSTKey)
            NotificationCenter.default.post(name: .blockCrossSiteTrackingChanged, object: nil, userInfo: ["enabled": blockCrossSiteTracking])
        }
    }
    
    var askBeforeQuit: Bool {
        didSet {
            userDefaults.set(askBeforeQuit, forKey: Self.askBeforeQuitKey)
        }
    }

    var restoreSessionOnLaunch: Bool {
        didSet {
            userDefaults.set(restoreSessionOnLaunch, forKey: Self.restoreSessionOnLaunchKey)
            NotificationCenter.default.post(
                name: .sessionPersistenceChanged,
                object: nil,
                userInfo: ["enabled": restoreSessionOnLaunch]
            )
        }
    }
    
    var sidebarPosition: SidebarPosition {
        didSet {
            userDefaults.set(sidebarPosition.rawValue, forKey: Self.sidebarPositionKey)
        }
    }
    
    var topBarAddressView: Bool {
        didSet {
            userDefaults.set(topBarAddressView, forKey: Self.topBarAddressViewKey)
        }
    }

    var debugToggleUpdateNotification: Bool {
        didSet {
            userDefaults.set(debugToggleUpdateNotification, forKey: Self.debugToggleUpdateNotificationKey)
        }
    }

    var experimentalExtensions: Bool {
        didSet {
            userDefaults.set(experimentalExtensions, forKey: Self.experimentalExtensionsKey)
        }
    }

    var geminiApiKey: String {
        didSet {
            userDefaults.set(geminiApiKey, forKey: Self.geminiApiKeyKey)
        }
    }

    var geminiModel: GeminiModel {
        didSet {
            userDefaults.set(geminiModel.rawValue, forKey: Self.geminiModelKey)
        }
    }

    var showAIAssistant: Bool {
        didSet {
            userDefaults.set(showAIAssistant, forKey: Self.showAIAssistantKey)
        }
    }
    
    static let defaultStartupURL = "https://www.google.com"

    static func persistedStartupConfiguration(defaults: UserDefaults = .standard) -> (mode: StartupTabMode, url: String) {
        let rawMode = defaults.string(forKey: Self.startupTabModeKey)
        let mode = rawMode.flatMap(StartupTabMode.init(rawValue:)) ?? .customURL
        let url = defaults.string(forKey: Self.startupTabURLKey) ?? defaultStartupURL
        return (mode, url)
    }

    static func persistedRestoreSessionFlag(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Self.restoreSessionOnLaunchKey) as? Bool ?? true
    }
    
    var startupTabMode: StartupTabMode {
        didSet {
            userDefaults.set(startupTabMode.rawValue, forKey: Self.startupTabModeKey)
        }
    }
    
    var startupTabURL: String {
        didSet {
            userDefaults.set(startupTabURL, forKey: Self.startupTabURLKey)
        }
    }

    init() {
        // Register default values
        userDefaults.register(defaults: [
            Self.materialKey: NSVisualEffectView.Material.hudWindow.rawValue,
            Self.liquidGlassKey: false,
            Self.searchEngineKey: SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            Self.tabUnloadTimeoutKey: 3600.0,
            Self.blockXSTKey: false,
            Self.debugToggleUpdateNotificationKey: false,
            Self.askBeforeQuitKey: true,
            Self.restoreSessionOnLaunchKey: true,
            Self.startupTabModeKey: StartupTabMode.customURL.rawValue,
            Self.startupTabURLKey: Self.defaultStartupURL,
            Self.sidebarPositionKey: SidebarPosition.left.rawValue,
            Self.topBarAddressViewKey: false,
            Self.experimentalExtensionsKey: false,
            Self.geminiApiKeyKey: "",
            Self.geminiModelKey: GeminiModel.flash.rawValue,
            Self.showAIAssistantKey: true
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.currentMaterialRaw = userDefaults.integer(forKey: Self.materialKey)
        self.isLiquidGlassEnabled = userDefaults.bool(forKey: Self.liquidGlassKey)

        if let rawEngine = userDefaults.string(forKey: Self.searchEngineKey),
           let provider = SearchProvider(rawValue: rawEngine)
        {
            self.searchEngine = provider
        } else {
            // Fallback to google if the stored value is somehow invalid
            self.searchEngine = .google
        }
        
        // Initialize tab unload timeout
        self.tabUnloadTimeout = userDefaults.double(forKey: Self.tabUnloadTimeoutKey)
        self.blockCrossSiteTracking = userDefaults.bool(forKey: Self.blockXSTKey)
        self.debugToggleUpdateNotification = userDefaults.bool(forKey: Self.debugToggleUpdateNotificationKey)
        self.askBeforeQuit = userDefaults.bool(forKey: Self.askBeforeQuitKey)
        self.restoreSessionOnLaunch = userDefaults.object(forKey: Self.restoreSessionOnLaunchKey) as? Bool ?? true
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: Self.sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.topBarAddressView = userDefaults.bool(forKey: Self.topBarAddressViewKey)
        self.experimentalExtensions = userDefaults.bool(forKey: Self.experimentalExtensionsKey)
        self.geminiApiKey = userDefaults.string(forKey: Self.geminiApiKeyKey) ?? ""
        self.geminiModel = GeminiModel(rawValue: userDefaults.string(forKey: Self.geminiModelKey) ?? GeminiModel.flash.rawValue) ?? .flash
        self.showAIAssistant = userDefaults.bool(forKey: Self.showAIAssistantKey)
        if let rawMode = userDefaults.string(forKey: Self.startupTabModeKey),
           let mode = StartupTabMode(rawValue: rawMode) {
            self.startupTabMode = mode
        } else {
            self.startupTabMode = .customURL
        }
        self.startupTabURL = userDefaults.string(forKey: Self.startupTabURLKey) ?? Self.defaultStartupURL
    }
}

// MARK: - Gemini Model

public enum GeminiModel: String, CaseIterable, Identifiable {
    case flash = "gemini-flash-latest"
    case pro = "gemini-2.5-pro"
    
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .flash: return "Gemini Flash (Fast)"
        case .pro: return "Gemini 2.5 Pro (Advanced)"
        }
    }
    
    var description: String {
        switch self {
        case .flash: return "Fast responses, great for quick questions"
        case .pro: return "Most capable model, best for complex analysis"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
    static let blockCrossSiteTrackingChanged = Notification.Name("blockCrossSiteTrackingChanged")
    static let sessionPersistenceChanged = Notification.Name("sessionPersistenceChanged")
}

// MARK: - Startup Tab
