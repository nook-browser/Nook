//
//  ExtensionManager+Clipboard.swift
//  Nook
//
//  Implements navigator.clipboard API for browser extensions.
//  Provides clipboard read/write functionality for password managers like Bitwarden.
//
//  Bitwarden Usage Pattern (from browser-clipboard.service.ts):
//  - Uses navigator.clipboard.writeText(text) for copying passwords/TOTP
//  - Uses navigator.clipboard.readText() for reading clipboard content
//  - Has fallback to document.execCommand('copy'/'paste') if modern API unavailable
//

import Foundation
import AppKit
import WebKit

@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Clipboard API Setup
    
    /// Inject navigator.clipboard API polyfill into extension contexts
    /// This provides the standard W3C Async Clipboard API
    func injectClipboardAPI(into controller: WKUserContentController) {
        let script = """
        (function() {
            'use strict';
            
            // Only inject if clipboard API doesn't already exist or is incomplete
            if (!navigator.clipboard || !navigator.clipboard.writeText || !navigator.clipboard.readText) {
                console.log('[Clipboard API] Installing polyfill');
                
                // Callback storage for async operations
                window.chromeClipboardCallbacks = window.chromeClipboardCallbacks || {};
                
                // Create clipboard API object
                const clipboardAPI = {
                    writeText: function(text) {
                        return new Promise(function(resolve, reject) {
                            const timestamp = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
                            
                            // Store callbacks
                            window.chromeClipboardCallbacks[timestamp] = {
                                resolve: resolve,
                                reject: reject
                            };
                            
                            // Send message to native handler
                            window.webkit.messageHandlers.chromeClipboard.postMessage({
                                type: 'writeText',
                                text: text,
                                timestamp: timestamp
                            });
                        });
                    },
                    
                    readText: function() {
                        return new Promise(function(resolve, reject) {
                            const timestamp = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
                            
                            // Store callbacks
                            window.chromeClipboardCallbacks[timestamp] = {
                                resolve: resolve,
                                reject: reject
                            };
                            
                            // Send message to native handler
                            window.webkit.messageHandlers.chromeClipboard.postMessage({
                                type: 'readText',
                                timestamp: timestamp
                            });
                        });
                    }
                };
                
                // Install clipboard API
                if (!navigator.clipboard) {
                    Object.defineProperty(navigator, 'clipboard', {
                        value: clipboardAPI,
                        writable: false,
                        configurable: false
                    });
                } else {
                    // Patch existing incomplete implementation
                    navigator.clipboard.writeText = clipboardAPI.writeText;
                    navigator.clipboard.readText = clipboardAPI.readText;
                }
                
                console.log('[Clipboard API] Polyfill installed successfully');
            }
        })();
        """
        
        // Inject as user script at document start
        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false // Apply to all frames including iframes
        )
        controller.addUserScript(userScript)
        
        print("✅ [Clipboard] navigator.clipboard polyfill configured")
    }
    
    // MARK: - Message Handler
    
    /// Handle clipboard operations from extensions
    func handleClipboardScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "chromeClipboard",
              let messageBody = message.body as? [String: Any],
              let messageType = messageBody["type"] as? String,
              let timestamp = messageBody["timestamp"] as? String else {
            print("❌ [Clipboard] Invalid message format")
            return
        }
        
        print("📋 [Clipboard] Received request: \\(messageType) [\\(timestamp)]")
        
        switch messageType {
        case "writeText":
            handleClipboardWrite(messageBody: messageBody, message: message, timestamp: timestamp)
            
        case "readText":
            handleClipboardRead(message: message, timestamp: timestamp)
            
        default:
            print("❌ [Clipboard] Unknown method: \\(messageType)")
            sendClipboardErrorResponse(to: message, timestamp: timestamp, error: "Unknown clipboard method: \\(messageType)")
        }
    }
    
    // MARK: - Write Operations
    
    private func handleClipboardWrite(messageBody: [String: Any], message: WKScriptMessage, timestamp: String) {
        guard let text = messageBody["text"] as? String else {
            print("❌ [Clipboard] writeText: missing text parameter")
            sendClipboardErrorResponse(to: message, timestamp: timestamp, error: "Missing text parameter")
            return
        }
        
        // Perform clipboard write on main thread
        DispatchQueue.main.async { [weak self] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            let success = pasteboard.setString(text, forType: .string)
            
            if success {
                print("✅ [Clipboard] Successfully wrote \\(text.count) characters to clipboard")
                self?.sendClipboardSuccessResponse(to: message, timestamp: timestamp, data: nil)
            } else {
                print("❌ [Clipboard] Failed to write to clipboard")
                self?.sendClipboardErrorResponse(to: message, timestamp: timestamp, error: "Failed to write to system clipboard")
            }
        }
    }
    
    // MARK: - Read Operations
    
    private func handleClipboardRead(message: WKScriptMessage, timestamp: String) {
        // Perform clipboard read on main thread
        DispatchQueue.main.async { [weak self] in
            let pasteboard = NSPasteboard.general
            
            guard let text = pasteboard.string(forType: .string) else {
                print("⚠️ [Clipboard] No text content in clipboard")
                // Return empty string (not an error - clipboard might just be empty)
                self?.sendClipboardSuccessResponse(to: message, timestamp: timestamp, data: "")
                return
            }
            
            print("✅ [Clipboard] Successfully read \\(text.count) characters from clipboard")
            self?.sendClipboardSuccessResponse(to: message, timestamp: timestamp, data: text)
        }
    }
    
    // MARK: - Response Helpers

    /// Safely escape a string for JavaScript by using JSON serialization
    private func escapeForJavaScript(_ string: String) -> String {
        // Use JSONSerialization for safe string escaping
        // This handles all special characters including unicode, backslashes, quotes, etc.
        if let jsonData = try? JSONSerialization.data(withJSONObject: string),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // JSONSerialization wraps strings in quotes, so remove them
            var escaped = jsonString
            if escaped.hasPrefix("\"") && escaped.hasSuffix("\"") {
                escaped = String(escaped.dropFirst().dropLast())
            }
            return escaped
        }
        
        // Fallback to manual escaping if JSON serialization fails
        return string.replacingOccurrences(of: "\\", with: "\\\\")
                     .replacingOccurrences(of: "'", with: "\\'")
                     .replacingOccurrences(of: "\n", with: "\\n")
                     .replacingOccurrences(of: "\r", with: "\\r")
                     .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    private func sendClipboardSuccessResponse(to message: WKScriptMessage, timestamp: String, data: String?) {
        guard let webView = message.webView else {
            print("❌ [Clipboard] No web view available for response")
            return
        }
        
        let responseScript: String
        if let data = data {
            // For readText - return the text
            // Use JSON-safe escaping
            let escapedData = escapeForJavaScript(data)
            
            responseScript = """
            if (window.chromeClipboardCallbacks && window.chromeClipboardCallbacks['\\(timestamp)']) {
                window.chromeClipboardCallbacks['\\(timestamp)'].resolve('\\(escapedData)');
                delete window.chromeClipboardCallbacks['\\(timestamp)'];
            }
            """
        } else {
            // For writeText - resolve with undefined
            responseScript = """
            if (window.chromeClipboardCallbacks && window.chromeClipboardCallbacks['\\(timestamp)']) {
                window.chromeClipboardCallbacks['\\(timestamp)'].resolve();
                delete window.chromeClipboardCallbacks['\\(timestamp)'];
            }
            """
        }
        
        webView.evaluateJavaScript(responseScript) { _, error in
            if let error = error {
                print("❌ [Clipboard] Error injecting response script: \\(error)")
            } else {
                print("✅ [Clipboard] Response sent successfully [\\(timestamp)]")
            }
        }
    }
    
    private func sendClipboardErrorResponse(to message: WKScriptMessage, timestamp: String, error: String) {
        guard let webView = message.webView else {
            print("❌ [Clipboard] No web view available for error response")
            return
        }
        
        let escapedError = error.replacingOccurrences(of: "'", with: "\\\\'")
        
        let responseScript = """
        if (window.chromeClipboardCallbacks && window.chromeClipboardCallbacks['\\(timestamp)']) {
            window.chromeClipboardCallbacks['\\(timestamp)'].reject(new DOMException('\\(escapedError)', 'NotAllowedError'));
            delete window.chromeClipboardCallbacks['\\(timestamp)'];
        }
        """
        
        webView.evaluateJavaScript(responseScript) { _, error in
            if let error = error {
                print("❌ [Clipboard] Error injecting error response script: \\(error)")
            } else {
                print("✅ [Clipboard] Error response sent successfully [\\(timestamp)]")
            }
        }
    }
}

