//
//  ExtensionManager+Storage.swift
//  Nook
//
//  Chrome Storage API Bridge for WKWebExtension support
//  Implements chrome.storage.* APIs for web extension compatibility
//

import Foundation
import WebKit

// MARK: - Chrome Storage API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Storage Local Implementation

    /// Handles chrome.storage.local.get calls from extension contexts
    func handleStorageLocalGet(keys: Any, from context: WKWebExtensionContext, completionHandler: @escaping ([String: Any]?, Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageLocalGet: \(keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any]?, Error>) in
                    storageManager.getLocal(keys: keys as? [String]) { result, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: result)
                        }
                    }
                }
                completionHandler(result, nil)
            } catch {
                print("[ExtensionManager+Storage] Error getting storage values: \(error)")
                completionHandler(nil, error)
            }
        }
    }

    /// Handles chrome.storage.local.set calls from extension contexts
    func handleStorageLocalSet(items: [String: Any], from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageLocalSet: \(items.keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.setLocal(items: items) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error setting storage values: \(error)")
                completionHandler(error)
            }
        }
    }

    /// Handles chrome.storage.local.remove calls from extension contexts
    func handleStorageLocalRemove(keys: [String], from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageLocalRemove: \(keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.removeLocal(keys: keys) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error removing storage values: \(error)")
                completionHandler(error)
            }
        }
    }

    /// Handles chrome.storage.local.clear calls from extension contexts
    func handleStorageLocalClear(from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageLocalClear")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.clearLocal { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error clearing storage values: \(error)")
                completionHandler(error)
            }
        }
    }

    // MARK: - Storage Session Implementation

    /// Handles chrome.storage.session.get calls from extension contexts
    func handleStorageSessionGet(keys: Any, from context: WKWebExtensionContext, completionHandler: @escaping ([String: Any]?, Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageSessionGet: \(keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any]?, Error>) in
                    storageManager.getSession(keys: keys as? [String]) { result, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: result)
                        }
                    }
                }
                completionHandler(result, nil)
            } catch {
                print("[ExtensionManager+Storage] Error getting session values: \(error)")
                completionHandler(nil, error)
            }
        }
    }

    /// Handles chrome.storage.session.set calls from extension contexts
    func handleStorageSessionSet(items: [String: Any], from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageSessionSet: \(items.keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.setSession(items: items) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error setting session values: \(error)")
                completionHandler(error)
            }
        }
    }

    /// Handles chrome.storage.session.remove calls from extension contexts
    func handleStorageSessionRemove(keys: [String], from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageSessionRemove: \(keys)")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.removeSession(keys: keys) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error removing session values: \(error)")
                completionHandler(error)
            }
        }
    }

    /// Handles chrome.storage.session.clear calls from extension contexts
    func handleStorageSessionClear(from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageSessionClear")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    storageManager.clearSession { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                completionHandler(nil)
            } catch {
                print("[ExtensionManager+Storage] Error clearing session values: \(error)")
                completionHandler(error)
            }
        }
    }

    // MARK: - Storage Quota Management

    /// Handles chrome.storage.local.getBytesInUse calls from extension contexts
    func handleStorageLocalGetBytesInUse(keys: Any?, from context: WKWebExtensionContext, completionHandler: @escaping (Int, Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageLocalGetBytesInUse")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                let bytesInUse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                    storageManager.getBytesInUseLocal(keys: keys as? [String]) { bytesInUse, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: bytesInUse)
                        }
                    }
                }
                completionHandler(bytesInUse, nil)
            } catch {
                print("[ExtensionManager+Storage] Error getting bytes in use: \(error)")
                completionHandler(0, error)
            }
        }
    }

    /// Handles chrome.storage.session.getBytesInUse calls from extension contexts
    func handleStorageSessionGetBytesInUse(keys: Any?, from context: WKWebExtensionContext, completionHandler: @escaping (Int, Error?) -> Void) {
        print("[ExtensionManager+Storage] handleStorageSessionGetBytesInUse")

        let storageManager = ExtensionStorageManager.shared
        let extensionId = getExtensionId(for: context) ?? "unknown"

        Task {
            do {
                let bytesInUse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                    storageManager.getBytesInUseSession(keys: keys as? [String]) { bytesInUse, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: bytesInUse)
                        }
                    }
                }
                completionHandler(bytesInUse, nil)
            } catch {
                print("[ExtensionManager+Storage] Error getting session bytes in use: \(error)")
                completionHandler(0, error)
            }
        }
    }

    // MARK: - Storage Change Events

    /// Broadcasts storage change events to all extension contexts
    func broadcastStorageChange(changes: [String: [String: Any]], areaName: String, from context: WKWebExtensionContext) {
        print("[ExtensionManager+Storage] Broadcasting storage changes: \(changes.keys)")

        let changeEvent: [String: Any] = [
            "changes": changes,
            "areaName": areaName
        ]

        Task { @MainActor in
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: changeEvent)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                let script = """
                (function() {
                    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.onChanged) {
                        const changes = \(jsonString);
                        try {
                            chrome.storage.onChanged.dispatch(changes.changes, changes.areaName);
                        } catch (error) {
                            console.error('Error dispatching storage change:', error);
                        }
                    }
                })();
                """

                // Note: WKWebExtensionContext doesn't directly expose web views
                // Storage change broadcasting would need different implementation

            } catch {
                print("[ExtensionManager+Storage] Error serializing storage changes: \(error)")
            }
        }
    }

    // MARK: - JavaScript API Injection

    /// Injects the Chrome Storage API bridge into a web view
    func injectStorageAPIIntoWebView(_ webView: WKWebView, extensionId: String) {
        let storageScript = generateStorageAPIScript(extensionId: extensionId)

        webView.evaluateJavaScript(storageScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Storage] Error injecting storage API: \(error)")
            } else {
                print("[ExtensionManager+Storage] Storage API injected successfully")
            }
        }
    }

    private func generateStorageAPIScript(extensionId: String) -> String {
        return """
        (function() {
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }

            if (!chrome.storage) {
                chrome.storage = {
                    local: {
                        get: function(keys, callback) {
                            const messageData = {
                                type: 'localGet',
                                keys: keys,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        set: function(items, callback) {
                            const messageData = {
                                type: 'localSet',
                                items: items,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        remove: function(keys, callback) {
                            const messageData = {
                                type: 'localRemove',
                                keys: Array.isArray(keys) ? keys : [keys],
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        clear: function(callback) {
                            const messageData = {
                                type: 'localClear',
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        getBytesInUse: function(keys, callback) {
                            const messageData = {
                                type: 'localGetBytesInUse',
                                keys: keys,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        }
                    },
                    session: {
                        get: function(keys, callback) {
                            const messageData = {
                                type: 'sessionGet',
                                keys: keys,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        set: function(items, callback) {
                            const messageData = {
                                type: 'sessionSet',
                                items: items,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        remove: function(keys, callback) {
                            const messageData = {
                                type: 'sessionRemove',
                                keys: Array.isArray(keys) ? keys : [keys],
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        clear: function(callback) {
                            const messageData = {
                                type: 'sessionClear',
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        },
                        getBytesInUse: function(keys, callback) {
                            const messageData = {
                                type: 'sessionGetBytesInUse',
                                keys: keys,
                                timestamp: Date.now()
                            };

                            if (callback) {
                                const messageId = Date.now().toString();
                                window.chromeStorageCallbacks = window.chromeStorageCallbacks || {};
                                window.chromeStorageCallbacks[messageId] = callback;
                            }

                            window.webkit.messageHandlers.chromeStorage.postMessage(messageData);
                        }
                    },
                    onChanged: new EventTarget()
                };

                // Add onChanged listener support
                chrome.storage.onChanged.addListener = function(listener) {
                    chrome.storage.onChanged.addEventListener('change', function(event) {
                        listener(event.detail.changes, event.detail.areaName);
                    });
                };

                console.log('[Chrome Storage API] Storage API initialized');
            }
        })();
        """
    }
}

