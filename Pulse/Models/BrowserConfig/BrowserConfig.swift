//
//  BrowserConfig.swift
//  Pulse
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import AppKit
import SwiftUI
import WebKit

class BrowserConfiguration {
    static let shared = BrowserConfiguration()
    
    lazy var webViewConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()

        // Use default website data store for normal browsing
        // Extensions use their own separate persistent storage managed by Apple
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Configure JavaScript preferences for extension support
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // Core WebKit preferences for extensions
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Media settings
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Enable Picture-in-Picture for web media
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        
        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true
        
        // User agent for better compatibility
        config.applicationNameForUserAgent = "Version/17.4.1 Safari/605.1.15"

        // Web inspector will be enabled per-webview using isInspectable property

        // Note: webExtensionController will be set by ExtensionManager during initialization

        return config
    }()

    // MARK: - Cache-Optimized Configuration
    lazy var cacheOptimizedWebViewConfiguration: WKWebViewConfiguration = {
        let config = webViewConfiguration
        
        // Enable aggressive caching
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        // Set cache policy preferences
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        
        return config
    }()

    private init() {}
    
}
