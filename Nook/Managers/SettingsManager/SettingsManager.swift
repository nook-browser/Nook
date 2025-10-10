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
    private let materialKey = "settings.currentMaterialRaw"
    private let searchEngineKey = "settings.searchEngine"
    private let liquidGlassKey = "settings.isLiquidGlassEnabled"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let blockXSTKey = "settings.blockCrossSiteTracking"
    private let debugToggleUpdateNotificationKey = "settings.debugToggleUpdateNotification"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
    private let restoreSessionOnLaunchKey = "settings.restoreSessionOnLaunch"
    private let startupTabModeKey = "settings.startupTabMode"
    private let startupTabURLKey = "settings.startupTabURL"
    private let sidebarPositionKey = "settings.sidebarPosition"
    private let topBarAddressViewKey = "settings.topBarAddressView"
    private let experimentalExtensionsKey = "settings.experimentalExtensions"
    private let geminiApiKeyKey = "settings.geminiApiKey"
    private let geminiModelKey = "settings.geminiModel"
    private let showAIAssistantKey = "settings.showAIAssistant"
    var currentSettingsTab: SettingsTabs = .general

    // Stored properties
    var isLiquidGlassEnabled: Bool {
        didSet {
            userDefaults.set(isLiquidGlassEnabled, forKey: liquidGlassKey)
        }
    }

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

    var restoreSessionOnLaunch: Bool {
        didSet {
            userDefaults.set(restoreSessionOnLaunch, forKey: restoreSessionOnLaunchKey)
            NotificationCenter.default.post(
                name: .sessionPersistenceChanged,
                object: nil,
                userInfo: ["enabled": restoreSessionOnLaunch]
            )
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
    
    static let defaultStartupURL = "https://www.google.com"
    
    var startupTabMode: StartupTabMode {
        didSet {
            userDefaults.set(startupTabMode.rawValue, forKey: startupTabModeKey)
        }
    }
    
    var startupTabURL: String {
        didSet {
            userDefaults.set(startupTabURL, forKey: startupTabURLKey)
        }
    }

    init() {
        // Register default values
        userDefaults.register(defaults: [
            materialKey: NSVisualEffectView.Material.hudWindow.rawValue,
            liquidGlassKey: false,
            searchEngineKey: SearchProvider.google.rawValue,
            // Default tab unload timeout: 60 minutes
            tabUnloadTimeoutKey: 3600.0,
            blockXSTKey: false,
            debugToggleUpdateNotificationKey: false,
            askBeforeQuitKey: true,
            restoreSessionOnLaunchKey: true,
            startupTabModeKey: StartupTabMode.customURL.rawValue,
            startupTabURLKey: Self.defaultStartupURL,
            sidebarPositionKey: SidebarPosition.left.rawValue,
            topBarAddressViewKey: false,
            experimentalExtensionsKey: false,
            geminiApiKeyKey: "",
            geminiModelKey: GeminiModel.flash.rawValue,
            showAIAssistantKey: true
        ])

        // Initialize properties from UserDefaults
        // This will use the registered defaults if no value is set
        self.currentMaterialRaw = userDefaults.integer(forKey: materialKey)
        self.isLiquidGlassEnabled = userDefaults.bool(forKey: liquidGlassKey)

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
        self.restoreSessionOnLaunch = userDefaults.object(forKey: restoreSessionOnLaunchKey) as? Bool ?? true
        self.sidebarPosition = SidebarPosition(rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left") ?? SidebarPosition.left
        self.topBarAddressView = userDefaults.bool(forKey: topBarAddressViewKey)
        self.experimentalExtensions = userDefaults.bool(forKey: experimentalExtensionsKey)
        self.geminiApiKey = userDefaults.string(forKey: geminiApiKeyKey) ?? ""
        self.geminiModel = GeminiModel(rawValue: userDefaults.string(forKey: geminiModelKey) ?? GeminiModel.flash.rawValue) ?? .flash
        self.showAIAssistant = userDefaults.bool(forKey: showAIAssistantKey)
        if let rawMode = userDefaults.string(forKey: startupTabModeKey),
           let mode = StartupTabMode(rawValue: rawMode) {
            self.startupTabMode = mode
        } else {
            self.startupTabMode = .customURL
        }
        self.startupTabURL = userDefaults.string(forKey: startupTabURLKey) ?? Self.defaultStartupURL
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
