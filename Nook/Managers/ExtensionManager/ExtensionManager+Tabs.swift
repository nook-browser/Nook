//
//  ExtensionManager+Tabs.swift
//  Nook
//
//  Chrome Tabs API Bridge for WKWebExtension support
//  Implements chrome.tabs.* APIs for web extension compatibility
//

import Foundation
import WebKit
import AppKit

// MARK: - Chrome Tabs API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Tabs Query Implementation

    /// Handles chrome.tabs.query calls from extension contexts
    func handleTabsQuery(queryInfo: [String: Any], from context: WKWebExtensionContext, completionHandler: @escaping ([[String: Any]]?, Error?) -> Void) {
        print("[ExtensionManager+Tabs] handleTabsQuery: \(queryInfo)")

        guard let browserManager = browserManagerAccess else {
            completionHandler([], NSError(domain: "ExtensionManager+Tabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        var matchingTabs: [[String: Any]] = []

        // Get all tabs from browser manager
        let allTabs = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs

        for tab in allTabs {
            if let tabInfo = createTabInfo(from: tab, matches: queryInfo) {
                matchingTabs.append(tabInfo)
            }
        }

        print("[ExtensionManager+Tabs] Found \(matchingTabs.count) matching tabs")
        completionHandler(matchingTabs, nil)
    }

    // MARK: - Tab Creation

    /// Handles chrome.tabs.create calls from extension contexts
    func handleTabsCreate(createProperties: [String: Any], from context: WKWebExtensionContext, completionHandler: @escaping ([String: Any]?, Error?) -> Void) {
        print("[ExtensionManager+Tabs] handleTabsCreate: \(createProperties)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        // Extract creation properties
        let url = createProperties["url"] as? String
        let active = createProperties["active"] as? Bool ?? true

        Task { @MainActor in
            do {
                let newTab = browserManager.tabManager.createNewTab(
                    url: url ?? "about:blank",
                    in: browserManager.tabManager.currentSpace
                )

                if active {
                    browserManager.tabManager.setActiveTab(newTab)
                }

                let tabInfo = createTabInfo(from: newTab, matches: [:])
                completionHandler(tabInfo, nil)

            } catch {
                completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create tab: \(error.localizedDescription)"]))
            }
        }
    }

    // MARK: - Tab Update

    /// Handles chrome.tabs.update calls from extension contexts
    func handleTabsUpdate(tabId: String?, updateProperties: [String: Any], from context: WKWebExtensionContext, completionHandler: @escaping ([String: Any]?, Error?) -> Void) {
        print("[ExtensionManager+Tabs] handleTabsUpdate: tabId=\(tabId ?? "current"), properties=\(updateProperties)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        let targetTab: Tab?

        if let tabId = tabId, let uuid = UUID(uuidString: tabId) {
            targetTab = browserManager.tabManager.tabs.first { $0.id == uuid }
        } else {
            targetTab = browserManager.currentTabForActiveWindow()
        }

        guard let tab = targetTab else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tab not found"]))
            return
        }

        Task { @MainActor in
            // Apply update properties
            if let url = updateProperties["url"] as? String {
                if let urlObj = URL(string: url) {
                    tab.webView?.load(URLRequest(url: urlObj))
                }
            }

            if let active = updateProperties["active"] as? Bool, active {
                browserManager.tabManager.setActiveTab(tab)
            }

            if updateProperties["muted"] != nil {
                // Note: WebKit doesn't directly support muting tabs
                print("[ExtensionManager+Tabs] Muted state not supported in WebKit")
            }

            // Wait a moment for updates to take effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let tabInfo = self.createTabInfo(from: tab, matches: [:])
                completionHandler(tabInfo, nil)
            }
        }
    }

    // MARK: - Tab Removal

    /// Handles chrome.tabs.remove calls from extension contexts
    func handleTabsRemove(tabIds: [String], from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Tabs] handleTabsRemove: \(tabIds)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(NSError(domain: "ExtensionManager+Tabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        Task { @MainActor in
            for tabId in tabIds {
                if let uuid = UUID(uuidString: tabId) {
                    browserManager.tabManager.removeTab(uuid)
                }
            }
            completionHandler(nil)
        }
    }

    // MARK: - Tab Message Sending

    /// Handles chrome.tabs.sendMessage calls from extension contexts
    func handleTabsSendMessage(tabId: String, message: [String: Any], options: [String: Any]?, from context: WKWebExtensionContext, completionHandler: @escaping (Any?, Error?) -> Void) {
        print("[ExtensionManager+Tabs] handleTabsSendMessage: tabId=\(tabId)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        guard let uuid = UUID(uuidString: tabId),
              let tab = browserManager.tabManager.tabs.first(where: { $0.id == uuid }) else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tab not found"]))
            return
        }

        guard let webView = tab.webView else {
            completionHandler(nil, NSError(domain: "ExtensionManager+Tabs", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
            return
        }

        // Inject the message into the tab's content script context
        let messageScript = """
        (function() {
            if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.onMessage) {
                const message = \(try! JSONSerialization.data(withJSONObject: message).base64EncodedString());
                const decodedMessage = JSON.parse(atob(message));

                const sender = {
                    id: '\(getExtensionId(for: context) ?? "unknown")',
                    url: '\(webView.url?.absoluteString ?? "")',
                    tab: {
                        id: '\(tabId)',
                        url: '\(webView.url?.absoluteString ?? "")',
                        title: '\(tab.name.replacingOccurrences(of: "'", with: "\\'"))'
                    }
                };

                const sendResponse = function(response) {
                    // Send response back via webkit message handler
                    window.webkit.messageHandlers.chromeTabsResponse.postMessage({
                        type: 'response',
                        messageId: '\(UUID().uuidString)',
                        data: response
                    });
                };

                chrome.runtime.onMessage.dispatch(decodedMessage, sender, sendResponse);
            }
        })();
        """

        // Store the completion handler for async response
        let messageId = UUID().uuidString
        pendingTabMessageResponses[messageId] = completionHandler

        webView.evaluateJavaScript(messageScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Tabs] Error sending message to tab: \(error)")
                completionHandler(nil, error)
            }
        }
    }

    // MARK: - Tab Information Creation

    private func createTabInfo(from tab: Tab, matches queryInfo: [String: Any]) -> [String: Any]? {
        // Check if tab matches query criteria
        if !tabMatchesQuery(tab: tab, query: queryInfo) {
            return nil
        }

        var tabInfo: [String: Any] = [
            "id": tab.id.uuidString,
            "index": tab.index,
            "windowId": 1, // Simplified window ID
            "active": browserManagerAccess?.currentTabForActiveWindow()?.id == tab.id,
            "pinned": browserManagerAccess?.tabManager.pinnedTabs.contains(where: { $0.id == tab.id }) ?? false,
            "title": tab.name,
            "url": tab.url.absoluteString
        ]

        // Add additional properties if available
        if let webView = tab.webView {
            tabInfo["status"] = !tab.isLoading ? "complete" : "loading"
            tabInfo["width"] = webView.bounds.width
            tabInfo["height"] = webView.bounds.height
        }

        // Add audible status (simplified - WebKit doesn't expose this directly)
        tabInfo["audible"] = false

        // Add muted status
        tabInfo["mutedInfo"] = ["muted": false]

        return tabInfo
    }

    private func tabMatchesQuery(tab: Tab, query: [String: Any]) -> Bool {
        // Check active tab condition
        if let active = query["active"] as? Bool {
            let isActive = browserManagerAccess?.currentTabForActiveWindow()?.id == tab.id
            if active != isActive {
                return false
            }
        }

        // Check pinned condition
        if let pinned = query["pinned"] as? Bool {
            let isPinned = browserManagerAccess?.tabManager.pinnedTabs.contains(where: { $0.id == tab.id }) ?? false
            if pinned != isPinned {
                return false
            }
        }

        // Check URL pattern matching
        if let urlPattern = query["url"] as? String {
            let tabUrl = tab.url.absoluteString
            // Simple pattern matching - could be enhanced with proper URL pattern matching
            if !tabUrl.contains(urlPattern) {
                return false
            }
        }

        // Check title matching
        if let titlePattern = query["title"] as? String {
            if !tab.name.contains(titlePattern) {
                return false
            }
        }

        return true
    }

    // MARK: - Message Response System

    /// Handles response from tab message
    func handleTabMessageResponse(messageId: String, response: Any?) {
        if let completionHandler = pendingTabMessageResponses[messageId] {
            completionHandler(response, nil)
            pendingTabMessageResponses.removeValue(forKey: messageId)
        }
    }

    // MARK: - JavaScript API Injection

    /// Injects the Chrome Tabs API bridge into a web view
    func injectTabsAPIIntoWebView(_ webView: WKWebView, extensionId: String) {
        let tabsScript = generateTabsAPIScript(extensionId: extensionId)

        webView.evaluateJavaScript(tabsScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Tabs] Error injecting tabs API: \(error)")
            } else {
                print("[ExtensionManager+Tabs] Tabs API injected successfully")
            }
        }
    }

    private func generateTabsAPIScript(extensionId: String) -> String {
        return """
        (function() {
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }

            if (!chrome.tabs) {
                chrome.tabs = {
                    query: function(queryInfo, callback) {
                        const messageData = {
                            type: 'query',
                            queryInfo: queryInfo,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            // Store callback for response handling
                            const messageId = Date.now().toString();
                            window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                            window.chromeTabsCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                    },
                    create: function(createProperties, callback) {
                        const messageData = {
                            type: 'create',
                            createProperties: createProperties,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                            window.chromeTabsCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                    },
                    update: function(tabId, updateProperties, callback) {
                        const messageData = {
                            type: 'update',
                            tabId: tabId,
                            updateProperties: updateProperties,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                            window.chromeTabsCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                    },
                    remove: function(tabIds, callback) {
                        const messageData = {
                            type: 'remove',
                            tabIds: Array.isArray(tabIds) ? tabIds : [tabIds],
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                            window.chromeTabsCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                    },
                    sendMessage: function(tabId, message, options, callback) {
                        // Handle overloaded parameters
                        if (typeof options === 'function') {
                            callback = options;
                            options = {};
                        }

                        const messageData = {
                            type: 'sendMessage',
                            tabId: tabId,
                            message: message,
                            options: options || {},
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeTabsCallbacks = window.chromeTabsCallbacks || {};
                            window.chromeTabsCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeTabs.postMessage(messageData);
                    }
                };

                // Add response handler for tab messages
                if (!window.chromeTabsResponseHandler) {
                    window.chromeTabsResponseHandler = function(event) {
                        const message = event.message;
                        if (message.type === 'response' && window.chromeTabsCallbacks && window.chromeTabsCallbacks[message.messageId]) {
                            window.chromeTabsCallbacks[message.messageId](message.data);
                            delete window.chromeTabsCallbacks[message.messageId];
                        }
                    };

                    // Register response handler
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeTabsResponse) {
                        window.webkit.messageHandlers.chromeTabsResponse.postMessage({type: 'register'});
                    }
                }

                console.log('[Chrome Tabs API] Tabs API initialized');
            }
        })();
        """
    }
}

