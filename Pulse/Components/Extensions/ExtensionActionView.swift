//
//  ExtensionActionView.swift
//  Pulse
//
//  Created for WKWebExtension UI surfaces
//

import SwiftUI
import WebKit
import AppKit

@available(macOS 15.4, *)
struct ExtensionActionView: View {
    let extensions: [InstalledExtension]
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(extensions.filter { $0.isEnabled }, id: \.id) { ext in
                ExtensionActionButton(ext: ext)
                    .environmentObject(browserManager)
            }
        }
    }
}

@available(macOS 15.4, *)
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    @State private var showingPopover = false
    @State private var popoverSize: CGSize = CGSize(width: 360, height: 300)
    
    var body: some View {
        Button(action: {
            handleExtensionAction()
        }) {
            Group {
                if let iconPath = ext.iconPath,
                   let nsImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .background(
            PersistentPopover(isPresented: $showingPopover, contentSize: $popoverSize) {
                ExtensionPopoverView(ext: ext, popoverSize: $popoverSize)
                    .environmentObject(browserManager)
            }
        )
        .help(ext.name)
    }
    
    private func handleExtensionAction() {
        // Check if extension has a browser action popup
        if hasPopup() {
            showingPopover.toggle()
        } else {
            // Grant activeTab permission and execute action
            grantActiveTabPermission()
        }
    }
    
    private func hasPopup() -> Bool {
        // Check manifest for browser_action.default_popup or action.default_popup
        if let action = ext.manifest["action"] as? [String: Any],
           let _ = action["default_popup"] as? String {
            return true
        }
        
        if let browserAction = ext.manifest["browser_action"] as? [String: Any],
           let _ = browserAction["default_popup"] as? String {
            return true
        }
        
        return false
    }
    
    private func grantActiveTabPermission() {
        guard let extensionManager = browserManager.extensionManager,
              let currentTab = browserManager.tabManager.currentTab else { return }
        
        let host = currentTab.url.host ?? currentTab.url.absoluteString
        
        // Grant temporary activeTab permission
        extensionManager.storeHostPermission(
            extensionId: ext.id,
            host: host,
            granted: true,
            isTemporary: true
        )
    }
}

@available(macOS 15.4, *)
struct ExtensionPopoverView: View {
    let ext: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    @State private var webView: WKWebView?
    @Binding var popoverSize: CGSize
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Group {
                    if let iconPath = ext.iconPath,
                       let nsImage = NSImage(contentsOfFile: iconPath) {
                        Image(nsImage: nsImage)
                            .resizable()
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 16, height: 16)
                
                Text(ext.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Options") {
                    openOptionsPage()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)

                Button("Inspect") {
                    openInspector()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)

                Button("Debug in Tab") {
                    openPopupInTab()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            
            // Web content (auto-sized)
            ExtensionWebView(
                ext: ext,
                webView: $webView,
                activeTabURL: browserManager.tabManager.currentTab?.url.absoluteString,
                activeTabTitle: browserManager.tabManager.currentTab?.name
            ) { newSize in
                // Clamp to Chrome-like popup constraints
                let clamped = CGSize(
                    width: max(25, min(800, newSize.width)),
                    height: max(25, min(600, newSize.height))
                )
                if clamped != popoverSize {
                    popoverSize = clamped
                }
            }
            .frame(width: popoverSize.width, height: popoverSize.height)
            .clipped()
        }
        .onAppear {
            grantActiveTabPermission()
        }
    }
    
    private func openOptionsPage() {
        guard let optionsPage = getOptionsPage() else { 
            print("WARNING: No options page found for extension: \(ext.name)")
            return 
        }
        
        // Validate and construct options URL
        let cleanPage = optionsPage.hasPrefix("/") ? String(optionsPage.dropFirst()) : optionsPage
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let optionsURL = extensionURL.appendingPathComponent(cleanPage)
        
        // Security check: ensure the file is within the extension directory
        guard optionsURL.path.hasPrefix(extensionURL.path) else {
            print("ERROR: Options page path appears to be outside extension directory")
            return
        }
        
        // Check if options file exists and is readable
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: optionsURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue {
            // Use chrome-extension scheme for proper loading
            let chromeExtensionURL = "chrome-extension://\(ext.id)/\(cleanPage)"
            print("Opening options page: \(chromeExtensionURL)")
            let newTab = browserManager.tabManager.createNewTab(url: chromeExtensionURL)
            browserManager.tabManager.setActiveTab(newTab)
        } else {
            print("ERROR: Options file not found or is not accessible at: \(optionsURL.path)")
            logAvailableFilesForPopover()
        }
    }
    
    private func getOptionsPage() -> String? {
        if let optionsUI = ext.manifest["options_ui"] as? [String: Any],
           let page = optionsUI["page"] as? String {
            return page
        }
        
        if let page = ext.manifest["options_page"] as? String {
            return page
        }
        
        return nil
    }
    
    private func getExtensionURL(for page: String) -> URL {
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        
        // Clean and validate the page path
        var cleanPage = page.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPage.hasPrefix("/") {
            cleanPage.removeFirst()
        }
        
        // Prevent directory traversal attacks
        let components = cleanPage.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePage = safeComponents.joined(separator: "/")
        
        return extensionURL.appendingPathComponent(safePage)
    }

    private func openInspector() {
        guard let wv = webView else { return }
        if #available(macOS 13.3, *) { wv.isInspectable = true }
        wv.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        func tryInspector(_ key: String) -> Bool {
            guard let insp = (wv.value(forKey: key) as AnyObject?) else { return false }
            let detachSel = NSSelectorFromString("detach")
            let setAttachedSel = NSSelectorFromString("setAttached:")
            let showSel = NSSelectorFromString("show")
            let showConsoleSel = NSSelectorFromString("showConsole")
            if insp.responds(to: detachSel) { _ = insp.perform(detachSel) }
            if insp.responds(to: setAttachedSel) { _ = insp.perform(setAttachedSel, with: false) }
            if insp.responds(to: showSel) { _ = insp.perform(showSel); return true }
            if insp.responds(to: showConsoleSel) { _ = insp.perform(showConsoleSel); return true }
            return false
        }
        let didShowInspector = (tryInspector("inspector") || tryInspector("_inspector"))
        if !didShowInspector {
            // Fallback: global action
            _ = NSApp.sendAction(NSSelectorFromString("showWebInspector:"), to: nil, from: wv)
            _ = NSApp.sendAction(NSSelectorFromString("toggleWebInspector:"), to: nil, from: wv)
        }
        // Always open our dedicated console window for reliability
        PopupConsole.shared.show()
    }

    private func openPopupInTab() {
        guard let popupPage = getPopupPage() else { return }
        var page = popupPage
        if page.hasPrefix("/") { page.removeFirst() }
        if let popupURL = URL(string: "chrome-extension://\(ext.id)/\(page)") {
            _ = browserManager.tabManager.createNewTab(url: popupURL.absoluteString)
            // Attempt to close popover if we’re in one
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    private func getPopupPage() -> String? {
        // Check for popup in action (Manifest V3)
        if let action = ext.manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String, !popup.isEmpty {
                if let validatedPopup = validatePopupFile(popup) {
                    print("Found valid V3 action popup: \(validatedPopup)")
                    return validatedPopup
                } else {
                    print("WARNING: V3 action popup '\(popup)' specified in manifest but file not found")
                }
            }
        }
        
        // Check for popup in browser_action (Manifest V2)
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            if let popup = browserAction["default_popup"] as? String, !popup.isEmpty {
                if let validatedPopup = validatePopupFile(popup) {
                    print("Found valid V2 browser_action popup: \(validatedPopup)")
                    return validatedPopup
                } else {
                    print("WARNING: V2 browser_action popup '\(popup)' specified in manifest but file not found")
                }
            }
        }
        
        // Enhanced fallback: Look for common popup file names in more locations
        let commonPopupFiles = [
            "popup.html", "popup/popup.html", "popup/index.html",
            "src/popup.html", "src/popup/popup.html", "src/popup/index.html",
            "ui/popup.html", "ui/popup/popup.html", "ui/popup/index.html",
            "pages/popup.html", "html/popup.html", "web/popup.html",
            "extension/popup.html", "browser/popup.html"
        ]
        
        for fileName in commonPopupFiles {
            if let validatedPopup = validatePopupFile(fileName) {
                print("Found fallback popup file: \(validatedPopup)")
                return validatedPopup
            }
        }
        
        // Final attempt: Search extension directory for any HTML file that might be a popup
        if let discoveredPopup = searchForPopupFile() {
            print("Discovered potential popup file: \(discoveredPopup)")
            return discoveredPopup
        }
        
        print("No popup page found for extension: \(ext.name)")
        logManifestDebuggingForPopover()
        return nil
    }
    
    private func searchForPopupFile() -> String? {
        let extensionDir = URL(fileURLWithPath: ext.packagePath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: extensionDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Look for HTML files that might be popups based on naming
            let popupKeywords = ["popup", "action", "browser", "main", "index"]
            let htmlFiles = files.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".html") && popupKeywords.contains { name.contains($0) }
            }
            
            // Prefer files with "popup" in the name
            for file in htmlFiles {
                let relativePath = String(file.path.dropFirst(extensionDir.path.count + 1))
                if file.lastPathComponent.lowercased().contains("popup") {
                    if validatePopupFile(relativePath) != nil {
                        return relativePath
                    }
                }
            }
            
            // Fall back to any matching HTML file
            for file in htmlFiles {
                let relativePath = String(file.path.dropFirst(extensionDir.path.count + 1))
                if validatePopupFile(relativePath) != nil {
                    return relativePath
                }
            }
        } catch {
            print("ERROR: Could not search for popup files: \(error)")
        }
        
        return nil
    }
    
    private func validatePopupFileExists(_ popupPath: String) -> Bool {
        guard !popupPath.isEmpty else { return false }
        
        // Clean up the path
        var cleanPath = popupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("/") {
            cleanPath.removeFirst()
        }
        
        // Validate path components for security
        let components = cleanPath.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePath = safeComponents.joined(separator: "/")
        
        guard !safePath.isEmpty else { return false }
        
        // Check if the file exists
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let popupURL = extensionURL.appendingPathComponent(safePath)
        
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: popupURL.path, isDirectory: &isDirectory)
        
        return fileExists && !isDirectory.boolValue
    }
    
    private func validatePopupFile(_ popupPath: String) -> String? {
        guard !popupPath.isEmpty else {
            return nil
        }
        
        // Clean up the path and prevent directory traversal
        var cleanPath = popupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("/") {
            cleanPath.removeFirst()
        }
        
        // Validate path components for security
        let components = cleanPath.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePath = safeComponents.joined(separator: "/")
        
        guard !safePath.isEmpty else {
            return nil
        }
        
        // Check if the popup file exists
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let popupURL = extensionURL.appendingPathComponent(safePath)
        
        // Verify the file exists and is readable
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: popupURL.path, isDirectory: &isDirectory)
        
        if !fileExists || isDirectory.boolValue {
            return nil
        }
        
        // Additional validation: ensure it's an HTML file
        let allowedExtensions = ["html", "htm"]
        let fileExtension = popupURL.pathExtension.lowercased()
        if !allowedExtensions.contains(fileExtension) {
            return nil
        }
        
        return safePath
    }
    
    private func grantActiveTabPermission() {
        guard let extensionManager = browserManager.extensionManager,
              let currentTab = browserManager.tabManager.currentTab else { return }
        
        let host = currentTab.url.host ?? currentTab.url.absoluteString
        
        // Grant temporary activeTab permission for popup
        extensionManager.storeHostPermission(
            extensionId: ext.id,
            host: host,
            granted: true,
            isTemporary: true
        )
    }
    
    private func logAvailableFilesForPopover() {
        let extensionDir = URL(fileURLWithPath: ext.packagePath)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: extensionDir, includingPropertiesForKeys: nil)
            let htmlFiles = files.filter { $0.pathExtension.lowercased() == "html" }
            print("Available HTML files: \(htmlFiles.map { $0.lastPathComponent })")
            
            // Look for common directories
            let directories = files.filter { $0.hasDirectoryPath }
            print("Available directories: \(directories.map { $0.lastPathComponent })")
        } catch {
            print("ERROR: Could not list extension files: \(error)")
        }
    }
    
    private func logManifestDebuggingForPopover() {
        print("=== Extension Manifest Debug Info ===")
        print("Extension: \(ext.name) (ID: \(ext.id))")
        print("Manifest keys: \(Array(ext.manifest.keys).sorted())")
        
        if let action = ext.manifest["action"] as? [String: Any] {
            print("Action manifest: \(action)")
        }
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            print("Browser action manifest: \(browserAction)")
        }
        
        logAvailableFilesForPopover()
        print("=== End Debug Info ===")
    }
}

