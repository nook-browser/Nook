//
//  SettingsManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

@Observable
class SettingsManager {
    private let userDefaults = UserDefaults.standard
    private let materialKey = "settings.currentMaterialRaw"
    private let searchEngineKey = "settings.searchEngine"
    private let liquidGlassKey = "settings.isLiquidGlassEnabled"
    private let tabUnloadTimeoutKey = "settings.tabUnloadTimeout"
    private let blockXSTKey = "settings.blockCrossSiteTracking"
    private let debugToggleUpdateNotificationKey = "settings.debugToggleUpdateNotification"
    private let askBeforeQuitKey = "settings.askBeforeQuit"
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

    var debugToggleUpdateNotification: Bool {
        didSet {
            userDefaults.set(debugToggleUpdateNotification, forKey: debugToggleUpdateNotificationKey)
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
            askBeforeQuitKey: true
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
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
    static let blockCrossSiteTrackingChanged = Notification.Name("blockCrossSiteTrackingChanged")
}
