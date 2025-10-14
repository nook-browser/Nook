//
//  ExtensionManager+DNR.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  declarativeNetRequest API message handlers and JavaScript bridge
//

import Foundation
import WebKit
import os.log

@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - JavaScript Bridge Injection
    
    /// Get JavaScript code to inject chrome.declarativeNetRequest API
    func getDeclarativeNetRequestAPIBridge() -> String {
        return """
        // Chrome declarativeNetRequest API Bridge
        (function() {
            if (window.chrome && window.chrome.declarativeNetRequest) {
                console.log('✅ [DNR] API already injected');
                return;
            }
            
            // Create chrome.declarativeNetRequest namespace
            if (!window.chrome) window.chrome = {};
            
            window.chrome.declarativeNetRequest = {
                // Update dynamic rules
                updateDynamicRules: function(options, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'updateDynamicRules',
                            options: {
                                addRules: options.addRules || [],
                                removeRuleIds: options.removeRuleIds || []
                            }
                        }).then(() => {
                            console.log('✅ [DNR] updateDynamicRules() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [DNR] updateDynamicRules() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Get dynamic rules
                getDynamicRules: function(callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'getDynamicRules'
                        }).then(rules => {
                            console.log('✅ [DNR] getDynamicRules():', rules.length, 'rules');
                            if (callback) callback(rules);
                            resolve(rules);
                        }).catch(error => {
                            console.error('❌ [DNR] getDynamicRules() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Update session rules
                updateSessionRules: function(options, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'updateSessionRules',
                            options: {
                                addRules: options.addRules || [],
                                removeRuleIds: options.removeRuleIds || []
                            }
                        }).then(() => {
                            console.log('✅ [DNR] updateSessionRules() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [DNR] updateSessionRules() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Get session rules
                getSessionRules: function(callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'getSessionRules'
                        }).then(rules => {
                            console.log('✅ [DNR] getSessionRules():', rules.length, 'rules');
                            if (callback) callback(rules);
                            resolve(rules);
                        }).catch(error => {
                            console.error('❌ [DNR] getSessionRules() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Get enabled rulesets (static rules)
                getEnabledRulesets: function(callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'getEnabledRulesets'
                        }).then(rulesets => {
                            console.log('✅ [DNR] getEnabledRulesets():', rulesets.length, 'rulesets');
                            if (callback) callback(rulesets);
                            resolve(rulesets);
                        }).catch(error => {
                            console.error('❌ [DNR] getEnabledRulesets() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Update enabled rulesets
                updateEnabledRulesets: function(options, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'updateEnabledRulesets',
                            options: {
                                enableRulesetIds: options.enableRulesetIds || [],
                                disableRulesetIds: options.disableRulesetIds || []
                            }
                        }).then(() => {
                            console.log('✅ [DNR] updateEnabledRulesets() succeeded');
                            if (callback) callback();
                            resolve();
                        }).catch(error => {
                            console.error('❌ [DNR] updateEnabledRulesets() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Get matched rules (for debugging)
                getMatchedRules: function(filter, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'getMatchedRules',
                            filter: filter || {}
                        }).then(result => {
                            console.log('✅ [DNR] getMatchedRules():', result.rulesMatchedInfo?.length || 0, 'matches');
                            if (callback) callback(result);
                            resolve(result);
                        }).catch(error => {
                            console.error('❌ [DNR] getMatchedRules() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Test match outcome
                testMatchOutcome: function(request, callback) {
                    return new Promise((resolve, reject) => {
                        window.webkit.messageHandlers.extensionDNR.postMessage({
                            method: 'testMatchOutcome',
                            request: request
                        }).then(result => {
                            console.log('✅ [DNR] testMatchOutcome():', result.matchedRules?.length || 0, 'matches');
                            if (callback) callback(result);
                            resolve(result);
                        }).catch(error => {
                            console.error('❌ [DNR] testMatchOutcome() failed:', error);
                            reject(error);
                        });
                    });
                },
                
                // Constants
                MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: 5000,
                MAX_NUMBER_OF_STATIC_RULESETS: 50,
                MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 10,
                GUARANTEED_MINIMUM_STATIC_RULES: 30000
            };
            
            console.log('✅ [DNR] API bridge injected successfully');
        })();
        """
    }
    
    // MARK: - Message Handlers
    
    /// Handle DNR API messages from JavaScript
    func handleDNRMessage(_ message: WKScriptMessage, body: [String: Any]) async {
        guard let method = body["method"] as? String else {
            sendDNRErrorResponse(to: message, error: "Missing method")
            return
        }
        
        // Get extension ID from the message's webView/context
        guard let extensionId = getExtensionId(for: message) else {
            sendDNRErrorResponse(to: message, error: "Unable to determine extension ID")
            return
        }
        
        let logger = Logger(subsystem: "com.nook.ExtensionManager", category: "DNR")
        logger.debug("📨 [DNR] Handling \(method) for extension \(extensionId)")
        
        do {
            switch method {
            case "updateDynamicRules":
                guard let options = body["options"] as? [String: Any] else {
                    sendDNRErrorResponse(to: message, error: "Missing options")
                    return
                }
                try await dnrManager.updateDynamicRules(for: extensionId, options: options)
                
                // Apply updated rules to all webviews
                await applyRulesToAllWebViews(for: extensionId)
                
                sendDNRSuccessResponse(to: message, result: nil)
                
            case "getDynamicRules":
                let rules = dnrManager.getDynamicRules(for: extensionId)
                let rulesArray = try encodeRules(rules)
                sendDNRSuccessResponse(to: message, result: rulesArray)
                
            case "updateSessionRules":
                guard let options = body["options"] as? [String: Any] else {
                    sendDNRErrorResponse(to: message, error: "Missing options")
                    return
                }
                try await dnrManager.updateSessionRules(for: extensionId, options: options)
                
                // Apply updated rules to all webviews
                await applyRulesToAllWebViews(for: extensionId)
                
                sendDNRSuccessResponse(to: message, result: nil)
                
            case "getSessionRules":
                let rules = dnrManager.getSessionRules(for: extensionId)
                let rulesArray = try encodeRules(rules)
                sendDNRSuccessResponse(to: message, result: rulesArray)
                
            case "getEnabledRulesets":
                // Return list of enabled static rulesets
                // This is a simplified implementation
                let rulesets: [[String: Any]] = []
                sendDNRSuccessResponse(to: message, result: rulesets)
                
            case "updateEnabledRulesets":
                // Update which static rulesets are enabled
                // Simplified: not implemented yet
                sendDNRSuccessResponse(to: message, result: nil)
                
            case "getMatchedRules":
                // Return matched rules for debugging
                // Simplified: return empty result
                let result: [String: Any] = ["rulesMatchedInfo": []]
                sendDNRSuccessResponse(to: message, result: result)
                
            case "testMatchOutcome":
                // Test if a request would match any rules
                // Simplified: return empty result
                let result: [String: Any] = ["matchedRules": []]
                sendDNRSuccessResponse(to: message, result: result)
                
            default:
                sendDNRErrorResponse(to: message, error: "Unknown method: \(method)")
            }
        } catch {
            logger.error("❌ [DNR] Error handling \(method): \(error.localizedDescription)")
            sendDNRErrorResponse(to: message, error: error.localizedDescription)
        }
    }
    
    // MARK: - Rule Application
    
    /// Apply DNR rules to all browser webviews
    @MainActor
    private func applyRulesToAllWebViews(for extensionId: String) async {
        guard let ruleList = dnrManager.getRuleList(for: extensionId) else {
            return
        }
        
        let logger = Logger(subsystem: "com.nook.ExtensionManager", category: "DNR")
        logger.info("🔧 Applying rules to all webviews for extension \(extensionId)")
        
        // Get all browser tabs and apply rules
        guard let browserManager = browserManagerRef else {
            logger.warning("⚠️ BrowserManager not available")
            return
        }
        
        let tabs = await browserManager.getAllTabs()
        
        for tab in tabs {
            guard let webView = tab.webView else { continue }
            
            // Remove old rule list
            let config = webView.configuration
            for existingRuleList in config.userContentController.contentRuleLists {
                config.userContentController.remove(existingRuleList)
            }
            
            // Add new rule list
            config.userContentController.add(ruleList)
            
            logger.debug("✅ Applied rules to tab \(tab.id)")
        }
        
        logger.info("✅ Applied rules to \(tabs.count) tabs")
    }
    
    // MARK: - Helper Methods
    
    /// Encode rules to JSON-compatible array
    private func encodeRules(_ rules: [DeclarativeNetRequestManager.DNRRule]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(rules)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "DNR", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode rules"])
        }
        return array
    }
    
    /// Send success response to JavaScript
    private func sendDNRSuccessResponse(to message: WKScriptMessage, result: Any?) {
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
    private func sendDNRErrorResponse(to message: WKScriptMessage, error: String) {
        guard let webView = message.webView else { return }
        
        Task { @MainActor in
            let escapedError = error.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("Promise.reject(new Error('\(escapedError)'))")
        }
    }
}

