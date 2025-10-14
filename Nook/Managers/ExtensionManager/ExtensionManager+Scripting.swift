//
//  ExtensionManager+Scripting.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  chrome.scripting API message handlers and JavaScript bridge
//

import Foundation
import WebKit
import os.log

@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - JavaScript Bridge Injection
    
    /// Get JavaScript code to inject chrome.scripting API
    func getScriptingAPIBridge() -> String {
        return """
        // Chrome scripting API Bridge
        (function() {
            if (window.chrome && window.chrome.scripting) {
                console.log('✅ [Scripting] API already injected');
                return;
            }
            
            // Create chrome.scripting namespace
            if (!window.chrome) window.chrome = {};
            
            window.chrome.scripting = {
                // Insert CSS into pages
                insertCSS: function(injection, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'insertCSS',
                            injection: injection
                        }).then(results => {
                            console.log('✅ [Scripting] insertCSS() succeeded:', results.length, 'injections');
                            if (callback) callback(results);
                            resolve(results);
                        }).catch(error => {
                            console.error('❌ [Scripting] insertCSS() failed:', error);
                            if (callback) callback(undefined);
                            reject(error);
                        });
                    });
                },
                
                // Remove CSS from pages
                removeCSS: function(injection, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'removeCSS',
                            injection: injection
                        }).then(results => {
                            console.log('✅ [Scripting] removeCSS() succeeded:', results.length, 'removals');
                            if (callback) callback(results);
                            resolve(results);
                        }).catch(error => {
                            console.error('❌ [Scripting] removeCSS() failed:', error);
                            if (callback) callback(undefined);
                            reject(error);
                        });
                    });
                },
                
                // Execute script in pages
                executeScript: function(injection, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'executeScript',
                            injection: injection
                        }).then(results => {
                            console.log('✅ [Scripting] executeScript() succeeded:', results.length, 'executions');
                            if (callback) callback(results);
                            resolve(results);
                        }).catch(error => {
                            console.error('❌ [Scripting] executeScript() failed:', error);
                            if (callback) callback(undefined);
                            reject(error);
                        });
                    });
                },
                
                // Register content scripts dynamically
                registerContentScripts: function(scripts, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'registerContentScripts',
                            scripts: scripts
                        }).then(() => {
                            console.log('✅ [Scripting] registerContentScripts() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [Scripting] registerContentScripts() failed:', error);
                            if (callback) callback();
                            reject(error);
                        });
                    });
                },
                
                // Unregister content scripts
                unregisterContentScripts: function(filter, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'unregisterContentScripts',
                            filter: filter
                        }).then(() => {
                            console.log('✅ [Scripting] unregisterContentScripts() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [Scripting] unregisterContentScripts() failed:', error);
                            if (callback) callback();
                            reject(error);
                        });
                    });
                },
                
                // Get registered content scripts
                getRegisteredContentScripts: function(filter, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'getRegisteredContentScripts',
                            filter: filter || {}
                        }).then(scripts => {
                            console.log('✅ [Scripting] getRegisteredContentScripts():', scripts.length, 'scripts');
                            if (callback) callback(scripts);
                            resolve(scripts);
                        }).catch(error => {
                            console.error('❌ [Scripting] getRegisteredContentScripts() failed:', error);
                            if (callback) callback([]);
                            reject(error);
                        });
                    });
                },
                
                // Update content scripts
                updateContentScripts: function(scripts, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionScripting.postMessage({
                            method: 'updateContentScripts',
                            scripts: scripts
                        }).then(() => {
                            console.log('✅ [Scripting] updateContentScripts() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [Scripting] updateContentScripts() failed:', error);
                            if (callback) callback();
                            reject(error);
                        });
                    });
                }
            };
            
            console.log('✅ [Scripting] API bridge injected successfully');
        })();
        """
    }
    
    // MARK: - Message Handlers
    
    /// Handle scripting API messages from JavaScript
    func handleScriptingMessage(_ message: WKScriptMessage, body: [String: Any]) async {
        guard let method = body["method"] as? String else {
            sendScriptingErrorResponse(to: message, error: "Missing method")
            return
        }
        
        // Get extension ID from the message's webView/context
        guard let extensionId = getExtensionId(for: message) else {
            sendScriptingErrorResponse(to: message, error: "Unable to determine extension ID")
            return
        }
        
        let logger = Logger(subsystem: "com.nook.ExtensionManager", category: "Scripting")
        logger.debug("📨 [Scripting] Handling \(method) for extension \(extensionId)")
        
        do {
            switch method {
            case "insertCSS":
                guard let injectionData = body["injection"] as? [String: Any] else {
                    sendScriptingErrorResponse(to: message, error: "Missing injection data")
                    return
                }
                
                let injection = try parseCSSInjection(from: injectionData)
                let results = try await scriptingManager.insertCSS(for: extensionId, injection: injection)
                let resultsArray = try encodeInjectionResults(results)
                sendScriptingSuccessResponse(to: message, result: resultsArray)
                
            case "removeCSS":
                guard let injectionData = body["injection"] as? [String: Any] else {
                    sendScriptingErrorResponse(to: message, error: "Missing injection data")
                    return
                }
                
                let injection = try parseCSSInjection(from: injectionData)
                let results = try await scriptingManager.removeCSS(for: extensionId, injection: injection)
                let resultsArray = try encodeInjectionResults(results)
                sendScriptingSuccessResponse(to: message, result: resultsArray)
                
            case "executeScript":
                guard let injectionData = body["injection"] as? [String: Any] else {
                    sendScriptingErrorResponse(to: message, error: "Missing injection data")
                    return
                }
                
                let injection = try parseScriptInjection(from: injectionData)
                let results = try await scriptingManager.executeScript(for: extensionId, injection: injection)
                let resultsArray = try encodeInjectionResults(results)
                sendScriptingSuccessResponse(to: message, result: resultsArray)
                
            case "registerContentScripts":
                guard let scriptsData = body["scripts"] as? [[String: Any]] else {
                    sendScriptingErrorResponse(to: message, error: "Missing scripts data")
                    return
                }
                
                let scripts = try scriptsData.compactMap { try parseContentScript(from: $0) }
                try await scriptingManager.registerContentScripts(for: extensionId, scripts: scripts)
                sendScriptingSuccessResponse(to: message, result: nil)
                
            case "unregisterContentScripts":
                guard let filter = body["filter"] as? [String: Any],
                      let ids = filter["ids"] as? [String] else {
                    sendScriptingErrorResponse(to: message, error: "Missing filter or ids")
                    return
                }
                
                try await scriptingManager.unregisterContentScripts(for: extensionId, ids: ids)
                sendScriptingSuccessResponse(to: message, result: nil)
                
            case "getRegisteredContentScripts":
                let scripts = scriptingManager.getRegisteredContentScripts(for: extensionId)
                let scriptsArray = try encodeContentScripts(scripts)
                sendScriptingSuccessResponse(to: message, result: scriptsArray)
                
            case "updateContentScripts":
                // Simplified: just re-register
                guard let scriptsData = body["scripts"] as? [[String: Any]] else {
                    sendScriptingErrorResponse(to: message, error: "Missing scripts data")
                    return
                }
                
                let scripts = try scriptsData.compactMap { try parseContentScript(from: $0) }
                try await scriptingManager.registerContentScripts(for: extensionId, scripts: scripts)
                sendScriptingSuccessResponse(to: message, result: nil)
                
            default:
                sendScriptingErrorResponse(to: message, error: "Unknown method: \(method)")
            }
        } catch {
            logger.error("❌ [Scripting] Error handling \(method): \(error.localizedDescription)")
            sendScriptingErrorResponse(to: message, error: error.localizedDescription)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Parse CSS injection from dictionary
    private func parseCSSInjection(from dict: [String: Any]) throws -> ScriptingManager.CSSInjection {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ScriptingManager.CSSInjection.self, from: data)
    }
    
    /// Parse script injection from dictionary
    private func parseScriptInjection(from dict: [String: Any]) throws -> ScriptingManager.ScriptInjection {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ScriptingManager.ScriptInjection.self, from: data)
    }
    
    /// Parse content script from dictionary
    private func parseContentScript(from dict: [String: Any]) throws -> ScriptingManager.RegisteredContentScript {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ScriptingManager.RegisteredContentScript.self, from: data)
    }
    
    /// Encode injection results to JSON-compatible array
    private func encodeInjectionResults(_ results: [ScriptingManager.InjectionResult]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(results)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "Scripting", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode results"])
        }
        return array
    }
    
    /// Encode content scripts to JSON-compatible array
    private func encodeContentScripts(_ scripts: [ScriptingManager.RegisteredContentScript]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(scripts)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "Scripting", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode scripts"])
        }
        return array
    }
    
    /// Send success response to JavaScript
    private func sendScriptingSuccessResponse(to message: WKScriptMessage, result: Any?) {
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
    private func sendScriptingErrorResponse(to message: WKScriptMessage, error: String) {
        guard let webView = message.webView else { return }
        
        Task { @MainActor in
            let escapedError = error.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("Promise.reject(new Error('\(escapedError)'))")
        }
    }
}

