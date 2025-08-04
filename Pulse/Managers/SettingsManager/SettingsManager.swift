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

    init() {
        let materialRaw: Int
        if userDefaults.object(forKey: materialKey) != nil {
            materialRaw = userDefaults.integer(forKey: materialKey)
        } else {
            materialRaw = NSVisualEffectView.Material.selection.rawValue
            userDefaults.set(materialRaw, forKey: materialKey)
        }

        let liquidEnabled: Bool
        if userDefaults.object(forKey: liquidGlassKey) != nil {
            liquidEnabled = userDefaults.bool(forKey: liquidGlassKey)
        } else {
            liquidEnabled = false
            userDefaults.set(liquidEnabled, forKey: liquidGlassKey)
        }

        let engine: SearchProvider
        if let raw = userDefaults.string(forKey: searchEngineKey),
            let provider = SearchProvider(rawValue: raw)
        {
            engine = provider
        } else {
            engine = .google
            userDefaults.set(engine.rawValue, forKey: searchEngineKey)
        }

        self.currentMaterialRaw = materialRaw
        self.isLiquidGlassEnabled = liquidEnabled
        self.searchEngine = engine
    }
}
