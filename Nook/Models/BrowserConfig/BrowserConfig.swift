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

    // MARK: - Tweaks Integration

    /// Create a configuration with tweak support integrated
    func webViewConfigurationWithTweaks(for profile: Profile) -> WKWebViewConfiguration {
        let config = webViewConfiguration(for: profile)

        // Add tweak injection support
        addTweakSupport(to: config)

        return config
    }

    /// Add tweak support to an existing configuration
    private func addTweakSupport(to config: WKWebViewConfiguration) {
        // Add message handler for tweak communication
        // Note: scriptMessageHandlerNames API not available in this WebKit version
        // The handler will be added each time this method is called
        config.userContentController.add(TweakMessageHandler(), name: "nookTweaks")

        // Add base tweak injection script
        let baseScript = createBaseTweakScript()
        let baseUserScript = WKUserScript(
            source: baseScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(baseUserScript)
    }

    /// Create the base script that provides tweak functionality
    private func createBaseTweakScript() -> String {
        let securityPolicy = TweakSecurityValidator.shared.generateSecurityPolicy()

        return """
        // Nook Tweaks Base Script
        (function() {
            if (typeof window.nookTweakBase === 'undefined') {
                window.nookTweakBase = {
                    version: '1.0.0',
                    debug: false,

                    // Log debug messages
                    log: function(message, data) {
                        if (this.debug) {
                            console.log('[Nook Tweaks]', message, data || '');
                        }
                    },

                    // Safely execute JavaScript with error handling
                    safeExecute: function(code, context) {
                        try {
                            if (typeof code === 'function') {
                                return code.call(context || window);
                            } else if (typeof code === 'string') {
                                return eval(code);
                            }
                        } catch (error) {
                            this.log('JavaScript execution error:', error);
                            return null;
                        }
                    },

                    // Safely manipulate DOM elements
                    safeManipulate: function(selector, operation, value) {
                        try {
                            const elements = document.querySelectorAll(selector);
                            elements.forEach(element => {
                                switch (operation) {
                                    case 'hide':
                                        element.style.display = 'none';
                                        break;
                                    case 'show':
                                        element.style.display = '';
                                        break;
                                    case 'addClass':
                                        element.classList.add(value);
                                        break;
                                    case 'removeClass':
                                        element.classList.remove(value);
                                        break;
                                    case 'setAttribute':
                                        element.setAttribute(value.name, value.value);
                                        break;
                                    case 'removeAttribute':
                                        element.removeAttribute(value);
                                        break;
                                }
                            });
                            return elements.length;
                        } catch (error) {
                            this.log('DOM manipulation error:', error);
                            return 0;
                        }
                    },

                    // Create a sandboxed execution context
                    createSandbox: function() {
                        const sandbox = {
                            console: {
                                log: (...args) => this.log('[User Script]', args),
                                error: (...args) => this.log('[User Script Error]', args),
                                warn: (...args) => this.log('[User Script Warning]', args)
                            },

                            // Safe DOM manipulation
                            hide: (selector) => this.safeManipulate(selector, 'hide'),
                            show: (selector) => this.safeManipulate(selector, 'show'),

                            // Limited CSS manipulation
                            addCSS: (css) => {
                                try {
                                    const style = document.createElement('style');
                                    style.textContent = css;
                                    style.setAttribute('data-nook-tweak', 'user-css');
                                    document.head.appendChild(style);
                                    return true;
                                } catch (error) {
                                    this.log('CSS injection error:', error);
                                    return false;
                                }
                            },

                            // Safe event handling
                            addEventListener: (selector, event, handler) => {
                                try {
                                    const elements = document.querySelectorAll(selector);
                                    elements.forEach(element => {
                                        element.addEventListener(event, (e) => {
                                            try {
                                                handler.call(sandbox, e);
                                            } catch (error) {
                                                this.log('Event handler error:', error);
                                            }
                                        });
                                    });
                                    return elements.length;
                                } catch (error) {
                                    this.log('Event listener error:', error);
                                    return 0;
                                }
                            }
                        };

                        return sandbox;
                    },

                    // Clean up all tweak modifications
                    cleanup: function() {
                        // Remove tweak styles
                        const tweakStyles = document.querySelectorAll('style[data-nook-tweak]');
                        tweakStyles.forEach(style => style.remove());

                        // Remove tweak attributes
                        const tweakElements = document.querySelectorAll('[data-nook-tweak-modified]');
                        tweakElements.forEach(element => {
                            element.removeAttribute('data-nook-tweak-modified');
                        });

                        this.log('Cleanup completed');
                    }
                };

                // Load security policy first
                \(securityPolicy)

                // Make available globally for user scripts
                window.nookTweaksSandbox = window.nookTweakBase.createSandbox();

                // Log initialization
                window.nookTweakBase.log('Nook Tweaks base script initialized with security policy');
            }
        })();
        """
    }
}

// MARK: - Tweak Message Handler
class TweakMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        let action = body["action"] as? String ?? ""
        let data = body["data"]

        switch action {
        case "log":
            if let message = data as? String {
                print("🎨 [Tweak WebView] \(message)")
            }

        case "error":
            if let error = data as? String {
                print("🎨 [Tweak WebView Error] \(error)")
            }

        case "debug":
            // Enable/disable debug mode
            if let enabled = data as? Bool {
                UserDefaults.standard.set(enabled, forKey: "nook.tweaks.debug")
            }

        default:
            print("🎨 [Tweak WebView] Unknown action: \(action)")
        }
    }
}
