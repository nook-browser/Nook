//
//  ExtensionManager+Storage.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  Storage API message handlers and JavaScript bridge
//

import Foundation
import WebKit
import os.log

@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - JavaScript Bridge Injection
    
    /// Get JavaScript code to inject chrome.storage API
    func getStorageAPIBridge() -> String {
        return """
        // Chrome Storage API Bridge
        (function() {
            if (window.chrome && window.chrome.storage) {
                console.log('✅ [Storage] API already injected');
                return;
            }
            
            // Create chrome.storage namespace
            if (!window.chrome) window.chrome = {};
            
            window.chrome.storage = {
                local: {
                    get: function(keys, callback) {
                        return new Promise((resolve, reject) => {
                            const normalizedKeys = keys === null || keys === undefined ? null :
                                                  Array.isArray(keys) ? keys :
                                                  typeof keys === 'object' ? Object.keys(keys) :
                                                  [keys];
                            
                            window.webkit.messageHandlers.extensionStorage.postMessage({
                                method: 'get',
                                area: 'local',
                                keys: normalizedKeys
                            }).then(result => {
                                console.log('✅ [Storage] get() succeeded:', Object.keys(result || {}).length, 'keys');
                                if (callback) callback(result);
                                resolve(result);
                            }).catch(error => {
                                console.error('❌ [Storage] get() failed:', error);
                                reject(error);
                            });
                        });
                    },
                    
                    set: function(items, callback) {
                        return new Promise((resolve, reject) => {
                            window.webkit.messageHandlers.extensionStorage.postMessage({
                                method: 'set',
                                area: 'local',
                                items: items
                            }).then(() => {
                                console.log('✅ [Storage] set() succeeded:', Object.keys(items).length, 'keys');
                                if (callback) callback();
                                resolve();
                            }).catch(error => {
                                console.error('❌ [Storage] set() failed:', error);
                                reject(error);
                            });
                        });
                    },
                    
                    remove: function(keys, callback) {
                        return new Promise((resolve, reject) => {
                            const keyArray = Array.isArray(keys) ? keys : [keys];
                            
                            window.webkit.messageHandlers.extensionStorage.postMessage({
                                method: 'remove',
                                area: 'local',
                                keys: keyArray
                            }).then(() => {
                                console.log('✅ [Storage] remove() succeeded:', keyArray.length, 'keys');
                                if (callback) callback();
                                resolve();
                            }).catch(error => {
                                console.error('❌ [Storage] remove() failed:', error);
                                reject(error);
                            });
                        });
                    },
                    
                    clear: function(callback) {
                        return new Promise((resolve, reject) => {
                            window.webkit.messageHandlers.extensionStorage.postMessage({
                                method: 'clear',
                                area: 'local'
                            }).then(() => {
                                console.log('✅ [Storage] clear() succeeded');
                                if (callback) callback();
                                resolve();
                            }).catch(error => {
                                console.error('❌ [Storage] clear() failed:', error);
                                reject(error);
                            });
                        });
                    },
                    
                    getBytesInUse: function(keys, callback) {
                        return new Promise((resolve, reject) => {
                            const normalizedKeys = keys === null || keys === undefined ? null :
                                                  Array.isArray(keys) ? keys : [keys];
                            
                            window.webkit.messageHandlers.extensionStorage.postMessage({
                                method: 'getBytesInUse',
                                area: 'local',
                                keys: normalizedKeys
                            }).then(bytes => {
                                console.log('✅ [Storage] getBytesInUse():', bytes, 'bytes');
                                if (callback) callback(bytes);
                                resolve(bytes);
                            }).catch(error => {
                                console.error('❌ [Storage] getBytesInUse() failed:', error);
                                reject(error);
                            });
                        });
                    },
                    
                    // Storage change listeners
                    onChanged: {
                        _listeners: [],
                        addListener: function(callback) {
                            this._listeners.push(callback);
                            console.log('✅ [Storage] onChanged listener added, total:', this._listeners.length);
                        },
                        removeListener: function(callback) {
                            const index = this._listeners.indexOf(callback);
                            if (index > -1) {
                                this._listeners.splice(index, 1);
                                console.log('✅ [Storage] onChanged listener removed, remaining:', this._listeners.length);
                            }
                        },
                        hasListener: function(callback) {
                            return this._listeners.includes(callback);
                        },
                        _fire: function(changes, areaName) {
                            console.log('🔥 [Storage] Firing onChanged:', Object.keys(changes).length, 'changes in', areaName);
                            this._listeners.forEach(callback => {
                                try {
                                    callback(changes, areaName);
                                } catch (error) {
                                    console.error('❌ [Storage] onChanged listener error:', error);
                                }
                            });
                        }
                    },
                    
                    QUOTA_BYTES: 10485760 // 10MB
                },
                
                // Alias for compatibility
                onChanged: null // Will be set below
            };
            
            // Make onChanged available at chrome.storage.onChanged too
            window.chrome.storage.onChanged = window.chrome.storage.local.onChanged;
            
            console.log('✅ [Storage] API bridge injected successfully');
        })();
        """
    }
    
    // MARK: - Message Handlers
    
    /// Handle storage API messages from JavaScript
    func handleStorageMessage(_ message: WKScriptMessage, body: [String: Any]) async {
        guard let method = body["method"] as? String else {
            sendErrorResponse(to: message, error: "Missing method")
            return
        }
        
        // Get extension ID from the message's webView/context
        guard let extensionId = getExtensionId(for: message) else {
            sendErrorResponse(to: message, error: "Unable to determine extension ID")
            return
        }
        
        let logger = Logger(subsystem: "com.nook.ExtensionManager", category: "Storage")
        logger.debug("📨 [Storage] Handling \(method) for extension \(extensionId)")
        
        do {
            switch method {
            case "get":
                let keys = body["keys"] as? [String]
                let result = await storageManager.get(for: extensionId, keys: keys)
                sendSuccessResponse(to: message, result: result)
                
            case "set":
                guard let items = body["items"] as? [String: Any] else {
                    sendErrorResponse(to: message, error: "Missing items")
                    return
                }
                try await storageManager.set(for: extensionId, items: items)
                sendSuccessResponse(to: message, result: nil)
                
            case "remove":
                guard let keys = body["keys"] as? [String] else {
                    sendErrorResponse(to: message, error: "Missing keys")
                    return
                }
                try await storageManager.remove(for: extensionId, keys: keys)
                sendSuccessResponse(to: message, result: nil)
                
            case "clear":
                try await storageManager.clear(for: extensionId)
                sendSuccessResponse(to: message, result: nil)
                
            case "getBytesInUse":
                let keys = body["keys"] as? [String]
                let bytes = await storageManager.getBytesInUse(for: extensionId, keys: keys)
                sendSuccessResponse(to: message, result: bytes)
                
            default:
                sendErrorResponse(to: message, error: "Unknown method: \(method)")
            }
        } catch {
            logger.error("❌ [Storage] Error handling \(method): \(error.localizedDescription)")
            sendErrorResponse(to: message, error: error.localizedDescription)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get extension ID from a script message
    private func getExtensionId(for message: WKScriptMessage) -> String? {
        // Try to get from webView's URL
        if let webView = message.webView,
           let url = webView.url,
           url.scheme == "webkit-extension" {
            return url.host
        }
        
        // Fallback: try to find the context that owns this webView
        for (id, context) in extensionContexts {
            // This is a simplified check - you may need more robust logic
            if message.frameInfo.securityOrigin.protocol == "webkit-extension" {
                return id
            }
        }
        
        return nil
    }
    
    /// Send success response to JavaScript
    private func sendSuccessResponse(to message: WKScriptMessage, result: Any?) {
        guard let webView = message.webView else { return }
        
        Task { @MainActor in
            if let result = result {
                let jsonData = try? JSONSerialization.data(withJSONObject: result, options: [])
                let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
                webView.evaluateJavaScript("Promise.resolve(\(jsonString))")
            } else {
                webView.evaluateJavaScript("Promise.resolve()")
            }
        }
    }
    
    /// Send error response to JavaScript
    private func sendErrorResponse(to message: WKScriptMessage, error: String) {
        guard let webView = message.webView else { return }
        
        Task { @MainActor in
            let escapedError = error.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("Promise.reject(new Error('\(escapedError)'))")
        }
    }
    
    // MARK: - Change Notifications
    
    /// Setup observer for storage change notifications
    func setupStorageChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ExtensionStorageChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let extensionId = notification.userInfo?["extensionId"] as? String,
                  let changes = notification.userInfo?["changes"] as? [String: ExtensionStorageManager.StorageChange],
                  let area = notification.userInfo?["area"] as? String else {
                return
            }
            
            Task {
                await self.fireStorageChangedEvent(extensionId: extensionId, changes: changes, area: area)
            }
        }
    }
    
    /// Fire storage changed event in extension contexts
    private func fireStorageChangedEvent(
        extensionId: String,
        changes: [String: ExtensionStorageManager.StorageChange],
        area: String
    ) async {
        guard let context = extensionContexts[extensionId] else { return }
        
        // Convert changes to JSON
        let changesDict = changes.mapValues { change -> [String: Any?] in
            return [
                "oldValue": change.oldValue?.value,
                "newValue": change.newValue?.value
            ]
        }
        
        guard let changesData = try? JSONSerialization.data(withJSONObject: changesDict, options: []),
              let changesJSON = String(data: changesData, encoding: .utf8) else {
            return
        }
        
        let script = """
        if (chrome.storage && chrome.storage.onChanged) {
            chrome.storage.onChanged._fire(\(changesJSON), '\(area)');
        }
        """
        
        // Execute in background context if available
        if let backgroundWebView = getBackgroundWebView(for: context) {
            await MainActor.run {
                backgroundWebView.evaluateJavaScript(script)
            }
        }
        
        // Also fire in all popup/options webviews for this extension
        // (Implementation depends on how you track these webviews)
    }
    
    /// Get background webview for an extension context
    private func getBackgroundWebView(for context: WKWebExtensionContext) -> WKWebView? {
        // This is a placeholder - implement based on your architecture
        // You may need to track background webviews separately
        return nil
    }
}

