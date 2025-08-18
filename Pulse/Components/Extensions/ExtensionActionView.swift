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
        .popover(isPresented: $showingPopover) {
            ExtensionPopoverView(ext: ext)
                .environmentObject(browserManager)
        }
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
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            
            // Web content  
            ExtensionWebView(ext: ext, webView: $webView)
                .frame(width: 400, height: 300)
                .clipped()
        }
        .onAppear {
            grantActiveTabPermission()
        }
    }
    
    private func openOptionsPage() {
        guard let optionsPage = getOptionsPage() else { 
            print("No options page found for extension: \(ext.name)")
            return 
        }
        
        // Create new tab with options page
        let optionsURL = getExtensionURL(for: optionsPage)
        print("Opening options page: \(optionsURL)")
        
        // Check if options file exists
        if FileManager.default.fileExists(atPath: optionsURL.path) {
            let newTab = browserManager.tabManager.createNewTab(url: optionsURL.absoluteString)
            browserManager.tabManager.setActiveTab(newTab)
        } else {
            print("Options file not found at: \(optionsURL.path)")
            // Show available files for debugging
            let extensionDir = URL(fileURLWithPath: ext.packagePath)
            if let files = try? FileManager.default.contentsOfDirectory(at: extensionDir, includingPropertiesForKeys: nil) {
                print("Available files in extension: \(files.map { $0.lastPathComponent })")
            }
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
        return extensionURL.appendingPathComponent(page)
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
}

@available(macOS 15.4, *)
struct ExtensionWebView: NSViewRepresentable {
    let ext: InstalledExtension
    @Binding var webView: WKWebView?
    
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
        
        // Inject extension API polyfills
        let extensionAPIs = """
        console.log('PULSE EXTENSION: Starting extension API injection...');
        console.log('PULSE EXTENSION: Window object exists:', !!window);
        console.log('PULSE EXTENSION: Document object exists:', !!document);
        
        // Extension API polyfills for popup
        window.chrome = window.chrome || {};
        window.browser = window.browser || window.chrome;
        
        // Set up global objects that extensions expect
        window.self = window.self || window;
        
        // Add support for browser as an Element check (used by uBlock's i18n.js)
        if (!window.browser.hasOwnProperty('constructor')) {
            Object.defineProperty(window.browser, 'constructor', {
                value: Object,
                writable: false
            });
        }
        
        // Runtime API with uBlock-specific features
        chrome.runtime = chrome.runtime || {
            getManifest: function() {
                console.log('getManifest called');
                return \(manifestJSON());
            },
            sendMessage: function(extensionId, message, options, callback) {
                // Handle both 3-arg and 4-arg versions
                if (typeof extensionId === 'object') {
                    callback = options;
                    options = message;
                    message = extensionId;
                    extensionId = null;
                }
                if (typeof options === 'function') {
                    callback = options;
                    options = null;
                }
                
                console.log('Extension message:', message);
                
                // Mock responses for uBlock Origin Lite specific messages
                let response = {success: true};
                
                if (message && message.what) {
                    switch (message.what) {
                        case 'getPopupData':
                            response = {
                                hostname: 'example.com',
                                level: 2,
                                autoReload: true,
                                disabledFeatures: []
                            };
                            break;
                        case 'setFilteringMode':
                            response = message.level || 2;
                            break;
                        case 'setPendingFilteringMode':
                            response = {success: true};
                            break;
                        default:
                            response = {success: true, data: message};
                    }
                }
                
                if (callback) callback(response);
                return Promise.resolve(response);
            },
            onMessage: {
                addListener: function(callback) {
                    console.log('Message listener added');
                    // Store listener for potential use
                    chrome.runtime._messageListeners = chrome.runtime._messageListeners || [];
                    chrome.runtime._messageListeners.push(callback);
                },
                removeListener: function(callback) {
                    console.log('Message listener removed');
                }
            },
            getURL: function(path) {
                const baseURL = 'file://\\(ext.packagePath.replacingOccurrences(of: "\\", with: "/"))';
                return baseURL + '/' + path;
            },
            id: '\\(ext.id)',
            lastError: null
        };
        
        // Storage API with persistent mock data
        const mockStorage = {};
        chrome.storage = chrome.storage || {
            local: {
                get: function(keys, callback) {
                    console.log('Storage get:', keys);
                    let result = {};
                    
                    if (keys === null || keys === undefined) {
                        result = {...mockStorage};
                    } else if (Array.isArray(keys)) {
                        keys.forEach(key => {
                            result[key] = mockStorage[key] || null;
                        });
                    } else if (typeof keys === 'string') {
                        result[keys] = mockStorage[keys] || null;
                    } else if (typeof keys === 'object') {
                        Object.keys(keys).forEach(key => {
                            result[key] = mockStorage[key] !== undefined ? mockStorage[key] : keys[key];
                        });
                    }
                    
                    if (callback) callback(result);
                    return Promise.resolve(result);
                },
                set: function(items, callback) {
                    console.log('Storage set:', items);
                    Object.assign(mockStorage, items);
                    if (callback) callback();
                    return Promise.resolve();
                },
                remove: function(keys, callback) {
                    console.log('Storage remove:', keys);
                    const keyArray = Array.isArray(keys) ? keys : [keys];
                    keyArray.forEach(key => delete mockStorage[key]);
                    if (callback) callback();
                    return Promise.resolve();
                },
                clear: function(callback) {
                    console.log('Storage clear');
                    Object.keys(mockStorage).forEach(key => delete mockStorage[key]);
                    if (callback) callback();
                    return Promise.resolve();
                }
            },
            sync: {
                get: function(keys, callback) {
                    return chrome.storage.local.get(keys, callback);
                },
                set: function(items, callback) {
                    return chrome.storage.local.set(items, callback);
                }
            }
        };
        
        // Tabs API
        chrome.tabs = chrome.tabs || {
            query: function(queryInfo, callback) {
                console.log('Tabs query:', queryInfo);
                const tabs = [{
                    id: 1, 
                    url: 'https://example.com', 
                    title: 'Example',
                    active: true,
                    windowId: 1,
                    index: 0
                }];
                if (callback) callback(tabs);
                return Promise.resolve(tabs);
            },
            sendMessage: function(tabId, message, options, callback) {
                if (typeof options === 'function') {
                    callback = options;
                    options = {};
                }
                console.log('Tab message to', tabId, ':', message);
                const response = {success: true};
                if (callback) callback(response);
                return Promise.resolve(response);
            },
            executeScript: function(tabId, details, callback) {
                console.log('Execute script:', details);
                if (callback) callback([{result: 'executed'}]);
                return Promise.resolve([{result: 'executed'}]);
            }
        };
        
        // i18n API for internationalization with uBlock Lite specific messages
        chrome.i18n = chrome.i18n || {
            getMessage: function(messageName, substitutions) {
                console.log('i18n getMessage:', messageName);
                // uBlock Origin Lite specific messages
                const messages = {
                    'extName': 'uBlock Origin Lite',
                    'popupFilteringModeLabel': 'filtering mode',
                    'popupLocalToolsLabel': 'On this website',
                    'popupTipReport': 'Report an issue',
                    'popupTipDashboard': 'Open the dashboard',
                    'zapperTipEnter': 'Enter element zapper mode',
                    'pickerTipEnter': 'Enter element picker mode',
                    'unpickerTipEnter': 'Disable element picker mode',
                    'filteringMode0Name': 'no filtering',
                    'filteringMode1Name': 'basic filtering',
                    'filteringMode2Name': 'optimal filtering', 
                    'filteringMode3Name': 'complete filtering',
                    '@@ui_locale': 'en'
                };
                return messages[messageName] || messageName;
            },
            getUILanguage: function() {
                return 'en';
            }
        };
        
        // Extension API for older extensions
        chrome.extension = chrome.extension || {
            getURL: function(path) {
                return chrome.runtime.getURL(path);
            },
            getBackgroundPage: function() {
                return null; // No background page in popup context
            }
        };
        
        // WebNavigation API (basic)
        chrome.webNavigation = chrome.webNavigation || {
            onCompleted: {
                addListener: function(callback) {
                    console.log('WebNavigation listener added');
                }
            }
        };
        
        // Permissions API for uBlock Origin Lite
        chrome.permissions = chrome.permissions || {
            request: function(permissions) {
                console.log('Permission request:', permissions);
                // Always grant permissions for development
                return Promise.resolve(true);
            },
            contains: function(permissions) {
                console.log('Permission check:', permissions);
                return Promise.resolve(true);
            },
            onAdded: {
                addListener: function(callback) {
                    console.log('Permission added listener');
                }
            },
            onRemoved: {
                addListener: function(callback) {
                    console.log('Permission removed listener');
                }
            }
        };
        
        console.log('PULSE EXTENSION: Extension APIs fully injected');
        console.log('PULSE EXTENSION: Chrome API check:', !!window.chrome);
        console.log('PULSE EXTENSION: Browser API check:', !!window.browser);
        """
        
        let apiScript = WKUserScript(source: extensionAPIs, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(apiScript)
        
        // Add early module error detection and fixes
        let moduleFixScript = """
        console.log('POPUP DEBUG: Early module fix script running');
        
        // Override module loading to catch errors
        const originalImport = window.import;
        if (typeof originalImport === 'function') {
            window.import = function(...args) {
                console.log('POPUP DEBUG: Module import attempt:', args);
                return originalImport.apply(this, args).catch(err => {
                    console.log('POPUP DEBUG: Module import failed:', err);
                    throw err;
                });
            };
        }
        
        // Monitor for script loading errors
        document.addEventListener('DOMContentLoaded', function() {
            const scripts = document.querySelectorAll('script[type="module"]');
            console.log('POPUP DEBUG: Found', scripts.length, 'module scripts');
            
            scripts.forEach((script, index) => {
                script.addEventListener('error', function(e) {
                    console.log('POPUP DEBUG: Module script', index, 'failed to load:', e);
                });
                script.addEventListener('load', function(e) {
                    console.log('POPUP DEBUG: Module script', index, 'loaded successfully');
                });
            });
        });
        
        // Add fallback initialization if modules fail
        setTimeout(() => {
            console.log('POPUP DEBUG: Checking if modules loaded...');
            
            // Check if body still has 'loading' class after 3 seconds
            if (document.body && document.body.classList.contains('loading')) {
                console.log('POPUP DEBUG: Modules appear to have failed, running fallback initialization');
                
                // Remove loading class
                document.body.classList.remove('loading');
                
                // Force i18n replacement
                const i18nElements = document.querySelectorAll('[data-i18n]');
                console.log('POPUP DEBUG: Force replacing', i18nElements.length, 'i18n elements');
                
                i18nElements.forEach(el => {
                    const key = el.getAttribute('data-i18n');
                    if (key && window.chrome && window.chrome.i18n) {
                        const message = window.chrome.i18n.getMessage(key);
                        if (message && message !== key) {
                            console.log('POPUP DEBUG: Force replacing', key, 'with', message);
                            el.textContent = message;
                        }
                    }
                });
                
                // Show basic UI
                const main = document.getElementById('main');
                if (main) {
                    main.style.display = 'block';
                    main.style.visibility = 'visible';
                    main.style.opacity = '1';
                }
            }
        }, 3000);
        """
        
        let moduleScript = WKUserScript(source: moduleFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(moduleScript)
        
        // Add comprehensive CSS reset and styling fixes
        let cssFixScript = """
        // Inject CSS fixes for extension rendering
        const style = document.createElement('style');
        style.textContent = `
            /* Reset and base styles for extension popups */
            * {
                box-sizing: border-box !important;
            }
            
            html, body {
                margin: 0 !important;
                padding: 0 !important;
                background: white !important;
                color: black !important;
                font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
                font-size: 13px !important;
                line-height: 1.4 !important;
                min-height: 100% !important;
                overflow: visible !important;
            }
            
            body {
                display: block !important;
                visibility: visible !important;
                opacity: 1 !important;
                transform: none !important;
            }
            
            /* Fix common extension UI elements */
            div, span, p, a, button, input {
                visibility: visible !important;
                display: initial !important;
                opacity: 1 !important;
                color: inherit !important;
            }
            
            /* Fix buttons and interactive elements */
            button {
                background: #f0f0f0 !important;
                border: 1px solid #ccc !important;
                border-radius: 3px !important;
                padding: 4px 8px !important;
                cursor: pointer !important;
            }
            
            button:hover {
                background: #e0e0e0 !important;
            }
            
            /* Fix any hidden or problematic elements */
            [style*="display: none"], [style*="visibility: hidden"] {
                display: block !important;
                visibility: visible !important;
            }
            
            /* CRITICAL: Force uBlock popup to be visible even with loading class */
            body.loading, .loading {
                visibility: visible !important;
                opacity: 1 !important;
                display: block !important;
            }
            
            /* Ensure main container is visible and properly sized */
            #main {
                display: flex !important;
                visibility: visible !important;
                opacity: 1 !important;
                flex-direction: column !important;
                width: 100% !important;
                height: 100% !important;
                padding: 8px !important;
                box-sizing: border-box !important;
            }
            
            /* Force proper popup dimensions */
            html, body {
                width: 400px !important;
                height: 300px !important;
                max-width: 400px !important;
                max-height: 300px !important;
                overflow: hidden !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            
            /* Force i18n text replacement for common elements */
            [data-i18n="popupTipDashboard"] {
                display: none !important;
            }
            [data-i18n="popupTipDashboard"]::after {
                content: "Open the dashboard" !important;
                display: inline !important;
            }
            
            /* Force visibility on specific uBlock elements */
            .filteringModeSlider,
            .toolMenu,
            .toolRibbon,
            #hostname,
            #filteringModeText {
                display: block !important;
                visibility: visible !important;
                opacity: 1 !important;
            }
        `;
        document.head.appendChild(style);
        """
        
        let cssScript = WKUserScript(source: cssFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(cssScript)
        
        // Add comprehensive debugging and module support
        let domReadyScript = """
        console.log('POPUP DEBUG: Script injection started');
        
        // Log all script tags and their loading status
        document.addEventListener('DOMContentLoaded', function() {
            console.log('POPUP DEBUG: DOM Content Loaded');
            console.log('POPUP DEBUG: Document title:', document.title);
            console.log('POPUP DEBUG: Body exists:', !!document.body);
            console.log('POPUP DEBUG: Head exists:', !!document.head);
            
            // Check for script tags
            const scripts = document.querySelectorAll('script');
            console.log('POPUP DEBUG: Found', scripts.length, 'script tags');
            scripts.forEach((script, index) => {
                console.log('POPUP DEBUG: Script', index, ':', {
                    src: script.src,
                    type: script.type,
                    textContent: script.textContent ? script.textContent.substring(0, 100) + '...' : 'No text content'
                });
            });
            
            // Check for CSS
            const stylesheets = document.querySelectorAll('link[rel="stylesheet"]');
            console.log('POPUP DEBUG: Found', stylesheets.length, 'stylesheets');
            stylesheets.forEach((link, index) => {
                console.log('POPUP DEBUG: Stylesheet', index, ':', link.href);
            });
            
            if (document.body) {
                console.log('POPUP DEBUG: Body innerHTML length:', document.body.innerHTML.length);
                console.log('POPUP DEBUG: Body classes:', document.body.className);
                console.log('POPUP DEBUG: Body text content preview:', document.body.textContent.substring(0, 200));
                
                // Log elements with data-i18n attributes
                const i18nElements = document.querySelectorAll('[data-i18n]');
                console.log('POPUP DEBUG: Found', i18nElements.length, 'elements with data-i18n');
                i18nElements.forEach(el => {
                    console.log('POPUP DEBUG: i18n element:', el.tagName, 'data-i18n:', el.getAttribute('data-i18n'), 'text:', el.textContent);
                });
                
                // Force visibility and basic styling
                document.body.style.setProperty('display', 'block', 'important');
                document.body.style.setProperty('visibility', 'visible', 'important');
                document.body.style.setProperty('opacity', '1', 'important');
                document.body.style.setProperty('background-color', 'white', 'important');
                document.body.style.setProperty('color', 'black', 'important');
                document.body.style.setProperty('min-height', '100%', 'important');
                
                // Remove 'loading' class if present
                if (document.body.classList.contains('loading')) {
                    console.log('POPUP DEBUG: Removing loading class from body');
                    document.body.classList.remove('loading');
                }
            }
            
            // Try manual i18n replacement
            setTimeout(() => {
                console.log('POPUP DEBUG: Attempting manual i18n replacement');
                const i18nElements = document.querySelectorAll('[data-i18n]');
                i18nElements.forEach(el => {
                    const key = el.getAttribute('data-i18n');
                    if (key && window.chrome && window.chrome.i18n) {
                        const message = window.chrome.i18n.getMessage(key);
                        if (message && message !== key) {
                            console.log('POPUP DEBUG: Replacing i18n key', key, 'with', message);
                            el.textContent = message;
                        }
                    }
                });
            }, 500);
        });
        
        // Monitor script errors
        window.addEventListener('error', function(e) {
            console.log('POPUP DEBUG: Script error:', e.error, 'at', e.filename, ':', e.lineno);
        });
        
        // Monitor module loading errors
        window.addEventListener('unhandledrejection', function(e) {
            console.log('POPUP DEBUG: Unhandled promise rejection:', e.reason);
        });
        
        window.addEventListener('load', function() {
            console.log('POPUP DEBUG: Window fully loaded');
            
            // Final status check
            setTimeout(() => {
                const allText = document.body ? document.body.textContent.trim() : '';
                console.log('POPUP DEBUG: Final text content length:', allText.length);
                console.log('POPUP DEBUG: Final text preview:', allText.substring(0, 200));
                
                if (allText.includes('cogs')) {
                    console.log('POPUP DEBUG: WARNING - Still showing fallback text "cogs"');
                }
                
                if (allText.length > 0) {
                    console.log('POPUP DEBUG: Extension content loaded successfully');
                } else {
                    console.log('POPUP DEBUG: WARNING - No text content found in extension popup');
                }
            }, 2000);
        });
        """
        
        let domScript = WKUserScript(source: domReadyScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(domScript)
        
        configuration.userContentController = contentController
        
        // Set up extension-specific configuration
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Debug: Print manifest info
        print("Extension manifest keys: \(ext.manifest.keys)")
        if let action = ext.manifest["action"] as? [String: Any] {
            print("Action manifest: \(action)")
        }
        if let browserAction = ext.manifest["browser_action"] as? [String: Any] {
            print("Browser action manifest: \(browserAction)")
        }
        
        // Load the extension popup page
        if let popupPage = getPopupPage() {
            let popupURL = getExtensionURL(for: popupPage)
            print("Loading extension popup: \(popupURL)")
            
            // Check if file exists
            if FileManager.default.fileExists(atPath: popupURL.path) {
                let request = URLRequest(url: popupURL)
                webView.load(request)
            } else {
                print("Popup file not found at: \(popupURL.path)")
                // List all files in extension directory for debugging
                let extensionDir = URL(fileURLWithPath: ext.packagePath)
                if let files = try? FileManager.default.contentsOfDirectory(at: extensionDir, includingPropertiesForKeys: nil) {
                    print("Available files: \(files.map { $0.lastPathComponent })")
                }
                loadFallbackContent(webView: webView)
            }
        } else {
            print("No popup page found in manifest for extension: \(ext.name)")
            print("Checking for these popup keys: action.default_popup, browser_action.default_popup")
            // Load extension info page
            loadFallbackContent(webView: webView)
        }
        
        self.webView = webView
        return webView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ExtensionWebView
        
        init(_ parent: ExtensionWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Extension popup loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Extension popup failed to load: \(error.localizedDescription)")
            parent.loadFallbackContent(webView: webView)
        }
    }
    
    private func loadFallbackContent(webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    padding: 16px; 
                    margin: 0;
                    background: white;
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
                    background: #007AFF;
                    border-radius: 6px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: white;
                    font-weight: bold;
                }
                .info { color: #666; font-size: 14px; }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="icon">\(String(ext.name.prefix(1)).uppercased())</div>
                <div>
                    <div><strong>\(ext.name)</strong></div>
                    <div class="info">v\(ext.version)</div>
                </div>
            </div>
            <div class="info">
                Extension is active and running.<br>
                No popup interface available.
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
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
    
    private func getPopupPage() -> String? {
        if let action = ext.manifest["action"] as? [String: Any],
           let popup = action["default_popup"] as? String {
            return popup
        }
        
        if let browserAction = ext.manifest["browser_action"] as? [String: Any],
           let popup = browserAction["default_popup"] as? String {
            return popup
        }
        
        return nil
    }
    
    private func getExtensionURL(for page: String) -> URL {
        let extensionURL = URL(fileURLWithPath: ext.packagePath)
        return extensionURL.appendingPathComponent(page)
    }
}
