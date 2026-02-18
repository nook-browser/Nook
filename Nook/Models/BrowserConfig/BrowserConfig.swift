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
    
    private init() {}
    
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
        
        // User agent for better compatibility with Client Hints support
        config.applicationNameForUserAgent = "Version/26.0.1 Safari/605.1.15"

        // Web inspector will be enabled per-webview using isInspectable property
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Note: webExtensionController will be set by ExtensionManager during initialization
        // Note: WebAuthn/Passkey support is enabled by default in WKWebView on macOS 13.3+
        // and requires only: entitlements, WKUIDelegate methods, and Info.plist descriptions

        return config
    }()

    // MARK: - Fresh User Content Controller
    // Creates a fresh WKUserContentController but preserves shared user scripts
    // (e.g., extension bridge scripts). This avoids cross-tab handler conflicts
    // while keeping scripts that must be present on every tab.
    func freshUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        for script in webViewConfiguration.userContentController.userScripts {
            controller.addUserScript(script)
        }
        return controller
    }

    // MARK: - Cache-Optimized Configuration
    // Derives from shared config to preserve process pool + extension controller
    func cacheOptimizedWebViewConfiguration() -> WKWebViewConfiguration {
        let config = webViewConfiguration.copy() as! WKWebViewConfiguration
        config.userContentController = freshUserContentController()
        return config
    }

    // MARK: - Profile-Aware Configurations
    // Derive from the shared config so extension controller + process pool are inherited
    func webViewConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let config = webViewConfiguration.copy() as! WKWebViewConfiguration

        // Fresh UCC per tab to avoid cross-tab handler conflicts (preserves shared scripts)
        config.userContentController = freshUserContentController()

        // Use the profile's website data store for isolation
        config.websiteDataStore = profile.dataStore

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
    
    // MARK: - User-Agent Client Hints Configuration
    
    /// Configure User-Agent Client Hints for enhanced browser capability reporting
    /// This ensures websites receive proper information about platform capabilities
    /// including passkey/WebAuthn support
    private func configureClientHints(_ config: WKWebViewConfiguration) {
        // User-Agent Client Hints are automatically supported when using a Safari-compatible User-Agent
        // The applicationNameForUserAgent setting enables this functionality
        // Additional headers like Sec-CH-UA, Sec-CH-UA-Mobile, Sec-CH-UA-Platform are sent automatically
        
        // Enable features that support Client Hints
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        config.preferences.setValue(true, forKey: "getUserMediaRequiresFocus")
    }
    
    // MARK: - Chrome Web Store Integration
    
    /// Get the Web Store injector script
    static func webStoreInjectorScript() -> WKUserScript? {
        guard let scriptPath = Bundle.main.path(forResource: "WebStoreInjector", ofType: "js"),
              let scriptSource = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
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
