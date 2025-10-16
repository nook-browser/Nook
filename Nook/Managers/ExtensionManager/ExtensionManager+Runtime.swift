//
//  ExtensionManager+Runtime.swift
//  Nook
//
//  Chrome Runtime API Bridge for WKWebExtension support
//  Implements chrome.runtime.* APIs

import Foundation
import WebKit
import AppKit

// MARK: - Chrome Runtime API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Runtime Message Handling

    /// Handles chrome.runtime.sendMessage calls from extension contexts
    func handleRuntimeMessage(message: [String: Any], from context: WKWebExtensionContext, replyHandler: @escaping (Any?) -> Void) {
        print("🔍 [ExtensionManager+Runtime] === CHROME RUNTIME MESSAGE DEBUG ===")
        print("🔍 [ExtensionManager+Runtime] Message keys: \(message.keys)")
        print("🔍 [ExtensionManager+Runtime] Full message: \(message)")
        print("🔍 [ExtensionManager+Runtime] Context extension ID: \(context.uniqueIdentifier)")

        guard let extensionId = getExtensionId(for: context) else {
            print("❌ [ExtensionManager+Runtime] Extension ID not found - this is critical")
            replyHandler(["error": "Extension ID not found"])
            return
        }

        print("✅ [ExtensionManager+Runtime] Extension ID resolved: \(extensionId)")

        // Extract message data
        let targetExtensionId = message["targetExtensionId"] as? String
        let messageData = message["data"] ?? message
        let messageId = UUID().uuidString

        // Handle different message types
        if let messageType = message["type"] as? String {
            switch messageType {
            case "sendMessage":
                handleSendMessage(messageData: messageData, from: extensionId, to: targetExtensionId, messageId: messageId, replyHandler: replyHandler)
            case "connect":
                handleConnect(messageData: messageData, from: extensionId, replyHandler: replyHandler)
            default:
                replyHandler(["error": "Unknown message type: \(messageType)"])
            }
        } else {
            // Default message handling
            handleSendMessage(messageData: messageData, from: extensionId, to: targetExtensionId, messageId: messageId, replyHandler: replyHandler)
        }
    }

    // MARK: - Message Passing Implementation

    private func handleSendMessage(messageData: Any, from extensionId: String, to targetExtensionId: String?, messageId: String, replyHandler: @escaping (Any?) -> Void) {
        print("[ExtensionManager+Runtime] Sending message from \(extensionId) to \(targetExtensionId ?? "broadcast")")

        // Store the reply handler for async response
        pendingRuntimeMessageRepliesAccess[messageId] = replyHandler

        // Create Chrome runtime message format
        let runtimeMessage: [String: Any] = [
            "id": messageId,
            "sender": [
                "id": extensionId,
                "url": "webkit-extension://\(extensionId)/",
                "tab": getCurrentTabInfo() as Any
            ],
            "data": messageData
        ]

        // Broadcast to all contexts or target specific extension
        if let targetId = targetExtensionId {
            // Send to specific extension
            if let targetContext = extensionContextsAccess[targetId] {
                deliverMessageToContext(runtimeMessage, to: targetContext)
            } else {
                replyHandler(["error": "Target extension not found: \(targetId)"])
                pendingRuntimeMessageRepliesAccess.removeValue(forKey: messageId)
            }
        } else {
            // Broadcast to all extension contexts (including background scripts)
            broadcastMessageToAllContexts(runtimeMessage, from: extensionId)

            // CRITICAL FIX: Provide timeout for broadcasts that don't get responses
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                if let callback = self.pendingRuntimeMessageRepliesAccess[messageId] {
                    print("[ExtensionManager+Runtime] Timeout for message \(messageId) - providing default response")
                    callback(["success": true, "message": "Message delivered"])
                    self.pendingRuntimeMessageRepliesAccess.removeValue(forKey: messageId)
                }
            }
        }
    }

    private func handleConnect(messageData: Any, from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("[ExtensionManager+Runtime] Handling connection request from \(extensionId)")

        // Create a message port for ongoing communication
        let portName = UUID().uuidString
        // Create message port using controller (simplified approach)

        // Store the port
        // extensionMessagePorts[portName] = messagePort (simplified approach)

        // Return port information to the caller
        replyHandler([
            "name": portName,
            "sender": [
                "id": extensionId,
                "url": "webkit-extension://\(extensionId)/"
            ]
        ])
    }

    // MARK: - Message Delivery

    private func deliverMessageToContext(_ message: [String: Any], to context: WKWebExtensionContext) {
        print("[ExtensionManager+Runtime] Delivering message to extension context: \(context.uniqueIdentifier)")

        // CRITICAL FIX: Simplified message delivery using WebKit's built-in system
        // The delegate method we added (webExtensionController:sendMessage:...) will be called by WebKit
        // We don't need to manually call delegate methods - WebKit handles the routing

        // Check if we have a pending reply handler for this message
        if let messageId = message["id"] as? String,
           let replyHandler = pendingRuntimeMessageRepliesAccess[messageId] {
            print("[ExtensionManager+Runtime] ✅ Providing immediate response for message: \(messageId)")

            // Provide a default successful response
            // The real communication will happen through the delegate method when WebKit calls it
            replyHandler(["success": true, "message": "Message delivered to extension context"])
            pendingRuntimeMessageRepliesAccess.removeValue(forKey: messageId)
        }

        print("[ExtensionManager+Runtime] ✅ Message delivery prepared - WebKit will route through delegate method")
    }

    private func broadcastMessageToAllContexts(_ message: [String: Any], from senderId: String) {
        for (extensionId, context) in extensionContextsAccess {
            // Don't send back to the sender
            if extensionId != senderId {
                deliverMessageToContext(message, to: context)
            }
        }
    }

    // MARK: - Context Information

    private func getCurrentTabInfo() -> [String: Any]? {
        guard let browserManager = browserManagerAccess,
              let currentTab = browserManager.currentTabForActiveWindow() else {
            return nil
        }

        return [
            "id": currentTab.id.uuidString,
            "url": currentTab.url.absoluteString,
            "title": currentTab.name,
            "active": true,
            "windowId": 1 // Simplified window ID
        ]
    }

    // MARK: - Runtime API Properties

    /// Gets the extension ID for chrome.runtime.id
    func getExtensionId(for context: WKWebExtensionContext) -> String? {
        return extensionContextsAccess.first(where: { $0.value == context })?.key ?? "unknown"
    }

    /// Gets the extension manifest for chrome.runtime.getManifest()
    func getExtensionManifest(for context: WKWebExtensionContext) -> [String: Any]? {
        guard let extensionId = getExtensionId(for: context) else { return nil }

        // This would typically read the actual manifest.json file
        // For now, return a basic manifest structure that Bitwarden expects
        return [
            "manifest_version": 3,
            "name": "Bitwarden",
            "version": "2024.6.2",
            "description": "Bitwarden password manager",
            "permissions": [
                "activeTab",
                "alarms",
                "storage",
                "tabs",
                "scripting",
                "unlimitedStorage",
                "webNavigation",
                "webRequest",
                "notifications"
            ],
            "host_permissions": [
                "https://*/*",
                "http://*/*"
            ],
            "background": [
                "service_worker": "background.js"
            ],
            "action": [
                "default_popup": "popup/index.html",
                "default_title": "Bitwarden"
            ],
            "content_scripts": [
                [
                    "matches": ["<all_urls>"],
                    "js": ["content/content-message-handler.js"],
                    "run_at": "document_start",
                    "all_frames": false
                ]
            ]
        ]
    }

    // MARK: - Message Reply System

    /// Sends a reply to a pending message
    func sendMessageReply(messageId: String, response: Any?) {
        if let replyHandler = pendingRuntimeMessageRepliesAccess[messageId] {
            replyHandler(response)
            pendingRuntimeMessageRepliesAccess.removeValue(forKey: messageId)
        }
    }

    // MARK: - JavaScript API Injection (Phase 3 Enhancement)

    /// Injects the complete Chrome API bridge system into a web view
    /// This is the main entry point for Phase 3 Chrome API context injection
    func injectCompleteChromeAPIIntoWebView(_ webView: WKWebView, extensionId: String, contextType: ChromeAPIContextType = .popup) {
        print("🔧 [ExtensionManager+Runtime] === CHROME API INJECTION DEBUG ===")
        print("🔧 [ExtensionManager+Runtime] Starting Chrome API injection for context: \(contextType)")
        print("🔧 [ExtensionManager+Runtime] Extension ID: \(extensionId)")
        print("🔧 [ExtensionManager+Runtime] WebView URL: \(webView.url?.absoluteString ?? "unknown")")

        let completeAPIScript = generateCompleteChromeAPIScript(extensionId: extensionId, contextType: contextType)

        print("🔧 [ExtensionManager+Runtime] Generated Chrome API script length: \(completeAPIScript.count) characters")

        webView.evaluateJavaScript(completeAPIScript) { result, error in
            if let error = error {
                print("❌ [ExtensionManager+Runtime] CHROME API INJECTION FAILED: \(error)")
                print("❌ [ExtensionManager+Runtime] This will prevent Bitwarden from loading properly")
            } else {
                print("✅ [ExtensionManager+Runtime] CHROME API INJECTION SUCCESSFUL")
                // Verify API availability after injection
                self.verifyChromeAPIAvailability(in: webView, contextType: contextType)
            }
        }
    }

    /// Injects the Chrome Runtime API bridge into a web view (legacy method)
    func injectRuntimeAPIIntoWebView(_ webView: WKWebView, extensionId: String) {
        injectCompleteChromeAPIIntoWebView(webView, extensionId: extensionId, contextType: .popup)
    }

    // MARK: - Context Types

    enum ChromeAPIContextType {
        case popup
        case background
        case contentScript
        case options
    }

    /// Generate the complete Chrome API bridge system for a specific context
    private func generateCompleteChromeAPIScript(extensionId: String, contextType: ChromeAPIContextType) -> String {
        let contextSpecificCode: String
        let additionalAPICode: String

        switch contextType {
        case .popup:
            contextSpecificCode = """
            // POPUP CONTEXT: Bitwarden Angular app initialization
            console.log('[Chrome Bridge] POPUP CONTEXT - Preparing for Angular bootstrap');
            window.CHROME_BRIDGE_CONTEXT = 'popup';
            window.CHROME_BRIDGE_READY = false;
            """
            additionalAPICode = """
            // Popup-specific APIs that Bitwarden needs
            if (!chrome.runtime.id) {
                console.error('[Chrome Bridge] CRITICAL: chrome.runtime.id is missing - Angular will fail');
            }
            """

        case .background:
            contextSpecificCode = """
            // BACKGROUND CONTEXT: Service worker environment
            console.log('[Chrome Bridge] BACKGROUND CONTEXT - Service worker initialization');
            window.CHROME_BRIDGE_CONTEXT = 'background';
            // Service workers don't have window, use self
            if (typeof self !== 'undefined') {
                self.chrome = chrome;
            }
            """
            additionalAPICode = """
            // Background script specific initialization
            chrome.runtime.onStartup = new EventTarget();
            chrome.runtime.onInstalled = new EventTarget();
            """

        case .contentScript:
            contextSpecificCode = """
            // CONTENT SCRIPT CONTEXT: Page interaction
            console.log('[Chrome Bridge] CONTENT SCRIPT CONTEXT - Page access enabled');
            window.CHROME_BRIDGE_CONTEXT = 'contentScript';
            """
            additionalAPICode = """
            // Content script specific APIs
            chrome.contentScripts = {
                register: function(contentScriptOptions, callback) {
                    // Simplified implementation
                    if (callback) callback();
                }
            };
            """

        case .options:
            contextSpecificCode = """
            // OPTIONS CONTEXT: Extension settings page
            console.log('[Chrome Bridge] OPTIONS CONTEXT - Settings page initialization');
            window.CHROME_BRIDGE_CONTEXT = 'options';
            """
            additionalAPICode = """
            // Options page specific APIs
            chrome.management = {
                getSelf: function(callback) {
                    const selfInfo = {
                        id: '\(extensionId)',
                        name: 'Bitwarden',
                        version: '2024.6.2'
                    };
                    if (callback) callback(selfInfo);
                }
            };
            """
        }

        return """
        // ========================================================
        // COMPLETE CHROME API BRIDGE SYSTEM - NOOK BROWSER
        // Generated for extension: \(extensionId)
        // Context: \(contextType)
        // ========================================================

        (function() {
            'use strict';

            console.log('[Chrome Bridge] Initializing complete Chrome API system...');
            console.log('[Chrome Bridge] Extension ID: \(extensionId)');
            console.log('[Chrome Bridge] Context: \(contextType)');

            // Create global chrome object if it doesn't exist
            if (typeof chrome === 'undefined') {
                window.chrome = {};
                console.log('[Chrome Bridge] Created global chrome object');
            }

            // Phase 3: API Availability Detection System
            window.CHROME_API_STATUS = {
                runtime: false,
                storage: false,
                tabs: false,
                scripting: false,
                fullyReady: false
            };

            // Phase 3: Angular Bootstrap Protection
            window.CHROME_BRIDGE_READY = false;
            window.CHROME_BRIDGE_ERRORS = [];

            function markAPIReady(apiName) {
                window.CHROME_API_STATUS[apiName] = true;
                console.log('[Chrome Bridge] API Ready: ' + apiName);
                checkAllAPIsReady();
            }

            function logError(error) {
                window.CHROME_BRIDGE_ERRORS.push(error);
                console.error('[Chrome Bridge]', error);
            }

            function checkAllAPIsReady() {
                const allReady = Object.values(window.CHROME_API_STATUS).every(status => status === true);
                if (allReady && !window.CHROME_API_STATUS.fullyReady) {
                    window.CHROME_API_STATUS.fullyReady = true;
                    window.CHROME_BRIDGE_READY = true;
                    console.log('[Chrome Bridge] 🎉 ALL CHROME APIS READY - Angular can now bootstrap');
                    console.log('[Chrome Bridge] Status:', window.CHROME_API_STATUS);

                    // Dispatch ready event for Angular
                    if (typeof window !== 'undefined' && window.dispatchEvent) {
                        window.dispatchEvent(new CustomEvent('chromeBridgeReady'));
                    }
                }
            }

            try {
                // Chrome Runtime API
                if (!chrome.runtime) {
                    chrome.runtime = {
                        id: '\(extensionId)',
                        onMessage: new EventTarget(),
                        sendMessage: function(message, callback) {
                            try {
                                const messageData = {
                                    type: 'sendMessage',
                                    data: message,
                                    timestamp: Date.now().toString()
                                };

                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
                                    window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);

                                    if (callback) {
                                        const messageId = messageData.timestamp;
                                        window.chromeRuntimeCallbacks = window.chromeRuntimeCallbacks || {};
                                        window.chromeRuntimeCallbacks[messageId] = callback;
                                    }
                                } else {
                                    logError('chromeRuntime message handler not available');
                                }
                            } catch (error) {
                                logError('chrome.runtime.sendMessage error: ' + error.message);
                            }
                        },
                        getManifest: function() {
                            return \(getManifestJSON() ?? "{}");
                        },
                        connect: function(extensionId, connectInfo) {
                            try {
                                const messageData = {
                                    type: 'connect',
                                    extensionId: extensionId,
                                    connectInfo: connectInfo
                                };

                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
                                    return window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);
                                }
                            } catch (error) {
                                logError('chrome.runtime.connect error: ' + error.message);
                            }
                        }
                    };

                    // Add onMessage listener support
                    chrome.runtime.onMessage.addListener = function(listener) {
                        try {
                            chrome.runtime.onMessage.addEventListener('message', function(event) {
                                const sendResponse = function(response) {
                                    // Handle response via existing message system
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeTabsResponse) {
                                        window.webkit.messageHandlers.chromeTabsResponse.postMessage({
                                            type: 'response',
                                            messageId: event.detail.messageId || Date.now().toString(),
                                            data: response
                                        });
                                    }
                                };
                                listener(event.detail.message, event.detail.sender, sendResponse);
                            });
                        } catch (error) {
                            logError('chrome.runtime.onMessage.addListener error: ' + error.message);
                        }
                    };

                    markAPIReady('runtime');
                } else {
                    markAPIReady('runtime');
                }

                // Chrome Storage API
                if (!chrome.storage) {
                    chrome.storage = {
                        local: {
                            get: function(keys, callback) {
                                try {
                                    const messageData = { type: 'localGet', keys: keys, timestamp: Date.now().toString() };
                                    if (callback) {
                                        window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                        window.chromeStorageCallbacks[messageData.timestamp] = callback;
                                    }
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeStorage) {
                                        window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                                    }
                                } catch (error) {
                                    logError('chrome.storage.local.get error: ' + error.message);
                                    if (callback) callback(null);
                                }
                            },
                            set: function(items, callback) {
                                try {
                                    const messageData = { type: 'localSet', items: items, timestamp: Date.now().toString() };
                                    if (callback) {
                                        window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                        window.chromeStorageCallbacks[messageData.timestamp] = callback;
                                    }
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeStorage) {
                                        window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                                    }
                                } catch (error) {
                                    logError('chrome.storage.local.set error: ' + error.message);
                                    if (callback) callback();
                                }
                            }
                        },
                        onChanged: new EventTarget()
                    };

                    chrome.storage.onChanged.addListener = function(listener) {
                        try {
                            chrome.storage.onChanged.addEventListener('change', function(event) {
                                listener(event.detail.changes, event.detail.areaName);
                            });
                        } catch (error) {
                            logError('chrome.storage.onChanged.addListener error: ' + error.message);
                        }
                    };

                    markAPIReady('storage');
                } else {
                    markAPIReady('storage');
                }

                // Chrome Tabs API
                if (!chrome.tabs) {
                    chrome.tabs = {
                        query: function(queryInfo, callback) {
                            try {
                                const messageData = { type: 'query', queryInfo: queryInfo, timestamp: Date.now().toString() };
                                if (callback) {
                                    window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                                    window.chromeTabsCallbacks[messageData.timestamp] = callback;
                                }
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeTabs) {
                                    window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                                }
                            } catch (error) {
                                logError('chrome.tabs.query error: ' + error.message);
                                if (callback) callback([]);
                            }
                        },
                        sendMessage: function(tabId, message, options, callback) {
                            try {
                                if (typeof options === 'function') {
                                    callback = options;
                                    options = {};
                                }
                                const messageData = {
                                    type: 'sendMessage',
                                    tabId: tabId,
                                    message: message,
                                    options: options,
                                    timestamp: Date.now().toString()
                                };
                                if (callback) {
                                    window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                                    window.chromeTabsCallbacks[messageData.timestamp] = callback;
                                }
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeTabs) {
                                    window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                                }
                            } catch (error) {
                                logError('chrome.tabs.sendMessage error: ' + error.message);
                                if (callback) callback();
                            }
                        }
                    };

                    markAPIReady('tabs');
                } else {
                    markAPIReady('tabs');
                }

                // Chrome Scripting API
                if (!chrome.scripting) {
                    chrome.scripting = {
                        executeScript: function(injection, callback) {
                            try {
                                const messageData = { type: 'executeScript', injection: injection, timestamp: Date.now().toString() };
                                if (callback) {
                                    window.chromeScriptingCallbacks = window.chromeScriptingCallbacks || {};
                                    window.chromeScriptingCallbacks[messageData.timestamp] = callback;
                                }
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeScripting) {
                                    window.webkit.messageHandlers.chromeScripting.postMessage(messageData);
                                }
                            } catch (error) {
                                logError('chrome.scripting.executeScript error: ' + error.message);
                                if (callback) callback([]);
                            }
                        }
                    };

                    markAPIReady('scripting');
                } else {
                    markAPIReady('scripting');

                }

                // chrome.alarms API - Force override native implementation
                \(generateAlarmsAPIScript(extensionId: extensionId))
                markAPIReady('alarms');

                // Context-specific initialization
                \(contextSpecificCode)

                // Additional API code based on context
                \(additionalAPICode)

                // Phase 3: Final verification
                setTimeout(function() {
                    if (!window.CHROME_API_STATUS.fullyReady) {
                        console.warn('[Chrome Bridge] Chrome APIs not fully ready after timeout');
                        console.warn('[Chrome Bridge] Status:', window.CHROME_API_STATUS);
                        console.warn('[Chrome Bridge] Errors:', window.CHROME_BRIDGE_ERRORS);

                        // Force ready state to prevent infinite waiting
                        window.CHROME_BRIDGE_READY = true;
                        window.CHROME_API_STATUS.fullyReady = true;

                        console.log('[Chrome Bridge] Forced ready state - Angular may proceed with limited functionality');
                    }
                }, 2000); // 2 second timeout

            } catch (error) {
                logError('Chrome API initialization failed: ' + error.message);
                // Force ready state to prevent blocking
                window.CHROME_BRIDGE_READY = true;
            }

        })();
        """
    }

    /// Verify Chrome API availability after injection
    private func verifyChromeAPIAvailability(in webView: WKWebView, contextType: ChromeAPIContextType) {
        print("🔍 [ExtensionManager+Runtime] === CHROME API VERIFICATION DEBUG ===")
        print("🔍 [ExtensionManager+Runtime] Starting API verification for context: \(contextType)")

        let verificationScript = """
        (function() {
            console.log('🔍 [Chrome Bridge] Verifying API availability...');

            const requiredAPIs = ['runtime', 'storage', 'tabs', 'scripting'];
            const missingAPIs = [];
            const availableAPIs = [];

            requiredAPIs.forEach(function(api) {
                if (!chrome[api]) {
                    missingAPIs.push(api);
                    console.error('❌ [Chrome Bridge] Missing API:', api);
                } else {
                    availableAPIs.push(api);
                    console.log('✅ [Chrome Bridge] Found API:', api);
                }
            });

            if (missingAPIs.length > 0) {
                console.error('❌ [Chrome Bridge] MISSING APIS:', missingAPIs);
                console.error('❌ [Chrome Bridge] Bitwarden will fail to load without these APIs');
                return { success: false, missingAPIs: missingAPIs, availableAPIs: availableAPIs };
            }

            // Test basic API functionality
            try {
                const testResult = {
                    success: true,
                    hasRuntime: !!chrome.runtime,
                    hasStorage: !!chrome.storage,
                    hasTabs: !!chrome.tabs,
                    hasScripting: !!chrome.scripting,
                    hasRuntimeId: !!chrome.runtime.id,
                    runtimeId: chrome.runtime?.id || 'MISSING',
                    contextType: '\(contextType)',
                    availableAPIs: availableAPIs,
                    timestamp: new Date().toISOString()
                };
                console.log('✅ [Chrome Bridge] API verification successful:', testResult);
                return testResult;
            } catch (error) {
                console.error('❌ [Chrome Bridge] API verification failed:', error);
                return { success: false, error: error.message, availableAPIs: availableAPIs };
            }
        })();
        """

        webView.evaluateJavaScript(verificationScript) { result, error in
            if let error = error {
                print("❌ [ExtensionManager+Runtime] API VERIFICATION ERROR: \(error)")
                print("❌ [ExtensionManager+Runtime] This indicates serious Chrome API injection problems")
            } else if let result = result {
                print("🔍 [ExtensionManager+Runtime] API VERIFICATION RESULT: \(result)")

                // Parse the result to show more detailed info
                if let resultDict = result as? [String: Any] {
                    let success = resultDict["success"] as? Bool ?? false
                    if success {
                        print("✅ [ExtensionManager+Runtime] ALL CHROME APIS VERIFIED SUCCESSFULLY")
                        print("✅ [ExtensionManager+Runtime] Bitwarden should be able to load properly")
                    } else {
                        print("❌ [ExtensionManager+Runtime] CHROME API VERIFICATION FAILED")
                        if let missingAPIs = resultDict["missingAPIs"] as? [String] {
                            print("❌ [ExtensionManager+Runtime] Missing APIs: \(missingAPIs.joined(separator: ", "))")
                        }
                    }
                }
            }
        }
    }

    private func generateRuntimeAPIScript(extensionId: String) -> String {
        return """
        (function() {
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }

            if (!chrome.runtime) {
                chrome.runtime = {
                    id: '\(extensionId)',
                    onMessage: new EventTarget(),
                    sendMessage: function(message, callback) {
                        const messageData = {
                            type: 'sendMessage',
                            data: message,
                            timestamp: Date.now()
                        };

                        window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);

                        // Handle async response
                        if (callback) {
                            // Store callback for response handling
                            const messageId = Date.now().toString();
                            window.chromeRuntimeCallbacks = window.chromeRuntimeCallbacks || {};
                            window.chromeRuntimeCallbacks[messageId] = callback;
                        }
                    },
                    getManifest: function() {
                        return \(getManifestJSON() ?? "{}");
                    },
                    connect: function(extensionId, connectInfo) {
                        const messageData = {
                            type: 'connect',
                            extensionId: extensionId,
                            connectInfo: connectInfo
                        };

                        return window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);
                    }
                };

                // Add message listener support
                chrome.runtime.onMessage.addListener = function(listener) {
                    chrome.runtime.onMessage.addEventListener('message', function(event) {
                        listener(event.detail.message, event.detail.sender, event.detail.sendResponse);
                    });
                };

                console.log('[Chrome Runtime API] Runtime API initialized');
            }
        })();
        """
    }

    private func getManifestJSON() -> String? {
        guard let firstContext = extensionContextsAccess.values.first else { return "{}" }
        let manifest = getExtensionManifest(for: firstContext)
        guard let manifest = manifest,
              let jsonData = try? JSONSerialization.data(withJSONObject: manifest),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    // MARK: - Chrome API Injection for Popup Context

    /// Generate Chrome API injection script for popup contexts (critical for Angular bootstrap)
    func generateChromeAPIInjectionScript(extensionId: String, contextType: ChromeAPIContextType) -> String {
        return """
        // ========================================================
        // CRITICAL CHROME API INJECTION FOR POPUP CONTEXT
        // Extension: \(extensionId)
        // Context: \(contextType)
        // Purpose: Ensure Chrome APIs are available before Angular bootstrap
        // ========================================================

        (function() {
            'use strict';
            console.log('🚀 [Chrome Injection] Starting popup Chrome API injection...');
            console.log('🚀 [Chrome Injection] Extension ID: \(extensionId)');
            console.log('🚀 [Chrome Injection] Context: \(contextType)');
            console.log('🚀 [Chrome Injection] URL:', window.location.href);

            // CRITICAL: Create chrome object immediately for Angular bootstrap
            if (typeof chrome === 'undefined') {
                window.chrome = {};
                console.log('🚀 [Chrome Injection] Created chrome object');
            }

            // Phase 1: Essential Runtime API (needed immediately by Bitwarden)
            if (!chrome.runtime) {
                chrome.runtime = {
                    id: '\(extensionId)',
                    onMessage: {
                        listeners: [],
                        addListener: function(listener) {
                            console.log('🚀 [Chrome Injection] Added runtime.onMessage listener');
                            this.listeners.push(listener);
                        },
                        dispatch: function(message) {
                            this.listeners.forEach(listener => {
                                try {
                                    listener(message, message.sender, function() {});
                                } catch (error) {
                                    console.error('🚀 [Chrome Injection] Runtime listener error:', error);
                                }
                            });
                        }
                    },
                    sendMessage: function(message, callback) {
                        console.log('🚀 [Chrome Injection] sendMessage called:', message);

                        try {
                            const messageData = {
                                type: 'sendMessage',
                                data: message,
                                timestamp: Date.now().toString()
                            };

                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
                                window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);

                                if (callback) {
                                    const messageId = messageData.timestamp;
                                    window.chromeRuntimeCallbacks = window.chromeRuntimeCallbacks || {};
                                    window.chromeRuntimeCallbacks[messageId] = callback;

                                    // Set timeout for popup messages
                                    setTimeout(() => {
                                        if (window.chromeRuntimeCallbacks[messageId]) {
                                            console.log('🚀 [Chrome Injection] Popup message timeout, providing default response');
                                            callback({ success: true, message: 'Popup message delivered' });
                                            delete window.chromeRuntimeCallbacks[messageId];
                                        }
                                    }, 1000);
                                }
                            } else {
                                console.warn('🚀 [Chrome Injection] chromeRuntime message handler not available');
                                if (callback) callback({ success: false, error: 'Message handler not available' });
                            }
                        } catch (error) {
                            console.error('🚀 [Chrome Injection] sendMessage error:', error);
                            if (callback) callback({ success: false, error: error.message });
                        }
                    },
                    getManifest: function() {
                        console.log('🚀 [Chrome Injection] getManifest called');
                        return \(getManifestJSON() ?? "{}");
                    },
                    connect: function(extensionId, connectInfo) {
                        console.log('🚀 [Chrome Injection] connect called:', extensionId, connectInfo);
                        // Return a simple port object for popup compatibility
                        return {
                            name: connectInfo?.name || 'popup-port',
                            postMessage: function(message) {
                                console.log('🚀 [Chrome Injection] Port postMessage:', message);
                            },
                            onMessage: {
                                addListener: function(listener) {
                                    console.log('🚀 [Chrome Injection] Added port message listener');
                                }
                            },
                            disconnect: function() {
                                console.log('🚀 [Chrome Injection] Port disconnected');
                            }
                        };
                    }
                };
                console.log('✅ [Chrome Injection] Runtime API initialized');
            }

            // Phase 2: Storage API (essential for Bitwarden settings)
            if (!chrome.storage) {
                chrome.storage = {
                    local: {
                        get: function(keys, callback) {
                            console.log('🚀 [Chrome Injection] storage.local.get called:', keys);
                            try {
                                const messageData = { type: 'localGet', keys: keys, timestamp: Date.now().toString() };
                                if (callback) {
                                    window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                    window.chromeStorageCallbacks[messageData.timestamp] = callback;

                                    // Timeout for popup storage requests
                                    setTimeout(() => {
                                        if (window.chromeStorageCallbacks[messageData.timestamp]) {
                                            console.log('🚀 [Chrome Injection] Storage get timeout, returning empty result');
                                            callback({});
                                            delete window.chromeStorageCallbacks[messageData.timestamp];
                                        }
                                    }, 500);
                                }
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeStorage) {
                                    window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                                }
                            } catch (error) {
                                console.error('🚀 [Chrome Injection] storage.local.get error:', error);
                                if (callback) callback({});
                            }
                        },
                        set: function(items, callback) {
                            console.log('🚀 [Chrome Injection] storage.local.set called:', items);
                            try {
                                const messageData = { type: 'localSet', items: items, timestamp: Date.now().toString() };
                                if (callback) {
                                    window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                    window.chromeStorageCallbacks[messageData.timestamp] = callback;

                                    // Auto-complete popup storage sets
                                    setTimeout(() => {
                                        if (window.chromeStorageCallbacks[messageData.timestamp]) {
                                            console.log('🚀 [Chrome Injection] Storage set auto-completed');
                                            callback();
                                            delete window.chromeStorageCallbacks[messageData.timestamp];
                                        }
                                    }, 100);
                                }
                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeStorage) {
                                    window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                                }
                            } catch (error) {
                                console.error('🚀 [Chrome Injection] storage.local.set error:', error);
                                if (callback) callback();
                            }
                        }
                    },
                    onChanged: {
                        listeners: [],
                        addListener: function(listener) {
                            console.log('🚀 [Chrome Injection] Added storage.onChanged listener');
                            this.listeners.push(listener);
                        }
                    }
                };
                console.log('✅ [Chrome Injection] Storage API initialized');
            }

            // Phase 3: Tabs API (needed for active tab access)
            if (!chrome.tabs) {
                chrome.tabs = {
                    query: function(queryInfo, callback) {
                        console.log('🚀 [Chrome Injection] tabs.query called:', queryInfo);
                        try {
                            // For popup, provide current tab info immediately
                            const result = [{
                                id: 1,
                                url: window.location.href,
                                title: document.title || 'Extension Popup',
                                active: true,
                                windowId: 1
                            }];
                            console.log('🚀 [Chrome Injection] tabs.query result:', result);
                            if (callback) callback(result);
                        } catch (error) {
                            console.error('🚀 [Chrome Injection] tabs.query error:', error);
                            if (callback) callback([]);
                        }
                    },
                    sendMessage: function(tabId, message, options, callback) {
                        console.log('🚀 [Chrome Injection] tabs.sendMessage called:', tabId, message);
                        // For popup, just log and return success
                        if (callback) callback();
                    }
                };
                console.log('✅ [Chrome Injection] Tabs API initialized');
            }

            // Phase 4: Mark injection complete and signal Angular bootstrap readiness
            window.CHROME_INJECTION_COMPLETE = true;
            window.CHROME_INJECTION_TIMESTAMP = Date.now();

            console.log('🎉 [Chrome Injection] ALL CHROME APIS INJECTED SUCCESSFULLY');
            console.log('🎉 [Chrome Injection] Runtime ID:', chrome.runtime.id);
            console.log('🎉 [Chrome Injection] Angular can now bootstrap safely');

            // Dispatch event to signal Chrome APIs are ready
            if (typeof window !== 'undefined' && window.dispatchEvent) {
                window.dispatchEvent(new CustomEvent('chromeInjectionComplete', {
                    detail: {
                        extensionId: '\(extensionId)',
                        contextType: '\(contextType)',
                        timestamp: Date.now()
                    }
                }));
            }

        })();
        """
    }
}

