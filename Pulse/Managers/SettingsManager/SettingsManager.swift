//
//  SettingsManager.swift
//  Pulse
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

    init() {
        // Register default values
        userDefaults.register(defaults: [
            materialKey: NSVisualEffectView.Material.hudWindow.rawValue,
            liquidGlassKey: false,
            searchEngineKey: SearchProvider.google.rawValue,
            tabUnloadTimeoutKey: 300.0 // 5 minutes default
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
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let tabUnloadTimeoutChanged = Notification.Name("tabUnloadTimeoutChanged")
}