// MARK: - WKScriptMessageHandler for Tabs
@available(macOS 15.4, *)
extension ExtensionManager {

    func handleTabsScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "chromeTabs",
              let messageBody = message.body as? [String: Any],
              let messageType = messageBody["type"] as? String else { return }

        print("[ExtensionManager+Tabs] Received tabs script message: \(messageType)")

        let timestamp = messageBody["timestamp"] as? String ?? ""

        switch messageType {
        case "query":
            let queryInfo = messageBody["queryInfo"] as? [String: Any] ?? [:]
            handleTabsQuery(queryInfo: queryInfo, from: extensionContextsAccess.values.first!) { tabs, error in
                self.sendTabsResponse(timestamp: timestamp, data: tabs, error: error)
            }

        case "create":
            let createProperties = messageBody["createProperties"] as? [String: Any] ?? [:]
            handleTabsCreate(createProperties: createProperties, from: extensionContextsAccess.values.first!) { tab, error in
                self.sendTabsResponse(timestamp: timestamp, data: tab, error: error)
            }

        case "update":
            let tabId = messageBody["tabId"] as? String
            let updateProperties = messageBody["updateProperties"] as? [String: Any] ?? [:]
            handleTabsUpdate(tabId: tabId, updateProperties: updateProperties, from: extensionContextsAccess.values.first!) { tab, error in
                self.sendTabsResponse(timestamp: timestamp, data: tab, error: error)
            }

        case "remove":
            let tabIds = messageBody["tabIds"] as? [String] ?? []
            handleTabsRemove(tabIds: tabIds, from: extensionContextsAccess.values.first!) { error in
                self.sendTabsResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "sendMessage":
            let tabId = messageBody["tabId"] as? String ?? ""
            let message = messageBody["message"] as? [String: Any] ?? [:]
            let options = messageBody["options"] as? [String: Any]
            handleTabsSendMessage(tabId: tabId, message: message, options: options, from: extensionContextsAccess.values.first!) { response, error in
                self.sendTabsResponse(timestamp: timestamp, data: response, error: error)
            }

        default:
            print("[ExtensionManager+Tabs] Unknown tabs message type: \(messageType)")
        }
    }

