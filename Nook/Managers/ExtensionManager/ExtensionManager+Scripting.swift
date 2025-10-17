//
//  ExtensionManager+Scripting.swift
//  Nook
//
//  Chrome Scripting API Bridge for WKWebExtension support
//  Implements chrome.scripting.* APIs for web extension compatibility
//

import Foundation
import WebKit
import AppKit

// MARK: - Chrome Scripting API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Script Execution Implementation

    /// Handles chrome.scripting.executeScript calls from extension contexts
    func handleScriptingExecuteScript(injection: ScriptingInjection, from context: WKWebExtensionContext, completionHandler: @escaping ([ScriptingResult]?, Error?) -> Void) {
        print("[ExtensionManager+Scripting] handleScriptingExecuteScript: targetTabId=\(injection.targetTabId)")

        guard let browserManager = browserManagerAccess else {
            completionHandler([], NSError(domain: "ExtensionManager+Scripting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        // Find target tab
        let targetTab: Tab?
        if let tabId = injection.targetTabId, let uuid = UUID(uuidString: tabId) {
            targetTab = browserManager.tabManager.tabs.first { $0.id == uuid }
        } else if let tabId = injection.targetTabId, tabId == "active" {
            targetTab = browserManager.currentTabForActiveWindow()
        } else {
            targetTab = browserManager.currentTabForActiveWindow()
        }

        guard let tab = targetTab else {
            completionHandler([], NSError(domain: "ExtensionManager+Scripting", code: 2, userInfo: [NSLocalizedDescriptionKey: "Target tab not found"]))
            return
        }

        guard let webView = tab.webView else {
            completionHandler([], NSError(domain: "ExtensionManager+Scripting", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
            return
        }

        Task { @MainActor in
            do {
                var results: [ScriptingResult] = []

                // Handle function injection
                if let funcInjection = injection.function {
                    let result = try await executeFunctionInjection(funcInjection, in: webView, frameId: injection.frameId)
                    results.append(result)
                }

                // Handle code injection
                if let code = injection.code {
                    let result = try await executeCodeInjection(code, in: webView, frameId: injection.frameId)
                    results.append(result)
                }

                // Handle file injection
                if let file = injection.file {
                    let result = try await executeFileInjection(file, in: webView, frameId: injection.frameId, extensionContext: context)
                    results.append(result)
                }

                completionHandler(results, nil)

            } catch {
                print("[ExtensionManager+Scripting] Error executing script: \(error)")
                completionHandler([], NSError(domain: "ExtensionManager+Scripting", code: 4, userInfo: [NSLocalizedDescriptionKey: "Script execution failed: \(error.localizedDescription)"]))
            }
        }
    }

    // MARK: - CSS Injection Implementation

    /// Handles chrome.scripting.insertCSS calls from extension contexts
    func handleScriptingInsertCSS(injection: CSSInjection, from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Scripting] handleScriptingInsertCSS: targetTabId=\(injection.targetTabId)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        // Find target tab
        let targetTab: Tab?
        if let tabId = injection.targetTabId, let uuid = UUID(uuidString: tabId) {
            targetTab = browserManager.tabManager.tabs.first { $0.id == uuid }
        } else if let tabId = injection.targetTabId, tabId == "active" {
            targetTab = browserManager.currentTabForActiveWindow()
        } else {
            targetTab = browserManager.currentTabForActiveWindow()
        }

        guard let tab = targetTab else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 2, userInfo: [NSLocalizedDescriptionKey: "Target tab not found"]))
            return
        }

        guard let webView = tab.webView else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
            return
        }

        Task { @MainActor in
            do {
                if let css = injection.css {
                    try await insertCSSString(css, in: webView, frameId: injection.frameId)
                }

                if let file = injection.file {
                    try await insertCSSFile(file, in: webView, frameId: injection.frameId, extensionContext: context)
                }

                completionHandler(nil)

            } catch {
                print("[ExtensionManager+Scripting] Error inserting CSS: \(error)")
                completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 4, userInfo: [NSLocalizedDescriptionKey: "CSS insertion failed: \(error.localizedDescription)"]))
            }
        }
    }

    /// Handles chrome.scripting.removeCSS calls from extension contexts
    func handleScriptingRemoveCSS(injection: CSSInjection, from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("[ExtensionManager+Scripting] handleScriptingRemoveCSS: targetTabId=\(injection.targetTabId)")

        guard let browserManager = browserManagerAccess else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return
        }

        // Find target tab (same logic as insertCSS)
        let targetTab: Tab?
        if let tabId = injection.targetTabId, let uuid = UUID(uuidString: tabId) {
            targetTab = browserManager.tabManager.tabs.first { $0.id == uuid }
        } else if let tabId = injection.targetTabId, tabId == "active" {
            targetTab = browserManager.currentTabForActiveWindow()
        } else {
            targetTab = browserManager.currentTabForActiveWindow()
        }

        guard let tab = targetTab else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 2, userInfo: [NSLocalizedDescriptionKey: "Target tab not found"]))
            return
        }

        guard let webView = tab.webView else {
            completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
            return
        }

        Task { @MainActor in
            do {
                // For CSS removal, we need to track inserted styles
                // This is a simplified implementation that removes all extension-injected styles
                let removalScript = """
                (function() {
                    const extensionStyles = document.querySelectorAll('style[data-extension-injected="true"]');
                    extensionStyles.forEach(style => style.remove());
                })();
                """

                try await executeScriptInFrame(removalScript, in: webView, frameId: injection.frameId)
                completionHandler(nil)

            } catch {
                print("[ExtensionManager+Scripting] Error removing CSS: \(error)")
                completionHandler(NSError(domain: "ExtensionManager+Scripting", code: 4, userInfo: [NSLocalizedDescriptionKey: "CSS removal failed: \(error.localizedDescription)"]))
            }
        }
    }

    // MARK: - Private Script Execution Methods

    private func executeFunctionInjection(_ function: String, in webView: WKWebView, frameId: String?) async throws -> ScriptingResult {
        // Convert function string to executable JavaScript
        let script = """
        (function() {
            \(function)
        })();
        """

        let result = try await executeScriptInFrame(script, in: webView, frameId: frameId)
        return ScriptingResult(
            frameId: frameId,
            result: result,
            error: nil
        )
    }

    private func executeCodeInjection(_ code: String, in webView: WKWebView, frameId: String?) async throws -> ScriptingResult {
        let result = try await executeScriptInFrame(code, in: webView, frameId: frameId)
        return ScriptingResult(
            frameId: frameId,
            result: result,
            error: nil
        )
    }

    private func executeFileInjection(_ file: String, in webView: WKWebView, frameId: String?, extensionContext: WKWebExtensionContext) async throws -> ScriptingResult {
        // Load file content from extension resources
        let baseURL = extensionContext.baseURL
        guard let fileURL = URL(string: file, relativeTo: baseURL) else {
            throw ScriptingError.fileNotFound
        }

        do {
            let fileContent = try String(contentsOf: fileURL)
            let result = try await executeScriptInFrame(fileContent, in: webView, frameId: frameId)
            return ScriptingResult(
                frameId: frameId,
                result: result,
                error: nil
            )
        } catch {
            throw ScriptingError.fileLoadFailed
        }
    }

    private func insertCSSString(_ css: String, in webView: WKWebView, frameId: String?) async throws {
        let script = """
        (function() {
            const style = document.createElement('style');
            style.textContent = `\(css.replacingOccurrences(of: "`", with: "\\`"))`;
            style.setAttribute('data-extension-injected', 'true');
            style.setAttribute('data-timestamp', Date.now().toString());
            document.head.appendChild(style);
        })();
        """

        try await executeScriptInFrame(script, in: webView, frameId: frameId)
    }

    private func insertCSSFile(_ file: String, in webView: WKWebView, frameId: String?, extensionContext: WKWebExtensionContext) async throws {
        // Load CSS file content from extension resources
        let baseURL = extensionContext.baseURL
        guard let fileURL = URL(string: file, relativeTo: baseURL) else {
            throw ScriptingError.fileNotFound
        }

        do {
            let cssContent = try String(contentsOf: fileURL)
            try await insertCSSString(cssContent, in: webView, frameId: frameId)
        } catch {
            throw ScriptingError.fileLoadFailed
        }
    }

    private func executeScriptInFrame(_ script: String, in webView: WKWebView, frameId: String?) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            let finalScript: String
            if let frameId = frameId {
                // For specific frames, we'd need to find the frame and execute there
                // This is a simplified implementation that executes in the main frame
                finalScript = script
            } else {
                finalScript = script
            }

            webView.evaluateJavaScript(finalScript) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - JavaScript API Injection

    /// Injects the Chrome Scripting API bridge into a web view
    func injectScriptingAPIIntoWebView(_ webView: WKWebView, extensionId: String) {
        let scriptingScript = generateScriptingAPIScript(extensionId: extensionId)

        webView.evaluateJavaScript(scriptingScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Scripting] Error injecting scripting API: \(error)")
            } else {
                print("[ExtensionManager+Scripting] Scripting API injected successfully")
            }
        }
    }

    private func generateScriptingAPIScript(extensionId: String) -> String {
        return """
        (function() {
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }

            if (!chrome.scripting) {
                chrome.scripting = {
                    executeScript: function(injection, callback) {
                        const messageData = {
                            type: 'executeScript',
                            injection: injection,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeScriptingCallbacks = window.chromeScriptingCallbacks || {};
                            window.chromeScriptingCallbacks[messageId] = function(results) {
                                if (results && results.length > 0) {
                                    callback(results);
                                } else {
                                    callback([]);
                                }
                            };
                        }

                        window.webkit.messageHandlers.chromeScripting.postMessage(messageData);
                    },
                    insertCSS: function(injection, callback) {
                        const messageData = {
                            type: 'insertCSS',
                            injection: injection,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeScriptingCallbacks = window.chromeScriptingCallbacks || {};
                            window.chromeScriptingCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeScripting.postMessage(messageData);
                    },
                    removeCSS: function(injection, callback) {
                        const messageData = {
                            type: 'removeCSS',
                            injection: injection,
                            timestamp: Date.now()
                        };

                        if (callback) {
                            const messageId = Date.now().toString();
                            window.chromeScriptingCallbacks = window.chromeScriptingCallbacks || {};
                            window.chromeScriptingCallbacks[messageId] = callback;
                        }

                        window.webkit.messageHandlers.chromeScripting.postMessage(messageData);
                    }
                };

                console.log('[Chrome Scripting API] Scripting API initialized');
            }
        })();
        """
    }
}

