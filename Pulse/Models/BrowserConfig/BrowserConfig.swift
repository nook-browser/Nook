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
    
    @available(macOS 15.4, *)
    private lazy var extensionURLSchemeHandler = WebKitExtensionURLSchemeHandler()

    lazy var webViewConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()

        // Use default website data store for persistent cookies and extension data
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

        // User agent for better compatibility
        config.applicationNameForUserAgent = "Version/17.4.1 Safari/605.1.15"

        // Register custom URL scheme handler for webkit-extension URLs
        if #available(macOS 15.4, *) {
            config.setURLSchemeHandler(extensionURLSchemeHandler, forURLScheme: "webkit-extension")
            print("BrowserConfiguration: Registered webkit-extension URL scheme handler")
        }

        // Note: webExtensionController will be set by ExtensionManager during initialization

        return config
    }()

    private init() {}
}