    private func sendTabsResponse(timestamp: String, data: Any?, error: Error?) {
        // Find the extension context that has active Chrome API callbacks
        guard let extensionContext = findExtensionContextWithTabsCallbacks(timestamp: timestamp) else {
            print("[ExtensionManager+Tabs] No extension context found for timestamp \(timestamp)")
            return
        }

        // Get the web view associated with this extension context
        guard let webView = getWebViewForExtensionContext(extensionContext) else {
            print("[ExtensionManager+Tabs] No web view found for extension context")
            return
        }

        let responseScript: String
        if let error = error {
            responseScript = """
            if (window.chromeTabsCallbacks && window.chromeTabsCallbacks['\(timestamp)']) {
                window.chromeTabsCallbacks['\(timestamp)'](null, { message: '\(error.localizedDescription.replacingOccurrences(of: "'", with: "\\'"))' });
                delete window.chromeTabsCallbacks['\(timestamp)'];
            }
            """
        } else {
            let dataString: String
            if let data = data {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                    let base64String = jsonData.base64EncodedString()
                    dataString = "JSON.parse(atob('\(base64String)'))"
                } else {
                    dataString = "null"
                }
            } else {
                dataString = "null"
            }
            responseScript = """
            if (window.chromeTabsCallbacks && window.chromeTabsCallbacks['\(timestamp)']) {
                window.chromeTabsCallbacks['\(timestamp)'](\(dataString));
                delete window.chromeTabsCallbacks['\(timestamp)'];
            }
            """
        }

        // Inject the response script into the web view
        webView.evaluateJavaScript(responseScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Tabs] Error injecting response script: \(error)")
            } else {
                print("[ExtensionManager+Tabs] Response injected successfully for timestamp \(timestamp)")
            }
        }
    }

    /// Find the extension context that has active Chrome API callbacks for the given timestamp
    private func findExtensionContextWithTabsCallbacks(timestamp: String) -> WKWebExtensionContext? {
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