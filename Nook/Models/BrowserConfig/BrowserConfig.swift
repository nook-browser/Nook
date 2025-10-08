//
//  BrowserConfig.swift
//  Nook
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
        
        // Enable full-screen API support
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        // CRITICAL: Enable HTML5 Fullscreen API
        config.preferences.isElementFullscreenEnabled = true
        
        
        // Enable full-screen API support
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        // CRITICAL: Enable HTML5 Fullscreen API
        config.preferences.isElementFullscreenEnabled = true
        
        
        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true
        
        // User agent for better compatibility
        config.applicationNameForUserAgent = "Version/26.0.1 Safari/605.1.15"

        // Web inspector will be enabled per-webview using isInspectable property
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Note: webExtensionController will be set by ExtensionManager during initialization

        return config
    }()

    // MARK: - Cache-Optimized Configuration
    // Returns a fresh configuration each call to avoid cross-tab state sharing
    func cacheOptimizedWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // Default data store for non-profile-specific usage
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
        
        // Enable full-screen API support
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        // CRITICAL: Enable HTML5 Fullscreen API
        config.preferences.isElementFullscreenEnabled = true
        
        

        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true

        // User agent for better compatibility (mirror default config)
        config.applicationNameForUserAgent = "Version/26.0.1 Safari/605.1.15"

        // Cache/perf optimizations mirroring profile-scoped variant
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")


        return config
    }

    // MARK: - Profile-Aware Configurations
    // Create a fresh configuration using a profile-specific data store
    func webViewConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // Use the profile's website data store for isolation
        config.websiteDataStore = profile.dataStore

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
        
        // Enable full-screen API support
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        
        // CRITICAL: Enable HTML5 Fullscreen API
        config.preferences.isElementFullscreenEnabled = true
        
        

        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true

        // User agent for better compatibility (mirror default config)
        config.applicationNameForUserAgent = "Version/26.0.1 Safari/605.1.15"
        
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        return config
    }

    // Returns a profile-scoped configuration with cache/perf optimizations applied
    func cacheOptimizedWebViewConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let config = webViewConfiguration(for: profile)
        // Enable aggressive caching and media capabilities (mirror default optimized config)
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        return config
    }

    private init() {}
    
    // MARK: - Chrome Web Store Integration
    
    /// Get the Web Store injector script
    static func webStoreInjectorScript() -> WKUserScript? {
        guard let scriptPath = Bundle.main.path(forResource: "WebStoreInjector", ofType: "js"),
              let scriptSource = try? String(contentsOfFile: scriptPath) else {
            return nil
        }
        
        return WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
    
    /// Check if URL is a Chrome Web Store page
    static func isChromeWebStore(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        
        // Check for Chrome Web Store
        if host.contains("chrome.google.com") && path.contains("webstore") {
            return true
        }
        
        // Check for new Chrome Web Store
        if host.contains("chromewebstore.google.com") {
            return true
        }
        
        // Check for Microsoft Edge Add-ons
        if host.contains("microsoftedge.microsoft.com") && path.contains("addons") {
            return true
        }
        
        return false
    }
}