// MARK: - Data Models

@available(macOS 15.4, *)
struct ScriptingInjection {
    let targetTabId: String?
    let function: String?
    let code: String?
    let file: String?
    let frameId: String?
}

@available(macOS 15.4, *)
struct CSSInjection {
    let targetTabId: String?
    let css: String?
    let file: String?
    let frameId: String?
}

@available(macOS 15.4, *)
struct ScriptingResult {
    let frameId: String?
    let result: Any?
    let error: String?
}

@available(macOS 15.4, *)
enum ScriptingError: Error {
    case fileNotFound
    case fileLoadFailed
    case scriptExecutionFailed
}

// MARK: - WKScriptMessageHandler for Scripting
@available(macOS 15.4, *)
extension ExtensionManager {

    func handleScriptingScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "chromeScripting",
              let messageBody = message.body as? [String: Any],
              let messageType = messageBody["type"] as? String else { return }

        print("[ExtensionManager+Scripting] Received scripting script message: \(messageType)")

        let timestamp = messageBody["timestamp"] as? String ?? ""

        switch messageType {
        case "executeScript":
            guard let injectionData = messageBody["injection"] as? [String: Any] else { return }

            let injection = ScriptingInjection(
                targetTabId: injectionData["targetTabId"] as? String,
                function: injectionData["func"] as? String,
                code: injectionData["code"] as? String,
                file: injectionData["file"] as? String,
                frameId: injectionData["frameId"] as? String
            )

            handleScriptingExecuteScript(injection: injection, from: extensionContextsAccess.values.first!) { results, error in
                self.sendScriptingResponse(timestamp: timestamp, data: results, error: error)
            }

        case "insertCSS":
            guard let injectionData = messageBody["injection"] as? [String: Any] else { return }

            let injection = CSSInjection(
                targetTabId: injectionData["targetTabId"] as? String,
                css: injectionData["css"] as? String,
                file: injectionData["file"] as? String,
                frameId: injectionData["frameId"] as? String
            )

            handleScriptingInsertCSS(injection: injection, from: extensionContextsAccess.values.first!) { error in
                self.sendScriptingResponse(timestamp: timestamp, data: nil, error: error)
            }

        case "removeCSS":
            guard let injectionData = messageBody["injection"] as? [String: Any] else { return }

            let injection = CSSInjection(
                targetTabId: injectionData["targetTabId"] as? String,
                css: injectionData["css"] as? String,
                file: injectionData["file"] as? String,
                frameId: injectionData["frameId"] as? String
            )

            handleScriptingRemoveCSS(injection: injection, from: extensionContextsAccess.values.first!) { error in
                self.sendScriptingResponse(timestamp: timestamp, data: nil, error: error)
            }

        default:
            print("[ExtensionManager+Scripting] Unknown scripting message type: \(messageType)")
        }
    }

    private func sendScriptingResponse(timestamp: String, data: Any?, error: Error?) {
        // Find the extension context that has active Chrome API callbacks
        guard let extensionContext = findExtensionContextWithScriptingCallbacks(timestamp: timestamp) else {
            print("[ExtensionManager+Scripting] No extension context found for timestamp \(timestamp)")
            return
        }

        // Get the web view associated with this extension context
        guard let webView = getWebViewForExtensionContext(extensionContext) else {
            print("[ExtensionManager+Scripting] No web view found for extension context")
            return
        }

        let responseScript: String
        if let error = error {
            responseScript = """
            if (window.chromeScriptingCallbacks && window.chromeScriptingCallbacks['\(timestamp)']) {
                console.error('[Chrome Scripting API]', '\(error.localizedDescription.replacingOccurrences(of: "'", with: "\\'"))');
                delete window.chromeScriptingCallbacks['\(timestamp)'];
            }
            """
        } else {
            let dataString: String
            if let data = data {
                if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                    let base64String = jsonData.base64EncodedString()
                    dataString = "JSON.parse(atob('\(base64String)'))"
                } else {
                    dataString = "[]"
                }
            } else {
                dataString = "[]"
            }
            responseScript = """
            if (window.chromeScriptingCallbacks && window.chromeScriptingCallbacks['\(timestamp)']) {
                window.chromeScriptingCallbacks['\(timestamp)'](\(dataString));
                delete window.chromeScriptingCallbacks['\(timestamp)'];
            }
            """
        }

        // Inject the response script into the web view
        webView.evaluateJavaScript(responseScript) { result, error in
            if let error = error {
                print("[ExtensionManager+Scripting] Error injecting response script: \(error)")
            } else {
                print("[ExtensionManager+Scripting] Response injected successfully for timestamp \(timestamp)")
            }
        }
    }

    /// Find the extension context that has active Chrome API callbacks for the given timestamp
    private func findExtensionContextWithScriptingCallbacks(timestamp: String) -> WKWebExtensionContext? {
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
