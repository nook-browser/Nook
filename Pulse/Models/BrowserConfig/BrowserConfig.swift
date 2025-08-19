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

        // Use default website data store for persistent cookies
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Configure JavaScript preferences
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // Important: Enable these for better Google compatibility
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Media settings
        config.mediaTypesRequiringUserActionForPlayback = []

        // Add application name
        config.applicationNameForUserAgent = "Version/17.4.1 Safari/605.1.15"

        // Allow extension resources to load in main web views
        let multiHandler = MultiExtensionSchemeHandler()
        config.setURLSchemeHandler(multiHandler, forURLScheme: "chrome-extension")
        config.setURLSchemeHandler(multiHandler, forURLScheme: "moz-extension")

        return config
    }()

    private init() {}
}