@available(macOS 15.4, *)
struct ExtensionWebView: NSViewRepresentable {
    let ext: InstalledExtension
    @Binding var webView: WKWebView?
    var activeTabURL: String? = nil
    var activeTabTitle: String? = nil
    var onSizeChange: ((CGSize) -> Void)? = nil
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Enable developer extras for debugging
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Set up proper security origin for extension files
        if #available(macOS 12.0, *) {
            configuration.limitsNavigationsToAppBoundDomains = false
        }
        
        // Set up extension content controller for proper extension APIs
        let contentController = WKUserContentController()
        // Receive size updates and console logs from web content
        contentController.add(context.coordinator, name: "pulsePopupSize")
        contentController.add(context.coordinator, name: "pulseConsole")
        // Runtime/Port bridges
        contentController.add(context.coordinator, name: "pulseRuntime")
        contentController.add(context.coordinator, name: "pulsePort")
        // Storage bridge
        contentController.add(context.coordinator, name: "pulseStorage")

        // CRITICAL: Primary Chrome Extension API Setup - Must be first and synchronous
        let immediateAPIScript = """
        // === IMMEDIATE Chrome Extension API Setup - BEFORE DOM ===
        // This script MUST run first to ensure APIs are available when extension scripts load
        
        (function() {
            'use strict';
            
            // Core globals - define immediately
            if (typeof window.chrome === 'undefined') {
                window.chrome = {};
            }
            if (typeof window.browser === 'undefined') {
                window.browser = window.chrome;
            }
            
            // Essential Web APIs that extensions expect
            if (typeof window.requestIdleCallback === 'undefined') {
                window.requestIdleCallback = function(callback, options) {
                    var start = Date.now();
                    return setTimeout(function() {
                        callback({
                            didTimeout: false,
                            timeRemaining: function() {
                                return Math.max(0, 50 - (Date.now() - start));
                            }
                        });
                    }, 1);
                };
            }
            if (typeof window.cancelIdleCallback === 'undefined') {
                window.cancelIdleCallback = function(id) {
                    clearTimeout(id);
                };
            }
            
            // Define self for worker compatibility
            if (typeof self === 'undefined') {
                window.self = window;
            }
            
            // Essential chrome.runtime - MUST be available immediately
            if (!chrome.runtime) {
                chrome.runtime = {
                    id: '\(ext.id)',
                    getURL: function(path) {
                        return 'chrome-extension://\(ext.id)/' + String(path || '').replace(/^[/]+/, '');
                    },
                    lastError: null,
                    getManifest: function() {
                        return \(manifestJSON());
                    },
                    sendMessage: function(extensionId, message, options, callback) {
                        // Handle parameter overloads
                        if (typeof extensionId === 'object') {
                            callback = options; options = message; message = extensionId; extensionId = null;
                        }
                        if (typeof options === 'function') { callback = options; options = null; }
                        
                        var response = { success: true };
                        if (callback) setTimeout(function() { callback(response); }, 0);
                        return Promise.resolve(response);
                    }
                };
            }
            
            // Essential chrome.i18n - MUST be available immediately
            if (!chrome.i18n) {
                chrome.i18n = {
                    getMessage: function(messageName, substitutions) {
                        if (typeof messageName !== 'string') return '';
                        
                        // Common message keys with defaults
                        var commonMessages = {
                            'appName': 'Extension',
                            'appDesc': 'Browser Extension',
                            'ok': 'OK',
                            'cancel': 'Cancel',
                            'yes': 'Yes',
                            'no': 'No',
                            'enable': 'Enable',
                            'disable': 'Disable',
                            'options': 'Options',
                            'settings': 'Settings'
                        };
                        
                        return commonMessages[messageName] || messageName;
                    },
                    getUILanguage: function() {
                        return navigator.language || 'en';
                    }
                };
            }
            
            // Ensure browser aliases chrome properly
            window.browser = window.chrome;
            if (!window.browser.runtime) {
                window.browser.runtime = window.chrome.runtime;
            }
            if (!window.browser.i18n) {
                window.browser.i18n = window.chrome.i18n;
            }
            
            // uBlock Origin vAPI compatibility - immediate setup
            if (typeof window.vAPI === 'undefined') {
                window.vAPI = {
                    localStorage: {
                        getItemAsync: function(key) {
                            return Promise.resolve(localStorage.getItem(key));
                        },
                        setItemAsync: function(key, value) {
                            localStorage.setItem(key, value);
                            return Promise.resolve();
                        },
                        removeItemAsync: function(key) {
                            localStorage.removeItem(key);
                            return Promise.resolve();
                        }
                    },
                    closePopup: function() {
                        if (window.close) window.close();
                    }
                };
            }
            
            console.log('Chrome API polyfills loaded immediately');
        })();
        """
        let immediateScript = WKUserScript(source: immediateAPIScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(immediateScript)

        // Fix root-relative path resolution and network calls using chrome-extension:// origin
        let pathFixScript = #"""
        (function() {
            try {
                // Prefer the current location origin if available; otherwise, build from injected id
                const EXT_ORIGIN = (location && location.origin && location.origin !== 'null')
                    ? location.origin
                    : 'chrome-extension://\#(ext.id)';
                const EXT_ROOT = EXT_ORIGIN + '/';
                const toExtURL = (u) => {
                    if (typeof u !== 'string') return u;
                    // Rewrite root-relative URLs like '/img/icon.png' -> EXT_ROOT + 'img/icon.png'
                    if (u.startsWith('/')) return EXT_ROOT + u.replace(/^[/]+/, '');
                    return u;
                };

                // Inject <base> for relative URLs (does not affect leading '/')
                const ensureBase = () => {
                    if (!document.head) return;
                    const existing = document.head.querySelector('base');
                    if (!existing) {
                        const base = document.createElement('base');
                        base.href = EXT_ROOT;
                        document.head.prepend(base);
                    }
                };

                // Rewrite DOM resource URLs
                const rewriteDOM = () => {
                    const sel = [
                        'script[src^="/"], script[data-main^="/"]',
                        'link[rel="stylesheet"][href^="/"]',
                        'img[src^="/"]',
                        'source[src^="/"]',
                        'video[src^="/"]',
                        'audio[src^="/"]'
                    ].join(',');
                    document.querySelectorAll(sel).forEach(el => {
                        if (el.src) el.src = toExtURL(el.getAttribute('src'));
                        if (el.href) el.href = toExtURL(el.getAttribute('href'));
                        if (el.dataset && el.dataset.main && el.getAttribute('data-main')?.startsWith('/')) {
                            el.setAttribute('data-main', toExtURL(el.getAttribute('data-main')));
                        }
                    });
                };

                // Monkey-patch fetch and XHR for runtime requests
                // Avoid aggressive network monkey-patching; most resources resolve via base/origin

                // Initial pass and on DOM ready
                ensureBase();
                rewriteDOM();
                document.addEventListener('DOMContentLoaded', () => { ensureBase(); rewriteDOM(); }, { once: true });
            } catch (e) {
                console.log('POPUP DEBUG: pathFixScript error', e);
            }
        })();
        """#
        let pathScript = WKUserScript(source: pathFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(pathScript)
        
        // Early polyfill injection removed - consolidated into immediateAPIScript above
        
        // Inject extension API polyfills
        // Prepare active tab values
        let activeURLJS = (activeTabURL ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let activeTitleJS = (activeTabTitle ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")

        var extensionAPIs = #"""
        // === EXTENDED Chrome Extension APIs ===
        // Core APIs already defined in immediateAPIScript - this adds extended functionality
        
        (function() {
            'use strict';
            
            // Extend runtime API with additional functionality
            if (chrome.runtime) {
                // Add missing runtime methods
                if (!chrome.runtime.onMessage) {
                    chrome.runtime.onMessage = {
                        addListener: function(listener) { /* stub */ },
                        removeListener: function(listener) { /* stub */ },
                        hasListener: function(listener) { return false; }
                    };
                }
                
                if (!chrome.runtime.connect) {
                    chrome.runtime.connect = function(connectInfo) {
                        return {
                            name: connectInfo && connectInfo.name || '',
                            sender: { id: chrome.runtime.id },
                            onDisconnect: { addListener: function() {}, removeListener: function() {} },
                            onMessage: { addListener: function() {}, removeListener: function() {} },
                            postMessage: function() {},
                            disconnect: function() {}
                        };
                    };
                }
            }
        
            // Storage API - enhanced implementation with event support
            chrome.storage = chrome.storage || {
                local: {
                    get: function(keys, callback) {
                        var result = {};
                        if (callback) setTimeout(function() { callback(result); }, 0);
                        return Promise.resolve(result);
                    },
                    set: function(items, callback) {
                        if (callback) setTimeout(function() { callback(); }, 0);
                        return Promise.resolve();
                    },
                    remove: function(keys, callback) {
                        if (callback) setTimeout(function() { callback(); }, 0);
                        return Promise.resolve();
                    },
                    clear: function(callback) {
                        if (callback) setTimeout(function() { callback(); }, 0);
                        return Promise.resolve();
                    },
                    getBytesInUse: function(keys, callback) {
                        if (callback) setTimeout(function() { callback(0); }, 0);
                        return Promise.resolve(0);
                    }
                },
                // Storage change event support
                onChanged: {
                    listeners: [],
                    addListener: function(listener) {
                        if (typeof listener === 'function') {
                            this.listeners.push(listener);
                        }
                    },
                    removeListener: function(listener) {
                        const index = this.listeners.indexOf(listener);
                        if (index > -1) {
                            this.listeners.splice(index, 1);
                        }
                    },
                    hasListener: function(listener) {
                        return this.listeners.indexOf(listener) > -1;
                    },
                    dispatch: function(changes, area) {
                        for (let i = 0; i < this.listeners.length; i++) {
                            try {
                                this.listeners[i](changes, area);
                            } catch(e) {
                                console.error('Storage change listener error:', e);
                            }
                        }
                    }
                }
            };
            chrome.storage.sync = chrome.storage.local;
            chrome.storage.managed = chrome.storage.local;
            
            // Tabs API - provides current tab info
            var ACTIVE_TAB = {
                id: 1,
                url: '__ACTIVE_URL__',
                title: '__ACTIVE_TITLE__',
                active: true,
                windowId: 1,
                index: 0,
                favIconUrl: '',
                status: 'complete'
            };
            chrome.tabs = chrome.tabs || {
                query: function(queryInfo, callback) {
                    var tabs = [ACTIVE_TAB];
                    if (callback) setTimeout(function() { callback(tabs); }, 0);
                    return Promise.resolve(tabs);
                },
                get: function(tabId, callback) {
                    if (callback) setTimeout(function() { callback(ACTIVE_TAB); }, 0);
                    return Promise.resolve(ACTIVE_TAB);
                },
                getCurrent: function(callback) {
                    if (callback) setTimeout(function() { callback(ACTIVE_TAB); }, 0);
                    return Promise.resolve(ACTIVE_TAB);
                },
                sendMessage: function(tabId, message, options, callback) {
                    if (typeof options === 'function') { callback = options; }
                    var response = { success: true };
                    if (callback) setTimeout(function() { callback(response); }, 0);
                    return Promise.resolve(response);
                }
            };
            
            // Action/browserAction API - enhanced for popup compatibility
            var actionAPI = {
                setIcon: function(details, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                setBadgeText: function(details, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                setBadgeBackgroundColor: function(details, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                setTitle: function(details, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                getTitle: function(details, callback) {
                    if (callback) setTimeout(function() { callback('Extension'); }, 0);
                    return Promise.resolve('Extension');
                },
                getBadgeText: function(details, callback) {
                    if (callback) setTimeout(function() { callback(''); }, 0);
                    return Promise.resolve('');
                }
            };
            chrome.action = chrome.action || actionAPI;
            chrome.browserAction = chrome.browserAction || actionAPI;
            
            // Extension API - legacy support
            chrome.extension = chrome.extension || {
                getURL: function(path) {
                    return chrome.runtime.getURL(path);
                },
                getBackgroundPage: function() {
                    return null; // No background page in popup context
                },
                inIncognitoContext: false
            };
            
            // Permissions API - enhanced stub
            chrome.permissions = chrome.permissions || {
                contains: function(permissions, callback) {
                    if (callback) setTimeout(function() { callback(true); }, 0);
                    return Promise.resolve(true);
                },
                request: function(permissions, callback) {
                    if (callback) setTimeout(function() { callback(true); }, 0);
                    return Promise.resolve(true);
                },
                remove: function(permissions, callback) {
                    if (callback) setTimeout(function() { callback(true); }, 0);
                    return Promise.resolve(true);
                },
                getAll: function(callback) {
                    var permissions = { permissions: [], origins: [] };
                    if (callback) setTimeout(function() { callback(permissions); }, 0);
                    return Promise.resolve(permissions);
                }
            };
            
            // Windows API - basic support
            chrome.windows = chrome.windows || {
                getCurrent: function(getInfo, callback) {
                    if (typeof getInfo === 'function') { callback = getInfo; getInfo = {}; }
                    var windowObj = { id: 1, focused: true, type: 'normal' };
                    if (callback) setTimeout(function() { callback(windowObj); }, 0);
                    return Promise.resolve(windowObj);
                }
            };
            
            // Context Menus API - stub
            chrome.contextMenus = chrome.contextMenus || {
                create: function(createProperties, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                update: function(id, updateProperties, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                remove: function(menuItemId, callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                },
                removeAll: function(callback) {
                    if (callback) setTimeout(callback, 0);
                    return Promise.resolve();
                }
            };
            
            // Ensure all browser aliases are properly set up
            window.browser = window.chrome;
            window.browser.runtime = window.chrome.runtime;
            window.browser.i18n = window.chrome.i18n;
            window.browser.storage = window.chrome.storage;
            window.browser.tabs = window.chrome.tabs;
            
            console.log('Extended Chrome API polyfills loaded');
        })();
        """#

        // Inject active tab values into JS
        extensionAPIs = extensionAPIs.replacingOccurrences(of: "__ACTIVE_URL__", with: activeURLJS)
        extensionAPIs = extensionAPIs.replacingOccurrences(of: "__ACTIVE_TITLE__", with: activeTitleJS)
        
        let apiScript = WKUserScript(source: extensionAPIs, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(apiScript)
        
        // Simplified runtime bridge for essential messaging
        let runtimeBridgeScript = """
        (function(){
          try {
            // Simple message callbacks for compatibility
            window.__pulseMessageCallbacks = window.__pulseMessageCallbacks || {};
            
            // Override sendMessage to handle native bridge if needed
            if (window.webkit?.messageHandlers?.pulseRuntime) {
              const originalSendMessage = chrome.runtime.sendMessage;
              chrome.runtime.sendMessage = function(extensionId, message, options, callback) {
                // Handle parameter overloads
                if (typeof extensionId === 'object') {
                  callback = options; options = message; message = extensionId; extensionId = null;
                }
                if (typeof options === 'function') { callback = options; options = null; }
                
                try {
                  window.webkit.messageHandlers.pulseRuntime.postMessage({
                    action: 'sendMessage',
                    payload: { message, extensionId: extensionId || chrome.runtime.id }
                  });
                } catch(e) {
                  console.log('Message bridge error:', e);
                }
                
                // Provide fallback response
                const response = { success: true };
                if (callback) setTimeout(() => callback(response), 0);
                return Promise.resolve(response);
              };
            }
          } catch (e) {
            console.log('Runtime bridge setup error:', e);
          }
        })();
        """
        let runtimeScript = WKUserScript(source: runtimeBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(runtimeScript)
        
        // Simple initialization and cleanup
        let initScript = """
        (function() {
            // Remove common loading states
            document.addEventListener('DOMContentLoaded', function() {
                if (document.body) {
                    document.body.classList.remove('loading', 'preload');
                    document.body.style.visibility = 'visible';
                }
            });
            
            // Basic error handling
            window.addEventListener('error', function(e) {
                console.warn('Extension UI error:', e.message);
            });
        })();
        """
        
        let initScriptObj = WKUserScript(source: initScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(initScriptObj)
        
        // Enhanced console logging bridge with API error detection
        let consoleBridgeScript = """
        (function(){
          if (!window._pulseConsolePatched) {
            window._pulseConsolePatched = true;
            
            // Enhanced error handling for Chrome API issues
            window.addEventListener('error', function(e) {
              const msg = e.message || '';
              const isAPIError = msg.includes('chrome') || msg.includes('browser') || 
                               msg.includes('requestIdleCallback') || msg.includes('vAPI');
              if (isAPIError) {
                console.error('Chrome API Error:', msg, 'at', e.filename + ':' + e.lineno);
              }
            });
            
            ['log','info','warn','error'].forEach(level => {
              const orig = console[level];
              console[level] = function(){
                const args = [...arguments];
                const message = args.map(String).join(' ');
                
                // Log API availability for debugging
                if (level === 'error' && (message.includes('chrome') || message.includes('browser'))) {
                  args.push('API_DEBUG:', {
                    chrome: typeof window.chrome,
                    browser: typeof window.browser,
                    chromeRuntime: typeof window.chrome?.runtime,
                    browserRuntime: typeof window.browser?.runtime,
                    requestIdleCallback: typeof window.requestIdleCallback,
                    vAPI: typeof window.vAPI
                  });
                }
                
                if (window.webkit?.messageHandlers?.pulseConsole) {
                  window.webkit.messageHandlers.pulseConsole.postMessage({
                    level, args: args.map(String)
                  });
                }
                return orig.apply(console, arguments);
              };
            });
          }
        })();
        """
        let consoleScript = WKUserScript(source: consoleBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(consoleScript)

        // Enhanced storage bridge with proper async response handling
        let storageBridgeScript = """
        (function(){
          if (window.webkit?.messageHandlers?.pulseStorage) {
            console.log('PulseStorageBridge: Initializing enhanced storage bridge');
            
            // Storage operation callbacks and promises
            let storageCallbacks = {};
            let storagePromises = {};
            let callbackId = 0;
            
            // Enhanced storage API implementation
            const createStorageAPI = () => ({
              get: function(keys, callback) {
                return new Promise((resolve, reject) => {
                  const id = ++callbackId;
                  const timeoutId = setTimeout(() => {
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    const result = {};
                    if (callback) callback(result);
                    resolve(result);
                  }, 5000); // 5 second timeout
                  
                  storageCallbacks[id] = function(result) {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback(result);
                    resolve(result);
                  };
                  
                  storagePromises[id] = { resolve, reject, callback };
                  
                  try {
                    window.webkit.messageHandlers.pulseStorage.postMessage({
                      action: 'get',
                      callbackId: id,
                      payload: { keys }
                    });
                  } catch(e) {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    console.log('Storage get error:', e);
                    const result = {};
                    if (callback) callback(result);
                    resolve(result);
                  }
                });
              },
              
              set: function(items, callback) {
                return new Promise((resolve, reject) => {
                  const id = ++callbackId;
                  const timeoutId = setTimeout(() => {
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  }, 5000);
                  
                  storageCallbacks[id] = function() {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  };
                  
                  storagePromises[id] = { resolve, reject, callback };
                  
                  try {
                    window.webkit.messageHandlers.pulseStorage.postMessage({
                      action: 'set',
                      callbackId: id,
                      payload: { items }
                    });
                  } catch(e) {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    console.log('Storage set error:', e);
                    if (callback) callback();
                    resolve();
                  }
                });
              },
              
              remove: function(keys, callback) {
                return new Promise((resolve, reject) => {
                  const id = ++callbackId;
                  const timeoutId = setTimeout(() => {
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  }, 5000);
                  
                  storageCallbacks[id] = function() {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  };
                  
                  storagePromises[id] = { resolve, reject, callback };
                  
                  try {
                    window.webkit.messageHandlers.pulseStorage.postMessage({
                      action: 'remove',
                      callbackId: id,
                      payload: { keys }
                    });
                  } catch(e) {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    console.log('Storage remove error:', e);
                    if (callback) callback();
                    resolve();
                  }
                });
              },
              
              clear: function(callback) {
                return new Promise((resolve, reject) => {
                  const id = ++callbackId;
                  const timeoutId = setTimeout(() => {
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  }, 5000);
                  
                  storageCallbacks[id] = function() {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    if (callback) callback();
                    resolve();
                  };
                  
                  storagePromises[id] = { resolve, reject, callback };
                  
                  try {
                    window.webkit.messageHandlers.pulseStorage.postMessage({
                      action: 'clear',
                      callbackId: id,
                      payload: {}
                    });
                  } catch(e) {
                    clearTimeout(timeoutId);
                    delete storageCallbacks[id];
                    delete storagePromises[id];
                    console.log('Storage clear error:', e);
                    if (callback) callback();
                    resolve();
                  }
                });
              },
              
              getBytesInUse: function(keys, callback) {
                // Estimated implementation
                return this.get(keys).then(items => {
                  const size = JSON.stringify(items).length;
                  if (callback) callback(size);
                  return size;
                });
              }
            });
            
            // Global response handler for storage operations
            window.__pulseStorageResponse = function(callbackId, result, error) {
              if (storageCallbacks[callbackId]) {
                if (error) {
                  console.error('Storage operation error:', error);
                }
                storageCallbacks[callbackId](result);
              }
            };
            
            // Storage change listener support
            if (!window.__pulseStorageChanged) {
              window.__pulseStorageChanged = function(changes, area) {
                if (chrome.storage && chrome.storage.onChanged) {
                  try {
                    chrome.storage.onChanged.dispatch(changes, area);
                  } catch(e) {
                    console.log('Storage change dispatch error:', e);
                  }
                }
              };
            }
            
            // Replace chrome.storage with enhanced implementation
            const enhancedAPI = createStorageAPI();
            chrome.storage.local = enhancedAPI;
            chrome.storage.sync = enhancedAPI;
            
            console.log('PulseStorageBridge: Enhanced storage API installed');
          }
        })();
        """
        let storageScript = WKUserScript(source: storageBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(storageScript)

        // Minimal CSS reset
        let cssFixScript = """
        (function(){
          const style = document.createElement('style');
          style.textContent = 'html, body { margin: 0; padding: 0; }';
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        
        let cssScript = WKUserScript(source: cssFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(cssScript)
        
        // Auto-resize popup observer
        let sizeObserverScript = """
        (function(){
          const clamp=(v,min,max)=>Math.max(min,Math.min(max,v));
          const send = () => {
            const de=document.documentElement; const b=document.body||de;
            const w=Math.max(de.scrollWidth, b.scrollWidth, de.offsetWidth, b.offsetWidth);
            const h=Math.max(de.scrollHeight, b.scrollHeight, de.offsetHeight, b.offsetHeight);
            const width=clamp(w,25,800), height=clamp(h,25,600);
            if (window.webkit?.messageHandlers?.pulsePopupSize) {
              window.webkit.messageHandlers.pulsePopupSize.postMessage({width, height});
            }
          };
          if (window.ResizeObserver) {
            new ResizeObserver(send).observe(document.documentElement);
          }
          window.addEventListener('load', ()=> setTimeout(send, 0));
          document.addEventListener('DOMContentLoaded', ()=> setTimeout(send, 0), { once: true });
          setTimeout(send, 250);
        })();
        """
        let sizeScript = WKUserScript(source: sizeObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(sizeScript)

        // Basic DOM ready and visibility fixes
        let domReadyScript = """
        document.addEventListener('DOMContentLoaded', function() {
            if (document.body) {
                document.body.style.visibility = 'visible';
                document.body.style.opacity = '1';
                document.body.classList.remove('loading', 'preload');
            }
        });
        """
        
        let domScript = WKUserScript(source: domReadyScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(domScript)
        
        configuration.userContentController = contentController
        
        // Register custom scheme handlers to emulate extension origins
        let schemeHandler = MultiExtensionSchemeHandler()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "chrome-extension")
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "moz-extension")

        // Set up extension-specific configuration
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        // Expose to parent so header buttons (Inspect) can access and attach console bridge
        DispatchQueue.main.async {
            self.webView = webView
            PopupConsole.shared.attach(to: webView)
        }
        // Expose to parent so header buttons (Inspect) can access
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        // Debug info moved to logManifestDebugging() method
        
        // Load the extension popup page via chrome-extension:// scheme
        if let popupPage = getPopupPageForWebView() {
            // Double-check file existence before loading
            if validatePopupFileExistsForWebView(popupPage) {
                // Construct and validate the chrome-extension URL
                let cleanPage = popupPage.hasPrefix("/") ? String(popupPage.dropFirst()) : popupPage
                let urlString = "chrome-extension://\(ext.id)/\(cleanPage)"
                
                if let popupURL = URL(string: urlString) {
                    print("Loading extension popup: \(popupURL)")
                    let request = URLRequest(url: popupURL, timeoutInterval: 15.0)
                    webView.load(request)
                } else {
                    print("ERROR: Failed to construct chrome-extension URL for popup: \(popupPage)")
                    loadFallbackContent(webView: webView)
                }
            } else {
                print("ERROR: Popup file no longer exists: \(popupPage)")
                loadFallbackContent(webView: webView)
            }
        } else {
            print("WARNING: No popup page found for extension: \(ext.name)")
            loadFallbackContent(webView: webView)
        }
        
        // Avoid mutating SwiftUI state during view creation
        return webView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: ExtensionWebView
        private var ports: [String: String] = [:]
        
        init(_ parent: ExtensionWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Extension popup loaded successfully")
            parent.requestContentSize(webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("ERROR: Extension popup failed to load: \(error.localizedDescription)")
            print("Extension: \(parent.ext.name) (\(parent.ext.id))")
            
            // Log additional debugging information
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
                
                // Provide helpful context for common errors
                switch nsError.code {
                case -1003: // NSURLErrorCannotFindHost
                    print("CONTEXT: Cannot find host - likely chrome-extension:// scheme handler issue")
                case -1002: // NSURLErrorUnsupportedURL
                    print("CONTEXT: Unsupported URL - chrome-extension:// scheme may not be registered")
                case -1100: // NSURLErrorFileDoesNotExist
                    print("CONTEXT: File does not exist - popup HTML file not found")
                case -1101: // NSURLErrorFileIsDirectory
                    print("CONTEXT: Expected file but found directory")
                default:
                    if let userInfo = nsError.userInfo as? [String: Any] {
                        print("Error userInfo: \(userInfo)")
                    }
                }
            }
            
            // Attempt to retry with fallback popup detection
            retryWithFallbackDetection(webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("ERROR: Extension popup provisional navigation failed: \(error.localizedDescription)")
            print("Extension: \(parent.ext.name) (\(parent.ext.id))")
            
            // Log URL that failed to load
            if let failingURL = webView.url {
                print("Failed URL: \(failingURL)")
            }
            
            retryWithFallbackDetection(webView: webView)
        }
        
        private func retryWithFallbackDetection(webView: WKWebView) {
            // Try one more time to find a valid popup file
            if let fallbackPopup = parent.getPopupPageForRetry() {
                let cleanPage = fallbackPopup.hasPrefix("/") ? String(fallbackPopup.dropFirst()) : fallbackPopup
                let urlString = "chrome-extension://\(parent.ext.id)/\(cleanPage)"
                
                if let popupURL = URL(string: urlString) {
                    print("Retrying with fallback popup: \(popupURL)")
                    let request = URLRequest(url: popupURL, timeoutInterval: 10.0)
                    webView.load(request)
                    return
                }
            }
            
            // If all else fails, load fallback content
            parent.loadFallbackContent(webView: webView)
        }

        // Handle size logs and runtime bridges
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pulsePopupSize" {
                if let dict = message.body as? [String: Any] {
                    let w = (dict["width"] as? CGFloat) ?? 0
                    let h = (dict["height"] as? CGFloat) ?? 0
                    if w > 0 && h > 0 {
                        DispatchQueue.main.async {
                            self.parent.onSizeChange?(CGSize(width: w, height: h))
                        }
                    }
                }
            } else if message.name == "pulseConsole" {
                if let dict = message.body as? [String: Any], let level = dict["level"] as? String, let args = dict["args"] as? [String] {
                    let line = "POPUP CONSOLE [\(level)]: \(args.joined(separator: " "))"
                    print(line)
                    PopupConsole.shared.log(line)
                }
            } else if message.name == "pulseRuntime" {
                guard let dict = message.body as? [String: Any], let action = dict["action"] as? String, action == "sendMessage", let payload = dict["payload"] as? [String: Any], let reqId = payload["id"] as? String else { return }
                let resp = handleRuntimeMessage(message: payload["message"])
                respondToMessage(webView: message.webView, id: reqId, response: resp)
            } else if message.name == "pulsePort" {
                guard let dict = message.body as? [String: Any], let action = dict["action"] as? String else { return }
                switch action {
                case "portOpen":
                    if let portId = dict["portId"] as? String, let name = dict["name"] as? String { ports[portId] = name; deliverPortMessage(webView: message.webView, portId: portId, message: ["hello": true]) }
                case "portMessage":
                    if let portId = dict["portId"] as? String { deliverPortMessage(webView: message.webView, portId: portId, message: ["ok": true]) }
                case "portDisconnect":
                    if let portId = dict["portId"] as? String { ports.removeValue(forKey: portId) }
                default: break
                }
            } else if message.name == "pulseStorage" {
                guard let dict = message.body as? [String: Any], 
                      let action = dict["action"] as? String,
                      let callbackId = dict["callbackId"] else { return }
                
                let payload = dict["payload"] as? [String: Any] ?? [:]
                let mgr = BrowserWindowManager.shared.browserManager?.extensionManager
                var result: Any = [:]
                var error: String? = nil
                
                switch action {
                case "get":
                    result = mgr?.handlePopupRuntimeMessage(extensionId: parent.ext.id, message: ["what": "storageGet", "keys": payload["keys"] as Any]) ?? [:]
                case "set":
                    _ = mgr?.handlePopupRuntimeMessage(extensionId: parent.ext.id, message: ["what": "storageSet", "items": payload["items"] as Any])
                    result = ["success": true]
                case "remove":
                    _ = mgr?.handlePopupRuntimeMessage(extensionId: parent.ext.id, message: ["what": "storageRemove", "keys": payload["keys"] as Any])
                    result = ["success": true]
                case "clear":
                    _ = mgr?.handlePopupRuntimeMessage(extensionId: parent.ext.id, message: ["what": "storageClear"]) 
                    result = ["success": true]
                default:
                    error = "Unknown storage action: \(action)"
                    result = [:]
                }
                
                // Call the response handler with proper parameters
                if let webView = message.webView {
                    let callbackIdJson = try? JSONSerialization.data(withJSONObject: callbackId, options: [])
                    let resultJson = try? JSONSerialization.data(withJSONObject: result, options: [])
                    let errorJson = error != nil ? try? JSONSerialization.data(withJSONObject: error!, options: []) : nil
                    
                    if let callbackIdStr = callbackIdJson.flatMap({ String(data: $0, encoding: .utf8) }),
                       let resultStr = resultJson.flatMap({ String(data: $0, encoding: .utf8) }) {
                        let errorStr = errorJson.flatMap({ String(data: $0, encoding: .utf8) }) ?? "null"
                        let js = "window.__pulseStorageResponse(\(callbackIdStr), \(resultStr), \(errorStr));"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            }
        }

        private func respondToMessage(webView: WKWebView?, id: String, response: Any) {
            guard let webView = webView else { return }
            if let data = try? JSONSerialization.data(withJSONObject: ["id": id, "response": response], options: []), let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.__pulseDispatchMessageResponse(\(json));", completionHandler: nil)
            }
        }

        private func deliverPortMessage(webView: WKWebView?, portId: String, message: Any) {
            guard let webView = webView else { return }
            if let data = try? JSONSerialization.data(withJSONObject: ["portId": portId, "message": message], options: []), let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.__pulseDeliverPortMessage(\(json));", completionHandler: nil)
            }
        }

        private func handleRuntimeMessage(message: Any?) -> Any {
            if let mgr = BrowserWindowManager.shared.browserManager?.extensionManager {
                return mgr.handlePopupRuntimeMessage(extensionId: parent.ext.id, message: message)
            }
            return ["success": true]
        }

        // Note: didReceive is implemented above; removed duplicate to avoid conflicts
    }
    
    private func loadFallbackContent(webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    padding: 16px; 
                    margin: 0;
                    background: white;
                    min-width: 200px;
                    max-width: 400px;
                }
                .header { 
                    display: flex; 
                    align-items: center; 
                    margin-bottom: 16px; 
                }
                .icon { 
                    width: 32px; 
                    height: 32px; 
                    margin-right: 12px;
                    background: linear-gradient(135deg, #007AFF, #5856D6);
                    border-radius: 8px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: white;
                    font-weight: bold;
                    font-size: 16px;
                }
                .title { font-weight: 600; font-size: 16px; color: #1d1d1f; }
                .version { color: #86868b; font-size: 13px; margin-top: 2px; }
                .status { 
                    color: #666; 
                    font-size: 14px; 
                    line-height: 1.4;
                    padding: 12px;
                    background: #f5f5f7;
                    border-radius: 8px;
                    margin-top: 8px;
                }
                .status-icon {
                    display: inline-block;
                    width: 16px;
                    height: 16px;
                    background: #34c759;
                    border-radius: 50%;
                    margin-right: 8px;
                    position: relative;
                    top: 2px;
                }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="icon">\(String(ext.name.prefix(1)).uppercased())</div>
                <div>
                    <div class="title">\(ext.name)</div>
                    <div class="version">v\(ext.version)</div>
                </div>
            </div>
            <div class="status">
                <span class="status-icon"></span>
                Extension is active and running.<br>
                No popup interface available for this extension.
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Measure content size via JS (fallback) and send through onSizeChange
    private func requestContentSize(_ webView: WKWebView) {
        let sizeScript = """
        (function(){
          const clamp=(v,min,max)=>Math.max(min,Math.min(max,v));
          const de=document.documentElement; const b=document.body||de;
          const w=Math.max(de.scrollWidth, b.scrollWidth, de.offsetWidth, b.offsetWidth);
          const h=Math.max(de.scrollHeight, b.scrollHeight, de.offsetHeight, b.offsetHeight);
          ({w:clamp(w,25,800), h:clamp(h,25,600)});
        })();
        """
        webView.evaluateJavaScript(sizeScript) { result, _ in
            if let dict = result as? [String: Any] {
                let w = (dict["w"] as? CGFloat) ?? 0
                let h = (dict["h"] as? CGFloat) ?? 0
                if w > 0 && h > 0 {
                    self.onSizeChange?(CGSize(width: w, height: h))
                }
            }
        }
    }
    
    private func manifestJSON() -> String {
        do {
            let manifestData = try JSONSerialization.data(withJSONObject: ext.manifest, options: [])
            return String(data: manifestData, encoding: .utf8) ?? "{}"
        } catch {
            print("Failed to serialize manifest: \(error)")
            return "{}"
        }
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Update if needed
    }
    
    private func logManifestDebugging() {
        print("=== Extension Manifest Debug Info ===")
        print("Extension: \(ext.name) (ID: \(ext.id))")
        print("Manifest keys: \(Array(ext.manifest.keys).sorted())")
        
        if let action = ext.manifest["action"] as? [String: Any] {
            print("Action manifest: \(action)")
        }
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            print("Browser action manifest: \(browserAction)")
        }
        
        logAvailableFiles()
        print("=== End Debug Info ===")
    }
    
    private func logAvailableFiles() {
        let extensionDir = URL(fileURLWithPath: ext.packagePath)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: extensionDir, includingPropertiesForKeys: nil)
            let htmlFiles = files.filter { $0.pathExtension.lowercased() == "html" }
            print("Available HTML files: \(htmlFiles.map { $0.lastPathComponent })")
            
            // Look for common directories
            let directories = files.filter { $0.hasDirectoryPath }
            print("Available directories: \(directories.map { $0.lastPathComponent })")
        } catch {
            print("ERROR: Could not list extension files: \(error)")
        }
    }
    
    // Duplicate helper methods for coordinator use
    private func getPopupPageForRetry() -> String? {
        // Check for popup in action (Manifest V3)
        if let action = ext.manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String, !popup.isEmpty {
                if validatePopupFileExistsForRetry(popup) {
                    return popup
                }
            }
        }
        
        // Check for popup in browser_action (Manifest V2)  
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            if let popup = browserAction["default_popup"] as? String, !popup.isEmpty {
                if validatePopupFileExistsForRetry(popup) {
                    return popup
                }
            }
        }
        
        return searchForPopupFileForRetry()
    }
    
    private func searchForPopupFileForRetry() -> String? {
        let extensionDir = URL(fileURLWithPath: ext.packagePath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: extensionDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            let popupKeywords = ["popup", "action", "browser", "main", "index"]
            let htmlFiles = files.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".html") && popupKeywords.contains { name.contains($0) }
            }
            
            for file in htmlFiles {
                let relativePath = String(file.path.dropFirst(extensionDir.path.count + 1))
                if file.lastPathComponent.lowercased().contains("popup") {
                    if validatePopupFileExistsForRetry(relativePath) {
                        return relativePath
                    }
                }
            }
        } catch {
            print("ERROR: Could not search for popup files during retry: \(error)")
        }
        
        return nil
    }
    
    private func validatePopupFileExistsForRetry(_ popupPath: String) -> Bool {
        guard !popupPath.isEmpty else { return false }
        
        var cleanPath = popupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("/") { cleanPath.removeFirst() }
        
        let components = cleanPath.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePath = safeComponents.joined(separator: "/")
        
        guard !safePath.isEmpty else { return false }
        
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let popupURL = extensionURL.appendingPathComponent(safePath)
        
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: popupURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    
    // Additional methods needed for ExtensionWebView
    private func getPopupPageForWebView() -> String? {
        // Check for popup in action (Manifest V3)
        if let action = ext.manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String, !popup.isEmpty {
                if let validatedPopup = validatePopupFileForWebView(popup) {
                    print("Found valid V3 action popup: \(validatedPopup)")
                    return validatedPopup
                } else {
                    print("WARNING: V3 action popup '\(popup)' specified in manifest but file not found")
                }
            }
        }
        
        // Check for popup in browser_action (Manifest V2)
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            if let popup = browserAction["default_popup"] as? String, !popup.isEmpty {
                if let validatedPopup = validatePopupFileForWebView(popup) {
                    print("Found valid V2 browser_action popup: \(validatedPopup)")
                    return validatedPopup
                } else {
                    print("WARNING: V2 browser_action popup '\(popup)' specified in manifest but file not found")
                }
            }
        }
        
        // Enhanced fallback: Look for common popup file names in more locations
        let commonPopupFiles = [
            "popup.html", "popup/popup.html", "popup/index.html",
            "src/popup.html", "src/popup/popup.html", "src/popup/index.html",
            "ui/popup.html", "ui/popup/popup.html", "ui/popup/index.html",
            "pages/popup.html", "html/popup.html", "web/popup.html",
            "extension/popup.html", "browser/popup.html"
        ]
        
        for fileName in commonPopupFiles {
            if let validatedPopup = validatePopupFileForWebView(fileName) {
                print("Found fallback popup file: \(validatedPopup)")
                return validatedPopup
            }
        }
        
        // Final attempt: Search extension directory for any HTML file that might be a popup
        if let discoveredPopup = searchForPopupFileForWebView() {
            print("Discovered potential popup file: \(discoveredPopup)")
            return discoveredPopup
        }
        
        print("No popup page found for extension: \(ext.name)")
        return nil
    }
    
    private func validatePopupFileExistsForWebView(_ popupPath: String) -> Bool {
        guard !popupPath.isEmpty else { return false }
        
        // Clean up the path
        var cleanPath = popupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("/") {
            cleanPath.removeFirst()
        }
        
        // Validate path components for security
        let components = cleanPath.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePath = safeComponents.joined(separator: "/")
        
        guard !safePath.isEmpty else { return false }
        
        // Check if the file exists
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let popupURL = extensionURL.appendingPathComponent(safePath)
        
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: popupURL.path, isDirectory: &isDirectory)
        
        return fileExists && !isDirectory.boolValue
    }
    
    private func validatePopupFileForWebView(_ popupPath: String) -> String? {
        guard !popupPath.isEmpty else {
            return nil
        }
        
        // Clean up the path and prevent directory traversal
        var cleanPath = popupPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.hasPrefix("/") {
            cleanPath.removeFirst()
        }
        
        // Validate path components for security
        let components = cleanPath.components(separatedBy: "/")
        let safeComponents = components.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let safePath = safeComponents.joined(separator: "/")
        
        guard !safePath.isEmpty else {
            return nil
        }
        
        // Check if the popup file exists
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        let popupURL = extensionURL.appendingPathComponent(safePath)
        
        // Verify the file exists and is readable
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: popupURL.path, isDirectory: &isDirectory)
        
        if !fileExists || isDirectory.boolValue {
            return nil
        }
        
        // Additional validation: ensure it's an HTML file
        let allowedExtensions = ["html", "htm"]
        let fileExtension = popupURL.pathExtension.lowercased()
        if !allowedExtensions.contains(fileExtension) {
            return nil
        }
        
        return safePath
    }
    
    private func searchForPopupFileForWebView() -> String? {
        let extensionDir = URL(fileURLWithPath: ext.packagePath)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: extensionDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Look for HTML files that might be popups based on naming
            let popupKeywords = ["popup", "action", "browser", "main", "index"]
            let htmlFiles = files.filter { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasSuffix(".html") && popupKeywords.contains { name.contains($0) }
            }
            
            // Prefer files with "popup" in the name
            for file in htmlFiles {
                let relativePath = String(file.path.dropFirst(extensionDir.path.count + 1))
                if file.lastPathComponent.lowercased().contains("popup") {
                    if validatePopupFileForWebView(relativePath) != nil {
                        return relativePath
                    }
                }
            }
            
            // Fall back to any matching HTML file
            for file in htmlFiles {
                let relativePath = String(file.path.dropFirst(extensionDir.path.count + 1))
                if validatePopupFileForWebView(relativePath) != nil {
                    return relativePath
                }
            }
        } catch {
            print("ERROR: Could not search for popup files: \(error)")
        }
        
        return nil
    }
}