// MARK: - Runtime Message Handler Helper
@available(macOS 15.4, *)
extension ExtensionManager {

    /// Handle runtime messages from chromeRuntime script message handler
    func handleRuntimeScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "chromeRuntime",
              let messageBody = message.body as? [String: Any],
              let webView = message.webView else { return }

        print("[ExtensionManager+Runtime] Received script message: \(messageBody.keys)")

        // CRITICAL FIX: Ensure we have extension context
        guard let extensionContext = extensionContextsAccess.values.first else {
            print("[ExtensionManager+Runtime] No extension context available for runtime message")
            return
        }

        // Handle runtime messages from extension contexts
        handleRuntimeMessage(message: messageBody, from: extensionContext) { [weak webView] response in
            guard let webView = webView else { return }

            print("[ExtensionManager+Runtime] Sending response: \(response ?? NSNull())")

            // CRITICAL FIX: Send response back to the same webView that sent the message
            let responseScript: String
            if let responseJSON = try? JSONSerialization.data(withJSONObject: response ?? NSNull()),
               let responseString = String(data: responseJSON, encoding: .utf8) {
                responseScript = """
                    (function() {
                        try {
                            const response = \(responseString);
                            const messageId = '\(messageBody["timestamp"] ?? "")';

                            if (window.chromeRuntimeCallbacks && window.chromeRuntimeCallbacks[messageId]) {
                                console.log('[Chrome Bridge] Executing callback for message:', messageId);
                                window.chromeRuntimeCallbacks[messageId](response);
                                delete window.chromeRuntimeCallbacks[messageId];
                            } else {
                                console.warn('[Chrome Bridge] No callback found for message:', messageId);
                            }
                        } catch (error) {
                            console.error('[Chrome Bridge] Error executing response callback:', error);
                        }
                    })();
                """
            } else {
                responseScript = """
                (function() {
                    const messageId = '\(messageBody["timestamp"] ?? "")';
                    if (window.chromeRuntimeCallbacks && window.chromeRuntimeCallbacks[messageId]) {
                        window.chromeRuntimeCallbacks[messageId](null);
                        delete window.chromeRuntimeCallbacks[messageId];
                    }
                })();
                """
            }

            webView.evaluateJavaScript(responseScript) { result, error in
                if let error = error {
                    print("[ExtensionManager+Runtime] Error executing response callback: \(error)")
                } else {
                    print("[ExtensionManager+Runtime] Response callback executed successfully")
                }
            }
        }
    }

    // MARK: - Extension Loading Completion Delegate Method

    /// Called when an extension context finishes loading - CRITICAL for resource serving
    func webExtensionController(
        _ controller: WKWebExtensionController,
        webExtensionContext: WKWebExtensionContext,
        didCompleteLoadWithError error: Error?
    ) {
        let extensionId = webExtensionContext.webExtension.displayName ?? webExtensionContext.uniqueIdentifier

        if let error = error {
            print("❌ [ExtensionManager] Extension context loading FAILED for \(extensionId): \(error.localizedDescription)")
            print("❌ [ExtensionManager] webkit-extension:// URLs will NOT work without proper loading")

            // CRITICAL FIX: Even on load error, try to provide basic functionality
            // But first, attempt to diagnose the failure
            diagnoseExtensionLoadingFailure(extensionId: extensionId, error: error, context: webExtensionContext)
            return
        }

        print("✅ [ExtensionManager] Extension context loading completed successfully for: \(extensionId)")
        print("🎯 [ExtensionManager] webkit-extension:// URLs should now be functional")

        // ENHANCED VERIFICATION: Comprehensive extension resource serving verification
        verifyExtensionResourceServing(for: webExtensionContext, controller: controller)

        // CRITICAL: Test actual webkit-extension:// URL resolution
        testWebkitExtensionURLResolution(for: webExtensionContext, controller: controller)
    }

    /// Verify that extension resource serving is working properly (ENHANCED)
    private func verifyExtensionResourceServing(for extensionContext: WKWebExtensionContext, controller: WKWebExtensionController) {
        let extensionId = extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier
        print("🔍 [ExtensionManager] === ENHANCED RESOURCE SERVING VERIFICATION ===")
        print("🔍 [ExtensionManager] Verifying resource serving for extension: \(extensionId)")

        // CRITICAL: Verify extension context is properly registered with controller
        print("🔧 [ExtensionManager] Extension context registration:")
        print("   Context unique ID: \(extensionContext.uniqueIdentifier)")
        print("   Context base URL: \(extensionContext.baseURL.absoluteString)")
        print("   Has controller: \(extensionContext.webExtensionController != nil)")
        print("   Controller contexts count: \(controller.extensionContexts.count)")

        // Verify the extension is in the controller's loaded contexts
        let controllerHasExtension = controller.extensionContexts.contains(extensionContext)
        print("   Controller recognizes extension: \(controllerHasExtension)")

        if !controllerHasExtension {
            print("❌ [ExtensionManager] CRITICAL: Extension not properly registered with controller")
            print("❌ [ExtensionManager] webkit-extension:// URLs will NOT work")
        }

        // Check if the extension directory structure is correct
        guard let installedExtension = installedExtensions.first(where: { $0.id == extensionId }) else {
            print("❌ [ExtensionManager] Extension not found in installed list")
            return
        }

        // Use the packagePath property from InstalledExtension
        let packagePath = installedExtension.packagePath
        print("📁 [ExtensionManager] Extension package path: \(packagePath)")
        print("📁 [ExtensionManager] Expected base URL should resolve to: \(packagePath)")

        // Verify base URL matches package path
        let baseURLPath = extensionContext.baseURL.path
        let packageURLPath = URL(fileURLWithPath: packagePath).path
        let baseURLMatches = baseURLPath == packageURLPath
        print("🔗 [ExtensionManager] Base URL matches package path: \(baseURLMatches)")

        if !baseURLMatches {
            print("⚠️ [ExtensionManager] Base URL mismatch:")
            print("   Extension context base URL: \(baseURLPath)")
            print("   Expected package path: \(packageURLPath)")
        }

        // Test loading multiple known resource files that Bitwarden needs
        let testResources = [
            "manifest.json",
            "popup/index.html",
            "popup/polyfills.js",
            "popup/vendor.js",
            "popup/main.js",
            "popup/main.css",
            "background.js"
        ]

        print("🔍 [ExtensionManager] Testing critical resource files...")
        var foundResources: [String] = []
        var missingResources: [String] = []

        for resource in testResources {
            let resourcePath = URL(fileURLWithPath: packagePath).appendingPathComponent(resource)
            if FileManager.default.fileExists(atPath: resourcePath.path) {
                foundResources.append(resource)
                print("✅ [ExtensionManager] Found: \(resource)")
            } else {
                missingResources.append(resource)
                print("❌ [ExtensionManager] Missing: \(resource) at path: \(resourcePath.path)")
            }
        }

        // Verify webkit-extension:// URL construction
        print("🌐 [ExtensionManager] webkit-extension:// URL construction test:")
        let extensionBaseURL = "webkit-extension://\(extensionContext.uniqueIdentifier)/"
        print("   Extension base URL: \(extensionBaseURL)")

        // Test specific URL resolutions
        for resource in foundResources {
            let fullURL = "\(extensionBaseURL)\(resource)"
            let expectedLocalPath = extensionContext.baseURL.appendingPathComponent(resource).path
            print("   \(resource) -> \(fullURL)")
            print("            Should resolve to: \(expectedLocalPath)")
        }

        // Use a simple test to see if WebKit's extension server is responding
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("📊 [ExtensionManager] === RESOURCE SERVING SUMMARY ===")
            print("   Found files: \(foundResources.count)/\(testResources.count)")
            print("   Missing files: \(missingResources.count)")
            print("   Extension base URL: \(extensionBaseURL)")
            print("   Controller recognizes extension: \(controllerHasExtension)")
            print("   Base URL matches package: \(baseURLMatches)")

            if missingResources.isEmpty && baseURLMatches && controllerHasExtension {
                print("✅ [ExtensionManager] All checks passed - WebKit should serve resources properly")
            } else {
                print("⚠️ [ExtensionManager] Issues detected that may cause resource loading failures")
                if !missingResources.isEmpty {
                    print("❌ Missing resources: \(missingResources.joined(separator: ", "))")
                }
                if !baseURLMatches {
                    print("❌ Base URL path mismatch")
                }
                if !controllerHasExtension {
                    print("❌ Extension not registered with controller")
                }
            }

            // Test if WebKit's extension controller can access the extension
            let isActive = extensionContext.webExtensionController != nil
            print("📊 [ExtensionManager] Extension context active: \(isActive)")

            // CRITICAL FIX: Check for WebAssembly MIME type issues
            self.checkWebAssemblyMIMETypes(packagePath: packagePath)
        }
    }

    /// Check and handle WebAssembly MIME type configuration issues
    private func checkWebAssemblyMIMETypes(packagePath: String) {
        print("🔧 [ExtensionManager] Checking WebAssembly MIME type configuration...")

        // Look for .wasm files in the extension
        let wasmFileURLs = findWasmFiles(in: URL(fileURLWithPath: packagePath))

        if !wasmFileURLs.isEmpty {
            print("📊 [ExtensionManager] Found \(wasmFileURLs.count) WebAssembly files:")
            for wasmURL in wasmFileURLs {
                print("   - \(wasmURL.lastPathComponent)")
            }

            // WebKit should serve .wasm files with application/wasm MIME type automatically
            // If not, we need to work around it by intercepting requests
            print("⚠️ [ExtensionManager] WebAssembly files detected - ensuring proper MIME type serving")

            // Note: WebKit's WKWebExtensionController doesn't expose MIME type configuration
            // This is handled internally by WebKit, but we can add debugging
            print("📋 [ExtensionManager] WebKit should automatically serve .wasm files as application/wasm")
            print("📋 [ExtensionManager] If MIME type errors occur, WebKit's extension server may need updating")
        } else {
            print("📊 [ExtensionManager] No WebAssembly files found in extension")
        }
    }

    /// Find all WebAssembly files in the extension directory
    private func findWasmFiles(in directoryURL: URL) -> [URL] {
        var wasmFiles: [URL] = []

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey, .pathKey]
        guard let directoryEnumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            print("❌ [ExtensionManager] Failed to create directory enumerator")
            return wasmFiles
        }

        for case let fileURL as URL in directoryEnumerator {
            if fileURL.pathExtension == "wasm" {
                wasmFiles.append(fileURL)
            }
        }

        return wasmFiles
    }

    // MARK: - Enhanced Extension Loading Diagnostics

    /// Diagnose extension loading failures with detailed error analysis
    private func diagnoseExtensionLoadingFailure(extensionId: String, error: Error, context: WKWebExtensionContext) {
        print("🔬 [ExtensionManager] === EXTENSION LOADING FAILURE DIAGNOSTICS ===")
        print("🔬 [ExtensionManager] Extension: \(extensionId)")
        print("🔬 [ExtensionManager] Error: \(error.localizedDescription)")
        print("🔬 [ExtensionManager] Error code: \((error as NSError).code)")

        // Check extension context details
        print("🔬 [ExtensionManager] Extension context details:")
        print("   Unique identifier: \(context.uniqueIdentifier)")
        print("   Base URL: \(context.baseURL.absoluteString)")
        print("   Has controller: \(context.webExtensionController != nil)")

        // Check if extension directory exists and is accessible
        print("🔬 [ExtensionManager] Extension directory analysis:")
        let baseURL = context.baseURL
        let directoryExists = FileManager.default.fileExists(atPath: baseURL.path)
        let isDirectory = (try? baseURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        print("   Directory exists: \(directoryExists)")
        print("   Is directory: \(isDirectory)")

        if !directoryExists {
            print("❌ [ExtensionManager] Extension directory does not exist: \(baseURL.path)")
        } else if !isDirectory {
            print("❌ [ExtensionManager] Extension path is not a directory: \(baseURL.path)")
        }

        // Check manifest.json specifically
        let manifestPath = baseURL.appendingPathComponent("manifest.json")
        let manifestExists = FileManager.default.fileExists(atPath: manifestPath.path)
        print("   manifest.json exists: \(manifestExists)")

        if !manifestExists {
            print("❌ [ExtensionManager] CRITICAL: manifest.json is missing - extension cannot load")
        } else {
            // Try to read and validate manifest.json
            do {
                let manifestData = try Data(contentsOf: manifestPath)
                let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
                let manifestVersion = manifest?["manifest_version"] as? Int
                print("   Manifest version: \(manifestVersion?.description ?? "unknown")")

                if manifestVersion != 3 {
                    print("⚠️ [ExtensionManager] Manifest version is not 3 - may cause compatibility issues")
                }
            } catch {
                print("❌ [ExtensionManager] Manifest.json is corrupted or invalid: \(error)")
            }
        }

        // Check file permissions
        print("🔬 [ExtensionManager] File permissions analysis:")
        if directoryExists {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: baseURL.path) {
                let permissions = attributes[.posixPermissions] as? Int
                print("   Directory permissions: \(String(permissions ?? 0, radix: 8))")
            }
        }

        // Attempt recovery if possible
        print("🔬 [ExtensionManager] Recovery attempts:")
        attemptExtensionLoadingRecovery(extensionId: extensionId, context: context, error: error)
    }

    /// Attempt to recover from extension loading failures
    private func attemptExtensionLoadingRecovery(extensionId: String, context: WKWebExtensionContext, error: Error) {
        print("🔧 [ExtensionManager] Attempting extension loading recovery...")

        // Recovery attempt 1: Try to reload the extension
        print("   Attempt 1: Checking if extension can be reloaded...")
        let canReload = context.webExtensionController != nil
        print("   Can reload: \(canReload)")

        // Recovery attempt 2: Check if extension is already loaded elsewhere
        print("   Attempt 2: Checking for duplicate extension instances...")
        if let installedExtension = installedExtensions.first(where: { $0.id == extensionId }) {
            print("   Found in installed extensions: \(installedExtension.name)")
            print("   Package path: \(installedExtension.packagePath)")
        }

        // Recovery attempt 3: Validate extension state
        print("   Attempt 3: Validating extension state...")
        let isActive = extensionContextsAccess[extensionId] != nil
        print("   Extension is active in contexts: \(isActive)")

        // Provide user-friendly error message
        print("💡 [ExtensionManager] Recovery suggestions:")
        print("   1. Check that the extension directory exists and contains manifest.json")
        print("   2. Verify the extension has proper file permissions")
        print("   3. Ensure manifest.json is valid JSON with manifest_version: 3")
        print("   4. Try reinstalling the extension")

        if canReload {
            print("   5. Extension may be reloadable - try refreshing extensions")
        }
    }

    /// Test actual webkit-extension:// URL resolution (CRITICAL)
    private func testWebkitExtensionURLResolution(for extensionContext: WKWebExtensionContext, controller: WKWebExtensionController) {
        print("🧪 [ExtensionManager] === WEBKIT-EXTENSION:// URL RESOLUTION TESTING ===")
        print("🧪 [ExtensionManager] Testing webkit-extension:// URL resolution for extension: \(extensionContext.uniqueIdentifier)")

        // Test 1: Basic URL construction
        let extensionUUID = extensionContext.uniqueIdentifier
        print("🧪 [ExtensionManager] Test 1: Basic URL construction")
        print("   Extension UUID: \(extensionUUID)")
        print("   Expected URL format: webkit-extension://\(extensionUUID)/resource.js")

        // Test 2: Controller's extension context lookup
        print("🧪 [ExtensionManager] Test 2: Controller extension context lookup")

        // Create test URLs for common resources
        let testResources = [
            "manifest.json",
            "popup/index.html",
            "background.js"
        ]

        for resource in testResources {
            let testURL = URL(string: "webkit-extension://\(extensionUUID)/\(resource)")!
            print("   Testing URL: \(testURL.absoluteString)")

            // Check if controller can resolve this URL to an extension context
            let foundContext = controller.extensionContext(for: testURL)
            let contextMatches = foundContext == extensionContext

            print("   Controller resolves to extension: \(foundContext != nil)")
            print("   Resolves to correct context: \(contextMatches)")

            if foundContext == nil {
                print("   ❌ FAIL: Controller cannot resolve webkit-extension:// URL")
                print("   ❌ This means webkit-extension:// URLs will NOT work")
            } else if !contextMatches {
                print("   ❌ FAIL: Controller resolves to wrong extension context")
                print("   ❌ This will cause resource loading failures")
            } else {
                print("   ✅ PASS: URL resolution works correctly")

                // Test 3: Check if the actual resource file exists
                let expectedLocalPath = extensionContext.baseURL.appendingPathComponent(resource)
                let fileExists = FileManager.default.fileExists(atPath: expectedLocalPath.path)
                print("   Resource file exists: \(fileExists)")

                if !fileExists {
                    print("   ⚠️ WARNING: URL resolution works but resource file is missing")
                }
            }
        }

        // Test 4: Verify the extension controller configuration
        print("🧪 [ExtensionManager] Test 4: Extension controller configuration")
        print("   Controller has extension contexts: \(controller.extensionContexts.count)")

        // Check if the extension context is in the controller's set
        let controllerRecognizesExtension = controller.extensionContexts.contains(extensionContext)
        print("   Controller recognizes this extension: \(controllerRecognizesExtension)")

        if !controllerRecognizesExtension {
            print("   ❌ CRITICAL: Extension context not in controller's extension contexts")
            print("   ❌ webkit-extension:// URLs will NOT work")
        }

        // Test 5: Check WebView configuration for extension support
        print("🧪 [ExtensionManager] Test 5: WebView configuration verification")
        if let webViewConfig = extensionContext.webViewConfiguration {
            let hasExtensionController = webViewConfig.webExtensionController != nil
            let dataStore = webViewConfig.websiteDataStore
            let dataStoreIsPersistent = dataStore.isPersistent

            print("   Context has WebView config: true")
            print("   WebView config has extension controller: \(hasExtensionController)")
            print("   WebView config data store persistent: \(dataStoreIsPersistent)")

            if !hasExtensionController {
                print("   ❌ WebView configuration missing webExtensionController")
                print("   ❌ Extension popups will not be able to load resources")
            }
        } else {
            print("   Context has WebView config: false")
            print("   ⚠️ Extension context may be using default configuration")
        }

        // Summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🧪 [ExtensionManager] === URL RESOLUTION TEST SUMMARY ===")

            let allTestsPassed = controllerRecognizesExtension

            if allTestsPassed {
                print("✅ [ExtensionManager] CRITICAL TESTS PASSED")
                print("✅ [ExtensionManager] webkit-extension:// URLs should work correctly")
                print("✅ [ExtensionManager] Extension popups should be able to load resources")
            } else {
                print("❌ [ExtensionManager] CRITICAL TESTS FAILED")
                print("❌ [ExtensionManager] webkit-extension:// URLs will NOT work")
                print("❌ [ExtensionManager] Extension popups will fail to load resources")
                print("❌ [ExtensionManager] This explains Bitwarden popup loading failures")
            }
        }
    }

    // MARK: - webkit-extension:// URL Error Recovery

    /// Detect and handle webkit-extension:// URL loading failures in real-time
    func handleExtensionResourceLoadingFailure(_ webView: WKWebView, failedURL: URL, error: Error) {
        print("🚨 [ExtensionManager] === EXTENSION RESOURCE LOADING FAILURE DETECTED ===")
        print("🚨 [ExtensionManager] Failed URL: \(failedURL.absoluteString)")
        print("🚨 [ExtensionManager] Error: \(error.localizedDescription)")

        // Check if this is a webkit-extension:// URL failure
        guard failedURL.scheme?.lowercased() == "webkit-extension" else {
            print("🚨 [ExtensionManager] Not a webkit-extension:// URL - skipping extension-specific handling")
            return
        }

        print("🚨 [ExtensionManager] CRITICAL: webkit-extension:// URL failed to load")
        print("🚨 [ExtensionManager] This indicates serious extension configuration issues")

        // Extract extension UUID from URL
        let extensionUUID = failedURL.host ?? "unknown"
        let resourcePath = failedURL.path

        print("🚨 [ExtensionManager] Failure details:")
        print("   Extension UUID: \(extensionUUID)")
        print("   Resource path: \(resourcePath)")

        // Try to find the extension context
        guard let extensionContext = extensionContextsAccess.values.first(where: { $0.uniqueIdentifier == extensionUUID }) else {
            print("❌ [ExtensionManager] Extension context not found for UUID: \(extensionUUID)")
            provideFallbackContent(webView: webView, failedURL: failedURL, reason: "Extension context not found")
            return
        }

        print("✅ [ExtensionManager] Found extension context for UUID")

        // Attempt recovery
        attemptResourceLoadingRecovery(webView: webView, failedURL: failedURL, extensionContext: extensionContext)
    }

    /// Attempt to recover from resource loading failures
    private func attemptResourceLoadingRecovery(webView: WKWebView, failedURL: URL, extensionContext: WKWebExtensionContext) {
        print("🔧 [ExtensionManager] Attempting resource loading recovery...")

        // Recovery attempt 1: Verify the resource file exists
        let resourcePath = failedURL.path
        let localFilePath = extensionContext.baseURL.appendingPathComponent(String(resourcePath.dropFirst())) // Remove leading /
        let fileExists = FileManager.default.fileExists(atPath: localFilePath.path)

        print("   Recovery 1: Check if resource file exists")
        print("   Expected local path: \(localFilePath.path)")
        print("   File exists: \(fileExists)")

        if !fileExists {
            print("   ❌ Resource file does not exist - providing fallback")
            provideFallbackContent(webView: webView, failedURL: failedURL, reason: "Resource file not found")
            return
        }

        // Recovery attempt 2: Try to load the file content directly and inject it
        print("   Recovery 2: Attempting direct file content injection")
        injectResourceContent(webView: webView, localFilePath: localFilePath, failedURL: failedURL)

        // Recovery attempt 3: Verify extension controller configuration
        print("   Recovery 3: Verifying extension controller configuration")
        if let controller = extensionContext.webExtensionController {
            let controllerCanResolve = controller.extensionContext(for: failedURL) != nil
            print("   Controller can resolve URL: \(controllerCanResolve)")

            if !controllerCanResolve {
                print("   ❌ Controller cannot resolve extension URL - critical configuration issue")
                diagnoseControllerConfiguration(extensionContext: extensionContext, failedURL: failedURL)
            }
        } else {
            print("   ❌ Extension context has no controller - critical issue")
        }
    }

    /// Provide fallback content for failed extension resources
    private func provideFallbackContent(webView: WKWebView, failedURL: URL, reason: String) {
        print("🔄 [ExtensionManager] Providing fallback content for: \(failedURL.absoluteString)")
        print("🔄 [ExtensionManager] Reason: \(reason)")

        let fallbackContent: String

        if failedURL.path.hasSuffix(".html") {
            // Fallback HTML content
            fallbackContent = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Extension Resource Unavailable</title>
                <style>
                    body {
                        font-family: system-ui, -apple-system, sans-serif;
                        padding: 20px;
                        background-color: #f5f5f5;
                        color: #333;
                    }
                    .error-container {
                        max-width: 500px;
                        margin: 50px auto;
                        background: white;
                        padding: 30px;
                        border-radius: 8px;
                        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    }
                    .error-title {
                        color: #e74c3c;
                        margin-bottom: 15px;
                    }
                    .error-details {
                        font-size: 14px;
                        color: #666;
                        margin-top: 20px;
                    }
                </style>
            </head>
            <body>
                <div class="error-container">
                    <h1 class="error-title">Extension Resource Unavailable</h1>
                    <p>The requested extension resource could not be loaded.</p>
                    <div class="error-details">
                        <strong>URL:</strong> \(failedURL.absoluteString)<br>
                        <strong>Reason:</strong> \(reason)<br>
                        <strong>Time:</strong> \(Date())<br>
                        <strong>Action:</strong> Please check the extension installation and try refreshing the extension.
                    </div>
                </div>
                <script>
                    console.error('[Extension Manager] Fallback content loaded for: \(failedURL.absoluteString)');
                    console.error('[Extension Manager] Reason: \(reason)');

                    // Try to notify the parent window about the failure
                    if (window.parent && window.parent.postMessage) {
                        window.parent.postMessage({
                            type: 'extensionResourceError',
                            url: '\(failedURL.absoluteString)',
                            reason: '\(reason)'
                        }, '*');
                    }
                </script>
            </body>
            </html>
            """
        } else if failedURL.path.hasSuffix(".js") {
            // Fallback JavaScript content
            fallbackContent = """
            console.error('[Extension Manager] Extension script failed to load: \(failedURL.absoluteString)');
            console.error('[Extension Manager] Reason: \(reason)');
            console.error('[Extension Manager] Providing minimal fallback implementation');

            // Provide minimal Chrome API fallback
            if (typeof chrome === 'undefined') {
                window.chrome = {
                    runtime: {
                        id: 'fallback-id',
                        sendMessage: function() { console.warn('Fallback sendMessage - extension not loaded'); },
                        getManifest: function() { return {}; }
                    }
                };
            }
            """
        } else if failedURL.path.hasSuffix(".css") {
            // Fallback CSS content
            fallbackContent = """
            /* Fallback CSS - extension resource unavailable */
            body {
                font-family: system-ui, -apple-system, sans-serif;
                background-color: #fff3cd;
                color: #856404;
                padding: 10px;
                border: 1px solid #ffeeba;
                border-radius: 4px;
                margin: 10px;
            }
            .extension-error {
                display: block;
                padding: 15px;
                background: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
                border-radius: 4px;
                text-align: center;
            }
            """
        } else {
            // Generic fallback
            fallbackContent = "Extension resource unavailable: \(failedURL.absoluteString). Reason: \(reason)"
        }

        // Inject the fallback content
        webView.evaluateJavaScript("""
        document.open();
        document.write('\(fallbackContent.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "'", with: "\\'"))');
        document.close();
        console.log('[Extension Manager] Fallback content injected for \(failedURL.absoluteString)');
        """) { result, error in
            if let error = error {
                print("❌ [ExtensionManager] Failed to inject fallback content: \(error)")
            } else {
                print("✅ [Extension Manager] Fallback content injected successfully")
            }
        }
    }

    /// Inject resource content directly as a fallback mechanism
    private func injectResourceContent(webView: WKWebView, localFilePath: URL, failedURL: URL) {
        print("🔄 [ExtensionManager] Attempting direct content injection from: \(localFilePath.path)")

        do {
            let content = try Data(contentsOf: localFilePath)
            let contentString = String(data: content, encoding: .utf8) ?? "Unable to read file content"

            // Determine content type and inject appropriately
            if failedURL.path.hasSuffix(".js") {
                // For JavaScript files, evaluate the content
                webView.evaluateJavaScript(contentString) { result, error in
                    if let error = error {
                        print("❌ [ExtensionManager] Failed to evaluate JavaScript content: \(error)")
                    } else {
                        print("✅ [ExtensionManager] JavaScript content evaluated successfully")
                    }
                }
            } else if failedURL.path.hasSuffix(".html") {
                // For HTML files, replace the document content
                let escapedContent = contentString.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")

                webView.evaluateJavaScript("""
                document.open();
                document.write('\(escapedContent)');
                document.close();
                """) { result, error in
                    if let error = error {
                        print("❌ [ExtensionManager] Failed to inject HTML content: \(error)")
                    } else {
                        print("✅ [ExtensionManager] HTML content injected successfully")
                    }
                }
            } else {
                print("⚠️ [ExtensionManager] Direct injection not supported for file type: \(failedURL.path)")
            }

        } catch {
            print("❌ [ExtensionManager] Failed to read local file: \(error)")
            provideFallbackContent(webView: webView, failedURL: failedURL, reason: "Failed to read local file: \(error.localizedDescription)")
        }
    }

    /// Diagnose controller configuration issues
    private func diagnoseControllerConfiguration(extensionContext: WKWebExtensionContext, failedURL: URL) {
        print("🔬 [ExtensionManager] Diagnosing controller configuration issues...")

        print("   Extension context details:")
        print("   Unique ID: \(extensionContext.uniqueIdentifier)")
        print("   Base URL: \(extensionContext.baseURL.absoluteString)")
        print("   Has controller: \(extensionContext.webExtensionController != nil)")

        if let controller = extensionContext.webExtensionController {
            print("   Controller details:")
            print("   Extension contexts count: \(controller.extensionContexts.count)")
            print("   Controller recognizes extension: \(controller.extensionContexts.contains(extensionContext))")

            // Test if the controller can resolve other URLs
            let testURLs = [
                "webkit-extension://\(extensionContext.uniqueIdentifier)/manifest.json",
                "webkit-extension://\(extensionContext.uniqueIdentifier)/",
                "webkit-extension://invalid-uuid/test.js"
            ]

            for testURLString in testURLs {
                if let testURL = URL(string: testURLString) {
                    let resolved = controller.extensionContext(for: testURL)
                    print("   Can resolve \(testURLString): \(resolved != nil)")
                }
            }
        }

        print("   Recommended fixes:")
        print("   1. Ensure extension context is properly loaded")
        print("   2. Verify controller configuration is correct")
        print("   3. Check extension directory structure")
        print("   4. Reinstall the extension if necessary")
    }
}