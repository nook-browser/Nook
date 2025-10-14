//
//  ScriptingManager.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  Manages chrome.scripting API for CSS and JavaScript injection
//

import Foundation
import WebKit
import os.log

/// Manages chrome.scripting API for content injection
@available(macOS 15.4, *)
class ScriptingManager {
    
    // MARK: - Types
    
    /// CSS injection details
    struct CSSInjection: Codable {
        let target: InjectionTarget
        let css: String?
        let files: [String]?
        let origin: String? // "AUTHOR" or "USER"
    }
    
    /// Script injection details
    struct ScriptInjection: Codable {
        let target: InjectionTarget
        let func: String?
        let args: [AnyCodable]?
        let files: [String]?
        let world: String? // "ISOLATED" or "MAIN"
        let injectImmediately: Bool?
    }
    
    /// Injection target
    struct InjectionTarget: Codable {
        let tabId: Int?
        let frameIds: [Int]?
        let documentIds: [String]?
        let allFrames: Bool?
    }
    
    /// Result of script execution
    struct InjectionResult: Codable {
        let frameId: Int
        let result: AnyCodable?
        let error: String?
    }
    
    /// Content script registration
    struct RegisteredContentScript: Codable {
        let id: String
        let matches: [String]
        let excludeMatches: [String]?
        let css: [String]?
        let js: [String]?
        let allFrames: Bool?
        let matchOriginAsFallback: Bool?
        let runAt: String? // "document_start", "document_end", "document_idle"
        let world: String? // "ISOLATED" or "MAIN"
    }
    
    enum ScriptingError: Error {
        case invalidTarget(String)
        case injectionFailed(String)
        case invalidScript(String)
        case tabNotFound(Int)
    }
    
    // MARK: - Properties
    
    /// Injected CSS per tab and extension
    private var injectedCSS: [String: [Int: [String]]] = [:] // [extensionId: [tabId: [css]]]
    
    /// Registered content scripts per extension
    private var registeredScripts: [String: [String: RegisteredContentScript]] = [:] // [extensionId: [scriptId: script]]
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Logger
    private let logger = Logger(subsystem: "com.nook.ScriptingManager", category: "Scripting")
    
    /// Callback to get WKWebView for a tab ID
    var getWebViewForTab: ((Int) async -> WKWebView?)?
    
    // MARK: - CSS Injection
    
    /// Insert CSS into tabs
    func insertCSS(for extensionId: String, injection: CSSInjection) async throws -> [InjectionResult] {
        logger.info("💉 Inserting CSS for extension \(extensionId)")
        
        guard let css = injection.css else {
            throw ScriptingError.invalidScript("No CSS provided")
        }
        
        // Get target tabs
        let tabIds = try resolveTabIds(from: injection.target)
        
        var results: [InjectionResult] = []
        
        for tabId in tabIds {
            do {
                try await injectCSSIntoTab(tabId: tabId, css: css, extensionId: extensionId)
                
                // Track injected CSS
                lock.lock()
                if injectedCSS[extensionId] == nil {
                    injectedCSS[extensionId] = [:]
                }
                if injectedCSS[extensionId]?[tabId] == nil {
                    injectedCSS[extensionId]?[tabId] = []
                }
                injectedCSS[extensionId]?[tabId]?.append(css)
                lock.unlock()
                
                results.append(InjectionResult(frameId: 0, result: AnyCodable(nil), error: nil))
                logger.debug("✅ CSS injected into tab \(tabId)")
            } catch {
                results.append(InjectionResult(frameId: 0, result: nil, error: error.localizedDescription))
                logger.error("❌ Failed to inject CSS into tab \(tabId): \(error.localizedDescription)")
            }
        }
        
        return results
    }
    
    /// Remove CSS from tabs
    func removeCSS(for extensionId: String, injection: CSSInjection) async throws -> [InjectionResult] {
        logger.info("🗑️ Removing CSS for extension \(extensionId)")
        
        guard let css = injection.css else {
            throw ScriptingError.invalidScript("No CSS provided")
        }
        
        // Get target tabs
        let tabIds = try resolveTabIds(from: injection.target)
        
        var results: [InjectionResult] = []
        
        for tabId in tabIds {
            do {
                try await removeCSSFromTab(tabId: tabId, css: css, extensionId: extensionId)
                
                // Remove from tracking
                lock.lock()
                if let index = injectedCSS[extensionId]?[tabId]?.firstIndex(of: css) {
                    injectedCSS[extensionId]?[tabId]?.remove(at: index)
                }
                lock.unlock()
                
                results.append(InjectionResult(frameId: 0, result: AnyCodable(nil), error: nil))
                logger.debug("✅ CSS removed from tab \(tabId)")
            } catch {
                results.append(InjectionResult(frameId: 0, result: nil, error: error.localizedDescription))
                logger.error("❌ Failed to remove CSS from tab \(tabId): \(error.localizedDescription)")
            }
        }
        
        return results
    }
    
    // MARK: - Script Execution
    