// MARK: - WKScriptMessageHandler for Storage
@available(macOS 15.4, *)
extension ExtensionManager {

    func handleStorageScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "chromeStorage",
              let messageBody = message.body as? [String: Any],
              let messageType = messageBody["type"] as? String else { return }

        print("[ExtensionManager+Storage] Received storage script message: \(messageType)")

        let timestamp = messageBody["timestamp"] as? String ?? ""

        switch messageType {
        case "localGet":
            let keys = messageBody["keys"]
            handleStorageLocalGet(keys: keys ?? [:], from: extensionContextsAccess.values.first!) { result, error in
                self.sendStorageResponse(timestamp: timestamp, data: result, error: error)
            }

        case "localSet":
            let items = messageBody["items"] as? [String: Any] ?? [:]
            handleStorageLocalSet(items: items, from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "localRemove":
            let keys = messageBody["keys"] as? [String] ?? []
            handleStorageLocalRemove(keys: keys, from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "localClear":
            handleStorageLocalClear(from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "localGetBytesInUse":
            let keys = messageBody["keys"]
            handleStorageLocalGetBytesInUse(keys: keys, from: extensionContextsAccess.values.first!) { bytesInUse, error in
                self.sendStorageResponse(timestamp: timestamp, data: bytesInUse, error: error)
            }

        case "sessionGet":
            let keys = messageBody["keys"]
            handleStorageSessionGet(keys: keys ?? [:], from: extensionContextsAccess.values.first!) { result, error in
                self.sendStorageResponse(timestamp: timestamp, data: result, error: error)
            }

        case "sessionSet":
            let items = messageBody["items"] as? [String: Any] ?? [:]
            handleStorageSessionSet(items: items, from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "sessionRemove":
            let keys = messageBody["keys"] as? [String] ?? []
            handleStorageSessionRemove(keys: keys, from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "sessionClear":
            handleStorageSessionClear(from: extensionContextsAccess.values.first!) { error in
                self.sendStorageResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "sessionGetBytesInUse":
            let keys = messageBody["keys"]
            handleStorageSessionGetBytesInUse(keys: keys, from: extensionContextsAccess.values.first!) { bytesInUse, error in
                self.sendStorageResponse(timestamp: timestamp, data: bytesInUse, error: error)
            }

        default:
            print("[ExtensionManager+Storage] Unknown storage message type: \(messageType)")
        }
    }

    private func sendStorageResponse(timestamp: String, data: Any?, error: Error?) {
        // Find the extension context that has active Chrome API callbacks
        guard let extensionContext = findExtensionContextWithStorageCallbacks(timestamp: timestamp) else {
            print("[ExtensionManager+Storage] No extension context found for timestamp \(timestamp)")
            return
        }

        // Get the web view associated with this extension context
        guard let webView = getWebViewForExtensionContext(extensionContext) else {
            print("[ExtensionManager+Storage] No web view found for extension context")
            return
        }

        let responseScript: String
        if let error = error {
            responseScript = """
            if (window.chromeStorageCallbacks && window.chromeStorageCallbacks['\(timestamp)']) {
                window.chromeStorageCallbacks['\(timestamp)'](null, { message: '\(error.localizedDescription.replacingOccurrences(of: "'", with: "\\'"))' });
                delete window.chromeStorageCallbacks['\(timestamp)'];
            }
            """
        } else {
            let dataString: String
            if let data = data {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                    let base64String = jsonData.base64EncodedString()
                    dataString = "JSON.parse(atob('\(base64String)'))"
                } else {
                    dataString = "\(data)"
                }
            } else {
                dataString = "null"
            }
            responseScript = """
            if (window.chromeStorageCallbacks && window.chromeStorageCallbacks['\(timestamp)']) {
                window.chromeStorageCallbacks['\(timestamp)'](\(dataString));
                delete window.chromeStorageCallbacks['\(timestamp)'];
            }
            """
        }

        // Inject the response script into the web view
        webView.evaluateJavaScript(responseScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Storage] Error injecting response script: \(error)")
            } else {
                print("[ExtensionManager+Storage] Response injected successfully for timestamp \(timestamp)")
            }
        }
    }

    /// Find the extension context that has active Chrome API callbacks for the given timestamp
    private func findExtensionContextWithStorageCallbacks(timestamp: String) -> WKWebExtensionContext? {
        // Try to find the context by checking which one has the timestamp in its callbacks
        for (_, context) in extensionContextsAccess {
            // For now, return the first context (this could be enhanced to track which context made the request)
            return context
        }
        return nil
    }

    /// Get the web view associated with an extension context
    private func getWebViewForExtensionContext(_ context: WKWebExtensionContext) -> WKWebView? {
        // Try to find a web view that can execute JavaScript in this extension context
        // First check if there's a popup web view
        if let extensionId = getExtensionId(for: context) {
            // Look through browser manager's window states to find popups or other web views
            guard let browserManager = browserManagerAccess else { return nil }

            // Check if there are any popup windows for this extension
            for windowState in browserManager.windowStates.values {
                if let window = windowState.window,
                   let webView = window.contentView?.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
                    // Check if this web view belongs to the extension
                    if webView.url?.absoluteString.contains("webkit-extension://") == true {
                        return webView
                    }
                }
            }

            // Fall back to the current active tab's web view
            if let activeTab = browserManager.currentTabForActiveWindow() {
                return activeTab.webView
            }
        }

        return nil
    }
}