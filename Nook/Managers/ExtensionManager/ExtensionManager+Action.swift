//
//  ExtensionManager+Action.swift
//  Nook
//
//  Chrome Action API Bridge for WKWebExtension support
//  Implements chrome.action.* APIs (Manifest v3)
//

import Foundation
import WebKit
import AppKit

// MARK: - Chrome Action API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Action State Storage
    
    /// Storage for per-extension action state
    private struct ActionState {
        var badgeText: String = ""
        var badgeBackgroundColor: [CGFloat] = [0.5, 0.5, 0.5, 1.0] // Default gray
        var badgeTextColor: [CGFloat] = [1.0, 1.0, 1.0, 1.0] // Default white
        var title: String = ""
        var icon: [String: Any]? = nil
        var popup: String? = nil
        var isEnabled: Bool = true
    }
    
    /// Global storage for action states (in-memory for now)
    /// Key: extensionId, Value: ActionState
    private static var actionStates: [String: ActionState] = [:]
    private static var actionStatesLock = NSLock()
    
    private var actionStatesAccess: [String: ActionState] {
        get {
            ExtensionManager.actionStatesLock.lock()
            defer { ExtensionManager.actionStatesLock.unlock() }
            return ExtensionManager.actionStates
        }
        set {
            ExtensionManager.actionStatesLock.lock()
            defer { ExtensionManager.actionStatesLock.unlock() }
            ExtensionManager.actionStates = newValue
        }
    }
    
    // MARK: - Action API Methods
    
    /// Get or initialize action state for an extension
    func getActionState(for extensionId: String) -> ActionState {
        ExtensionManager.actionStatesLock.lock()
        defer { ExtensionManager.actionStatesLock.unlock() }
        
        if let state = ExtensionManager.actionStates[extensionId] {
            return state
        } else {
            // Initialize with manifest defaults if available
            let newState = ActionState()
            ExtensionManager.actionStates[extensionId] = newState
            return newState
        }
    }
    
    /// Update action state for an extension
    func setActionState(for extensionId: String, state: ActionState) {
        ExtensionManager.actionStatesLock.lock()
        defer { ExtensionManager.actionStatesLock.unlock() }
        ExtensionManager.actionStates[extensionId] = state
        
        // Notify UI to update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .extensionActionUpdated, object: nil, userInfo: ["extensionId": extensionId])
        }
    }
    
    // MARK: - chrome.action.setBadgeText
    
    func handleActionSetBadgeText(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📛 [ExtensionManager+Action] setBadgeText called")
        
        guard let text = message["text"] as? String else {
            print("❌ [ExtensionManager+Action] Missing 'text' parameter")
            replyHandler(["error": "Missing 'text' parameter"])
            return
        }
        
        var state = getActionState(for: extensionId)
        state.badgeText = text
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Badge text set to: '\(text)'")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.getBadgeText
    
    func handleActionGetBadgeText(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📛 [ExtensionManager+Action] getBadgeText called")
        
        let state = getActionState(for: extensionId)
        print("✅ [ExtensionManager+Action] Badge text: '\(state.badgeText)'")
        replyHandler(["text": state.badgeText])
    }
    
    // MARK: - chrome.action.setBadgeBackgroundColor
    
    func handleActionSetBadgeBackgroundColor(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🎨 [ExtensionManager+Action] setBadgeBackgroundColor called")
        
        guard let color = message["color"] else {
            print("❌ [ExtensionManager+Action] Missing 'color' parameter")
            replyHandler(["error": "Missing 'color' parameter"])
            return
        }
        
        var state = getActionState(for: extensionId)
        
        // Parse color - can be array [r, g, b, a] or string "#RRGGBB"
        if let colorArray = color as? [CGFloat] {
            state.badgeBackgroundColor = colorArray
        } else if let colorString = color as? String {
            // Parse hex color
            state.badgeBackgroundColor = parseHexColor(colorString)
        }
        
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Badge background color set")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.getBadgeBackgroundColor
    
    func handleActionGetBadgeBackgroundColor(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🎨 [ExtensionManager+Action] getBadgeBackgroundColor called")
        
        let state = getActionState(for: extensionId)
        print("✅ [ExtensionManager+Action] Badge background color: \(state.badgeBackgroundColor)")
        replyHandler(["color": state.badgeBackgroundColor])
    }
    
    // MARK: - chrome.action.setBadgeTextColor
    
    func handleActionSetBadgeTextColor(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🎨 [ExtensionManager+Action] setBadgeTextColor called")
        
        guard let color = message["color"] else {
            print("❌ [ExtensionManager+Action] Missing 'color' parameter")
            replyHandler(["error": "Missing 'color' parameter"])
            return
        }
        
        var state = getActionState(for: extensionId)
        
        // Parse color
        if let colorArray = color as? [CGFloat] {
            state.badgeTextColor = colorArray
        } else if let colorString = color as? String {
            state.badgeTextColor = parseHexColor(colorString)
        }
        
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Badge text color set")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.getBadgeTextColor
    
    func handleActionGetBadgeTextColor(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🎨 [ExtensionManager+Action] getBadgeTextColor called")
        
        let state = getActionState(for: extensionId)
        print("✅ [ExtensionManager+Action] Badge text color: \(state.badgeTextColor)")
        replyHandler(["color": state.badgeTextColor])
    }
    
    // MARK: - chrome.action.setTitle
    
    func handleActionSetTitle(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📝 [ExtensionManager+Action] setTitle called")
        
        guard let title = message["title"] as? String else {
            print("❌ [ExtensionManager+Action] Missing 'title' parameter")
            replyHandler(["error": "Missing 'title' parameter"])
            return
        }
        
        var state = getActionState(for: extensionId)
        state.title = title
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Title set to: '\(title)'")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.getTitle
    
    func handleActionGetTitle(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📝 [ExtensionManager+Action] getTitle called")
        
        let state = getActionState(for: extensionId)
        print("✅ [ExtensionManager+Action] Title: '\(state.title)'")
        replyHandler(["title": state.title])
    }
    
    // MARK: - chrome.action.setPopup
    
    func handleActionSetPopup(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🪟 [ExtensionManager+Action] setPopup called")
        
        guard let popup = message["popup"] as? String else {
            print("❌ [ExtensionManager+Action] Missing 'popup' parameter")
            replyHandler(["error": "Missing 'popup' parameter"])
            return
        }
        
        var state = getActionState(for: extensionId)
        state.popup = popup.isEmpty ? nil : popup
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Popup set to: '\(popup)'")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.getPopup
    
    func handleActionGetPopup(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🪟 [ExtensionManager+Action] getPopup called")
        
        let state = getActionState(for: extensionId)
        let popupValue = state.popup ?? ""
        print("✅ [ExtensionManager+Action] Popup: '\(popupValue)'")
        replyHandler(["popup": popupValue])
    }
    
    // MARK: - chrome.action.setIcon
    
    func handleActionSetIcon(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🖼️ [ExtensionManager+Action] setIcon called")
        
        // Icon can be imageData (base64) or path
        var state = getActionState(for: extensionId)
        state.icon = message
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Icon updated")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.enable / disable
    
    func handleActionEnable(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("✅ [ExtensionManager+Action] enable called")
        
        var state = getActionState(for: extensionId)
        state.isEnabled = true
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Action enabled")
        replyHandler(["success": true])
    }
    
    func handleActionDisable(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🚫 [ExtensionManager+Action] disable called")
        
        var state = getActionState(for: extensionId)
        state.isEnabled = false
        setActionState(for: extensionId, state: state)
        
        print("✅ [ExtensionManager+Action] Action disabled")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.action.isEnabled
    
    func handleActionIsEnabled(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🔍 [ExtensionManager+Action] isEnabled called")
        
        let state = getActionState(for: extensionId)
        print("✅ [ExtensionManager+Action] Is enabled: \(state.isEnabled)")
        replyHandler(["enabled": state.isEnabled])
    }
    
    // MARK: - Script Message Handler
    
    /// Handles script messages for chrome.action API
    func handleActionScriptMessage(_ message: WKScriptMessage) {
        print("📨 [ExtensionManager+Action] Received action script message")
        
        guard let body = message.body as? [String: Any] else {
            print("❌ [ExtensionManager+Action] Invalid message body")
            return
        }
        
        guard let extensionId = body["extensionId"] as? String else {
            print("❌ [ExtensionManager+Action] Missing extensionId")
            return
        }
        
        guard let method = body["method"] as? String else {
            print("❌ [ExtensionManager+Action] Missing method")
            return
        }
        
        let args = body["args"] as? [String: Any] ?? [:]
        let messageId = body["messageId"] as? String ?? UUID().uuidString
        
        // Route to appropriate handler
        let replyHandler: (Any?) -> Void = { [weak self] response in
            self?.sendActionResponse(messageId: messageId, response: response, to: message.webView)
        }
        
        switch method {
        case "setBadgeText":
            handleActionSetBadgeText(args, from: extensionId, replyHandler: replyHandler)
        case "getBadgeText":
            handleActionGetBadgeText(args, from: extensionId, replyHandler: replyHandler)
        case "setBadgeBackgroundColor":
            handleActionSetBadgeBackgroundColor(args, from: extensionId, replyHandler: replyHandler)
        case "getBadgeBackgroundColor":
            handleActionGetBadgeBackgroundColor(args, from: extensionId, replyHandler: replyHandler)
        case "setBadgeTextColor":
            handleActionSetBadgeTextColor(args, from: extensionId, replyHandler: replyHandler)
        case "getBadgeTextColor":
            handleActionGetBadgeTextColor(args, from: extensionId, replyHandler: replyHandler)
        case "setTitle":
            handleActionSetTitle(args, from: extensionId, replyHandler: replyHandler)
        case "getTitle":
            handleActionGetTitle(args, from: extensionId, replyHandler: replyHandler)
        case "setPopup":
            handleActionSetPopup(args, from: extensionId, replyHandler: replyHandler)
        case "getPopup":
            handleActionGetPopup(args, from: extensionId, replyHandler: replyHandler)
        case "setIcon":
            handleActionSetIcon(args, from: extensionId, replyHandler: replyHandler)
        case "enable":
            handleActionEnable(args, from: extensionId, replyHandler: replyHandler)
        case "disable":
            handleActionDisable(args, from: extensionId, replyHandler: replyHandler)
        case "isEnabled":
            handleActionIsEnabled(args, from: extensionId, replyHandler: replyHandler)
        default:
            print("❌ [ExtensionManager+Action] Unknown method: \(method)")
            replyHandler(["error": "Unknown method: \(method)"])
        }
    }
    
    /// Send response back to the extension
    private func sendActionResponse(messageId: String, response: Any?, to webView: WKWebView?) {
        guard let webView = webView else {
            print("❌ [ExtensionManager+Action] WebView not available for response")
            return
        }
        
        let responseData: [String: Any] = [
            "messageId": messageId,
            "response": response ?? NSNull()
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: responseData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let script = "window.__nookActionResponse && window.__nookActionResponse(\(jsonString));"
            
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("❌ [ExtensionManager+Action] Failed to send response: \(error)")
                }
            }
        } catch {
            print("❌ [ExtensionManager+Action] Failed to serialize response: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Parse hex color string to RGBA array
    private func parseHexColor(_ hex: String) -> [CGFloat] {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        return [r, g, b, 1.0]
    }
    
    // MARK: - JavaScript Injection
    
    /// Inject chrome.action API into extension contexts
    func injectActionAPI(into webView: WKWebView, for extensionId: String) {
        let script = generateActionAPIScript(extensionId: extensionId)
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Action] Error injecting action API: \(error)")
            } else {
                print("✅ [ExtensionManager+Action] Action API injected successfully for \(extensionId)")
            }
        }
    }
    
    private func generateActionAPIScript(extensionId: String) -> String {
        return """
        (function() {
            'use strict';
            
            console.log('🎯 [Action API] Initializing chrome.action for extension: \(extensionId)');
            
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }
            
            if (!chrome.action) {
                // Message ID counter for tracking responses
                let messageIdCounter = 0;
                const pendingCallbacks = new Map();
                
                // Response handler
                window.__nookActionResponse = function(data) {
                    const { messageId, response } = data;
                    const callback = pendingCallbacks.get(messageId);
                    if (callback) {
                        callback(response);
                        pendingCallbacks.delete(messageId);
                    }
                };
                
                // Helper to send message to native code
                function sendActionMessage(method, args = {}, callback) {
                    const messageId = `action_${++messageIdCounter}_${Date.now()}`;
                    
                    if (callback) {
                        pendingCallbacks.set(messageId, callback);
                        
                        // Timeout after 5 seconds
                        setTimeout(() => {
                            if (pendingCallbacks.has(messageId)) {
                                console.warn(`[Action API] Timeout for ${method}`);
                                pendingCallbacks.delete(messageId);
                            }
                        }, 5000);
                    }
                    
                    const message = {
                        extensionId: '\(extensionId)',
                        method: method,
                        args: args,
                        messageId: messageId
                    };
                    
                    try {
                        window.webkit.messageHandlers.chromeAction.postMessage(message);
                    } catch (error) {
                        console.error('[Action API] Failed to send message:', error);
                        if (callback) {
                            callback({ error: error.message });
                            pendingCallbacks.delete(messageId);
                        }
                    }
                    
                    // Return promise for async/await support
                    return new Promise((resolve, reject) => {
                        if (!callback) {
                            pendingCallbacks.set(messageId, (response) => {
                                if (response && response.error) {
                                    reject(new Error(response.error));
                                } else {
                                    resolve(response);
                                }
                            });
                        }
                    });
                }
                
                chrome.action = {
                    // Badge text
                    setBadgeText: function(details, callback) {
                        sendActionMessage('setBadgeText', { text: details.text }, callback);
                    },
                    
                    getBadgeText: function(details, callback) {
                        return sendActionMessage('getBadgeText', details || {}, callback);
                    },
                    
                    // Badge background color
                    setBadgeBackgroundColor: function(details, callback) {
                        sendActionMessage('setBadgeBackgroundColor', { color: details.color }, callback);
                    },
                    
                    getBadgeBackgroundColor: function(details, callback) {
                        return sendActionMessage('getBadgeBackgroundColor', details || {}, callback);
                    },
                    
                    // Badge text color (Chrome 110+)
                    setBadgeTextColor: function(details, callback) {
                        sendActionMessage('setBadgeTextColor', { color: details.color }, callback);
                    },
                    
                    getBadgeTextColor: function(details, callback) {
                        return sendActionMessage('getBadgeTextColor', details || {}, callback);
                    },
                    
                    // Title (tooltip)
                    setTitle: function(details, callback) {
                        sendActionMessage('setTitle', { title: details.title }, callback);
                    },
                    
                    getTitle: function(details, callback) {
                        return sendActionMessage('getTitle', details || {}, callback);
                    },
                    
                    // Popup
                    setPopup: function(details, callback) {
                        sendActionMessage('setPopup', { popup: details.popup }, callback);
                    },
                    
                    getPopup: function(details, callback) {
                        return sendActionMessage('getPopup', details || {}, callback);
                    },
                    
                    // Icon
                    setIcon: function(details, callback) {
                        sendActionMessage('setIcon', details, callback);
                    },
                    
                    // Enable/disable
                    enable: function(tabId, callback) {
                        sendActionMessage('enable', { tabId: tabId }, callback);
                    },
                    
                    disable: function(tabId, callback) {
                        sendActionMessage('disable', { tabId: tabId }, callback);
                    },
                    
                    isEnabled: function(details, callback) {
                        return sendActionMessage('isEnabled', details || {}, callback);
                    },
                    
                    // Event listeners (stub for now, will implement in Phase 2)
                    onClicked: {
                        addListener: function(callback) {
                            console.log('[Action API] onClicked.addListener - stub');
                        },
                        removeListener: function(callback) {
                            console.log('[Action API] onClicked.removeListener - stub');
                        }
                    }
                };
                
                console.log('✅ [Action API] chrome.action initialized');
                console.log('   📛 Badge methods: setBadgeText, getBadgeText, setBadgeBackgroundColor, setBadgeTextColor');
                console.log('   📝 Title methods: setTitle, getTitle');
                console.log('   🪟 Popup methods: setPopup, getPopup');
                console.log('   🖼️ Icon methods: setIcon');
                console.log('   ✅ State methods: enable, disable, isEnabled');
            }
        })();
        """
    }
}