    /// Execute script in tabs
    func executeScript(for extensionId: String, injection: ScriptInjection) async throws -> [InjectionResult] {
        logger.info("🔧 Executing script for extension \(extensionId)")
        
        // Get script to execute
        let script: String
        if let funcString = injection.func {
            // Function provided as string
            script = funcString
        } else if let files = injection.files, !files.isEmpty {
            // Files provided - would need to load from extension bundle
            // For now, simplified implementation
            throw ScriptingError.invalidScript("File-based scripts not yet implemented")
        } else {
            throw ScriptingError.invalidScript("No script provided")
        }
        
        // Get target tabs
        let tabIds = try resolveTabIds(from: injection.target)
        
        var results: [InjectionResult] = []
        
        for tabId in tabIds {
            do {
                let result = try await executeScriptInTab(tabId: tabId, script: script, world: injection.world ?? "ISOLATED")
                results.append(InjectionResult(frameId: 0, result: AnyCodable(result), error: nil))
                logger.debug("✅ Script executed in tab \(tabId)")
            } catch {
                results.append(InjectionResult(frameId: 0, result: nil, error: error.localizedDescription))
                logger.error("❌ Failed to execute script in tab \(tabId): \(error.localizedDescription)")
            }
        }
        
        return results
    }
    
    // MARK: - Content Script Registration
    
    /// Register content scripts for dynamic injection
    func registerContentScripts(for extensionId: String, scripts: [RegisteredContentScript]) async throws {
        logger.info("📝 Registering \(scripts.count) content scripts for extension \(extensionId)")
        
        lock.lock()
        if registeredScripts[extensionId] == nil {
            registeredScripts[extensionId] = [:]
        }
        
        for script in scripts {
            registeredScripts[extensionId]?[script.id] = script
            logger.debug("✅ Registered content script: \(script.id)")
        }
        lock.unlock()
    }
    
    /// Unregister content scripts
    func unregisterContentScripts(for extensionId: String, ids: [String]) async throws {
        logger.info("🗑️ Unregistering content scripts for extension \(extensionId)")
        
        lock.lock()
        for id in ids {
            registeredScripts[extensionId]?.removeValue(forKey: id)
            logger.debug("✅ Unregistered content script: \(id)")
        }
        lock.unlock()
    }
    
    /// Get registered content scripts
    func getRegisteredContentScripts(for extensionId: String) -> [RegisteredContentScript] {
        lock.lock()
        defer { lock.unlock() }
        return Array(registeredScripts[extensionId]?.values ?? [])
    }
    
    // MARK: - Helper Methods
    
    /// Resolve tab IDs from target
    private func resolveTabIds(from target: InjectionTarget) throws -> [Int] {
        if let tabId = target.tabId {
            return [tabId]
        }
        
        // If no specific tab, return empty (caller needs to provide tab context)
        throw ScriptingError.invalidTarget("No tab ID specified")
    }
    
    /// Inject CSS into a specific tab
    private func injectCSSIntoTab(tabId: Int, css: String, extensionId: String) async throws {
        // This needs access to the actual WKWebView for the tab
        // Will be implemented via callback to BrowserManager
        guard let webView = await getWebViewForTab(tabId) else {
            throw ScriptingError.tabNotFound(tabId)
        }
        
        // Create CSS injection script
        let script = """
        (function() {
            const styleId = 'nook-extension-\(extensionId)-\(abs(css.hashValue))';
            
            // Remove existing style if present
            const existingStyle = document.getElementById(styleId);
            if (existingStyle) {
                existingStyle.remove();
            }
            
            // Create and inject new style
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `\(css.replacingOccurrences(of: "`", with: "\\`"))`;
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        
        try await webView.evaluateJavaScript(script)
    }
    
    /// Remove CSS from a specific tab
    private func removeCSSFromTab(tabId: Int, css: String, extensionId: String) async throws {
        guard let webView = await getWebViewForTab(tabId) else {
            throw ScriptingError.tabNotFound(tabId)
        }
        
        let script = """
        (function() {
            const styleId = 'nook-extension-\(extensionId)-\(abs(css.hashValue))';
            const style = document.getElementById(styleId);
            if (style) {
                style.remove();
            }
        })();
        """
        
        try await webView.evaluateJavaScript(script)
    }
    
    /// Execute script in a specific tab
    private func executeScriptInTab(tabId: Int, script: String, world: String) async throws -> Any? {
        guard let webView = await getWebViewForTab(tabId) else {
            throw ScriptingError.tabNotFound(tabId)
        }
        
        // Wrap the script in an IIFE and execute
        let wrappedScript = """
        (function() {
            \(script)
        })();
        """
        
        return try await webView.evaluateJavaScript(wrappedScript)
    }
    
    /// Get WKWebView for a tab ID (placeholder - needs BrowserManager integration)
    private func getWebViewForTab(_ tabId: Int) async -> WKWebView? {
        return await getWebViewForTab?(tabId)
    }
    
    // MARK: - Cleanup
    
    /// Remove all injected CSS and scripts for an extension
    func cleanup(for extensionId: String) async {
        lock.lock()
        let cssToRemove = injectedCSS[extensionId] ?? [:]
        injectedCSS.removeValue(forKey: extensionId)
        registeredScripts.removeValue(forKey: extensionId)
        lock.unlock()
        
        // Remove all injected CSS
        for (tabId, cssList) in cssToRemove {
            for css in cssList {
                try? await removeCSSFromTab(tabId: tabId, css: css, extensionId: extensionId)
            }
        }
        
        logger.info("🗑️ Cleaned up scripting resources for extension \(extensionId)")
    }
}

// MARK: - Helper Types

/// Type-erased Codable wrapper for Any
struct AnyCodable: Codable {
    let value: Any?
    
    init(_ value: Any?) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = nil
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            self.value = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let value = value {
            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let array as [Any]:
                try container.encode(array.map { AnyCodable($0) })
            case let dict as [String: Any]:
                try container.encode(dict.mapValues { AnyCodable($0) })
            default:
                try container.encodeNil()
            }
        } else {
            try container.encodeNil()
        }
    }
}

