//
//  BrowserConfig.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import AppKit
import SwiftUI
import WebKit
import NookBlocker

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
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Enable JavaScript clipboard access (navigator.clipboard API, document.execCommand('copy'))
        // Required for third-party WKWebView apps — Safari enables this by default.
        config.preferences.setValue(true, forKey: "javaScriptCanAccessClipboard")
        config.preferences.setValue(true, forKey: "DOMPasteAllowed")

        // Media settings — use macOS default (no restrictions, matching Safari behavior).
        // [.audio] blocks programmatic play() for media with audio tracks, which breaks
        // YouTube autoplay since SPA navigations call play() outside user-gesture context.
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Enable Picture-in-Picture for web media
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")

        // Enable full-screen API support
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        // NOTE: "mediaDevicesEnabled" intentionally NOT set — it causes the WebContent
        // process to eagerly register with com.apple.audio.AudioComponentRegistrar,
        // which is sandbox-denied for third-party WKWebView apps and crashes the process.
        // getUserMedia still works through WKUIDelegate permission prompts without this.

        // CRITICAL: Enable HTML5 Fullscreen API
        config.preferences.isElementFullscreenEnabled = true

        // Enable background media playback
        config.allowsAirPlayForMediaPlayback = true
        
        // User agent for better compatibility with Client Hints support
        config.applicationNameForUserAgent = "Version/26.0.1 Safari/605.1.15"

        // Web inspector will be enabled per-webview using isInspectable property
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        // Note: webExtensionController will be set by ExtensionManager during initialization

        // MARK: Passkey suppression
        // Pending Apple approval of com.apple.developer.web-browser.public-key-credential,
        // tell websites we don't support platform authenticators so they won't prompt for passkeys.
        // TODO: Remove this once the entitlement is granted.
        let passkeySuppress = WKUserScript(
            source: """
            // Nook Passkey Suppression
            (function() {
                if (window.PublicKeyCredential) {
                    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function() {
                        return Promise.resolve(false);
                    };
                    if (PublicKeyCredential.isConditionalMediationAvailable) {
                        PublicKeyCredential.isConditionalMediationAvailable = function() {
                            return Promise.resolve(false);
                        };
                    }
                }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(passkeySuppress)

        return config
    }()

    /// Optional hook for ContentBlockerManager to apply rule lists to new controllers.
    var contentRuleListApplicator: ((WKUserContentController) -> Void)?

    // MARK: - Fresh User Content Controller
    // Creates a fresh WKUserContentController but preserves Nook's own shared
    // user scripts. This avoids cross-tab handler conflicts while keeping
    // scripts that must be present on every tab.
    //
    // Only Nook-owned scripts are copied. WKWebExtensionController injects its
    // content scripts into every new controller itself, so copying them here as
    // well would hand each new tab two of each. See WKUserScript+NookOwned.
    func freshUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        for script in webViewConfiguration.userContentController.userScripts.nookOwned {
            controller.addUserScript(script)
        }
        // Apply content blocker rule lists if available
        contentRuleListApplicator?(controller)
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
    @MainActor
    func webViewConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let config = webViewConfiguration.copy() as! WKWebViewConfiguration

        // Fresh UCC per tab to avoid cross-tab handler conflicts (preserves shared scripts)
        config.userContentController = freshUserContentController()

        // Use the profile's website data store for isolation
        config.websiteDataStore = profile.dataStore

        // Extensions never run in private (ephemeral) profiles, matching Chrome's default.
        if profile.isEphemeral {
            config.webExtensionController = nil
        }

        return config
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
}
