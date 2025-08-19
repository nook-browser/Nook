//
//  ExtensionManager.swift
//  Pulse
//
//  Simplified ExtensionManager using native WKWebExtension APIs
//

import Foundation
import WebKit
import SwiftData
import AppKit
import SwiftUI

@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate, WKNavigationDelegate {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private var actionAnchors: [String: [WeakAnchor]] = [:]
    // Stable adapters for tabs/windows used when notifying controller events
    private var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    internal var windowAdapter: ExtensionWindowAdapter?
    private weak var browserManagerRef: BrowserManager?
    
    let context: ModelContext
    
    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable = ExtensionUtils.isExtensionSupportAvailable
        super.init()
        
        if isExtensionSupportAvailable {
            setupExtensionController()
            loadInstalledExtensions()
        }
    }
    
    // MARK: - Setup
    
    private func setupExtensionController() {
        // Use a persistent controller configuration with a stable identifier
        let config: WKWebExtensionController.Configuration
        if let idString = UserDefaults.standard.string(forKey: "Pulse.WKWebExtensionController.Identifier"),
           let uuid = UUID(uuidString: idString) {
            config = WKWebExtensionController.Configuration(identifier: uuid)
        } else {
            let uuid = UUID()
            UserDefaults.standard.set(uuid.uuidString, forKey: "Pulse.WKWebExtensionController.Identifier")
            config = WKWebExtensionController.Configuration(identifier: uuid)
        }
        
        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        
        // Configure the shared WebView configuration for extension support
        let sharedWebConfig = BrowserConfiguration.shared.webViewConfiguration
        
        // Use the default website data store - WKWebExtension handles storage internally
        controller.configuration.defaultWebsiteDataStore = WKWebsiteDataStore.default()
        controller.configuration.webViewConfiguration = sharedWebConfig
        
        print("ExtensionManager: WKWebExtensionController configured with persistent storage identifier: \(config.identifier?.uuidString ?? "none")")
        print("   Native storage types supported: .local, .session, .synchronized")
        
        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject
        if #available(macOS 15.4, *) {
            sharedWebConfig.webExtensionController = controller
            
            // Ensure JavaScript is enabled for extension APIs
            sharedWebConfig.preferences.javaScriptEnabled = true
            
            print("ExtensionManager: Configured shared WebView configuration with extension controller")
        }
        
        extensionController = controller
        print("ExtensionManager: Native WKWebExtensionController initialized and configured")
        print("   Controller ID: \(config.identifier?.uuidString ?? "none")")
        print("   Data store: \(controller.configuration.defaultWebsiteDataStore)")
    }
    
    
    // MARK: - Extension Installation
    
    func installExtension(from url: URL, completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }
        
        Task {
            do {
                let installedExtension = try await performInstallation(from: url)
                await MainActor.run {
                    self.installedExtensions.append(installedExtension)
                    completionHandler(.success(installedExtension))
                }
            } catch let error as ExtensionError {
                await MainActor.run {
                    completionHandler(.failure(error))
                }
            } catch {
                await MainActor.run {
                    completionHandler(.failure(.installationFailed(error.localizedDescription)))
                }
            }
        }
    }
    
    private func performInstallation(from sourceURL: URL) async throws -> InstalledExtension {
        let extensionsDir = getExtensionsDirectory()
        try FileManager.default.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
        
        let extensionId = ExtensionUtils.generateExtensionId()
        let destinationDir = extensionsDir.appendingPathComponent(extensionId)
        
        // Handle ZIP files and directories
        if sourceURL.pathExtension.lowercased() == "zip" {
            try await extractZip(from: sourceURL, to: destinationDir)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationDir)
        }
        
        // Validate manifest exists
        let manifestURL = destinationDir.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
        
        // Use native WKWebExtension for loading
        let webExtension = try await WKWebExtension(resourceBaseURL: destinationDir)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        
        // Debug extension details and permissions
        print("ExtensionManager: Installing extension '\(webExtension.displayName ?? "Unknown")'")
        print("   Version: \(webExtension.version ?? "Unknown")")
        print("   Requested permissions: \(webExtension.requestedPermissions)")
        print("   Requested match patterns: \(webExtension.requestedPermissionMatchPatterns)")
        
        // Pre-grant common permissions for extensions that need them (like Dark Reader)
        let commonPermissions: [WKWebExtension.Permission] = [
            .storage,
            .tabs,
            .activeTab,
            .alarms,
            .contextMenus
        ]
        
        for permission in commonPermissions {
            if webExtension.requestedPermissions.contains(permission) {
                extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
                print("   ✅ Pre-granted \(permission) permission")
            }
        }
        
        // Pre-grant <all_urls> match pattern if requested
        for matchPattern in webExtension.requestedPermissionMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
            print("   ✅ Pre-granted match pattern: \(matchPattern)")
            print("      Pattern string: '\(matchPattern.description)'")
        }
        
        // Special check for <all_urls>
        if webExtension.requestedPermissionMatchPatterns.contains(where: { $0.description.contains("all_urls") }) {
            print("   🌐 Dark Reader has <all_urls> permission - content scripts should work!")
        }
        
        // Store context
        extensionContexts[extensionId] = extensionContext
        
        // Load with native controller
        try extensionController?.load(extensionContext)
        
        // Debug: Check if this is Dark Reader and log additional info
        if webExtension.displayName?.lowercased().contains("dark") == true ||
           webExtension.displayName?.lowercased().contains("reader") == true {
            print("🌙 DARK READER DETECTED - Adding comprehensive API debugging")
            print("   Has background content: \(webExtension.hasBackgroundContent)")
            print("   Has injected content: \(webExtension.hasInjectedContent)")
            print("   Current permissions after loading: \(extensionContext.currentPermissions)")
            
            // Test if Dark Reader can access current tab URL
            if let windowAdapter = windowAdapter,
               let activeTab = windowAdapter.activeTab(for: extensionContext),
               let url = activeTab.url?(for: extensionContext) {
                print("   🔍 Dark Reader can see active tab URL: \(url)")
                let hasAccess = extensionContext.hasAccess(to: url)
                print("   🔐 Has access to current URL: \(hasAccess)")
            }
            
            // WKWebExtension automatically provides Chrome APIs - no manual bridging needed
        }
        
        // Create extension entity for persistence
        let entity = ExtensionEntity(
            id: extensionId,
            name: manifest["name"] as? String ?? "Unknown Extension",
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            extensionDescription: manifest["description"] as? String,
            isEnabled: true,
            packagePath: destinationDir.path,
            iconPath: findExtensionIcon(in: destinationDir, manifest: manifest)
        )
        
        // Save to database
        self.context.insert(entity)
        try self.context.save()
        
        let installedExtension = InstalledExtension(from: entity, manifest: manifest)
        print("ExtensionManager: Successfully installed extension '\(installedExtension.name)' with native WKWebExtension")

        // Prompt for requested/optional permissions on first install (if any)
        if #available(macOS 15.4, *),
           let displayName = extensionContext.webExtension.displayName {
            let requestedPermissions = extensionContext.webExtension.requestedPermissions
            let optionalPermissions = extensionContext.webExtension.optionalPermissions
            let requestedMatches = extensionContext.webExtension.requestedPermissionMatchPatterns
            let optionalMatches = extensionContext.webExtension.optionalPermissionMatchPatterns
            if !requestedPermissions.isEmpty || !requestedMatches.isEmpty || !optionalPermissions.isEmpty || !optionalMatches.isEmpty {
                self.presentPermissionPrompt(
                    requestedPermissions: requestedPermissions,
                    optionalPermissions: optionalPermissions,
                    requestedMatches: requestedMatches,
                    optionalMatches: optionalMatches,
                    extensionDisplayName: displayName,
                    onDecision: { grantedPerms, grantedMatches in
                        // Apply permission decisions
                        for p in requestedPermissions.union(optionalPermissions) {
                            extensionContext.setPermissionStatus(
                                grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly,
                                for: p
                            )
                        }
                        for m in requestedMatches.union(optionalMatches) {
                            extensionContext.setPermissionStatus(
                                grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                                for: m
                            )
                        }
                    },
                    onCancel: {
                        // Default deny only for requested; optional remain unchanged
                        for p in requestedPermissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                        for m in requestedMatches { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                    }
                )
            }
        }

        return installedExtension
    }
    
    private func extractZip(from zipURL: URL, to destinationURL: URL) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-q", zipURL.path, "-d", destinationURL.path]
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            throw ExtensionError.installationFailed("Failed to extract ZIP file")
        }
    }
    
    private func findExtensionIcon(in directory: URL, manifest: [String: Any]) -> String? {
        if let icons = manifest["icons"] as? [String: String] {
            for size in ["128", "64", "48", "32", "16"] {
                if let iconPath = icons[size] {
                    let fullPath = directory.appendingPathComponent(iconPath)
                    if FileManager.default.fileExists(atPath: fullPath.path) {
                        return fullPath.path
                    }
                }
            }
        }
        
        let commonIconNames = ["icon.png", "logo.png", "icon128.png", "icon64.png"]
        for iconName in commonIconNames {
            let iconURL = directory.appendingPathComponent(iconName)
            if FileManager.default.fileExists(atPath: iconURL.path) {
                return iconURL.path
            }
        }
        
        return nil
    }
    
    // MARK: - Extension Management
    
    func enableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }
        
        do {
            try extensionController?.load(context)
            updateExtensionEnabled(extensionId, enabled: true)
        } catch {
            print("ExtensionManager: Failed to enable extension: \(error.localizedDescription)")
        }
    }
    
    func disableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }
        
        do {
            try extensionController?.unload(context)
            updateExtensionEnabled(extensionId, enabled: false)
        } catch {
            print("ExtensionManager: Failed to disable extension: \(error.localizedDescription)")
        }
    }
    
    func uninstallExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId] {
            do {
                try extensionController?.unload(context)
            } catch {
                print("ExtensionManager: Failed to unload extension context: \(error.localizedDescription)")
            }
            extensionContexts.removeValue(forKey: extensionId)
        }
        
        // Remove from database and filesystem
        do {
            let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))
            
            for entity in entities {
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                try? FileManager.default.removeItem(at: packageURL)
                self.context.delete(entity)
            }
            
            try self.context.save()
            installedExtensions.removeAll { $0.id == extensionId }
            
        } catch {
            print("ExtensionManager: Failed to uninstall extension: \(error)")
        }
    }
    
    private func updateExtensionEnabled(_ extensionId: String, enabled: Bool) {
        do {
            let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))
            
            if let entity = entities.first {
                entity.isEnabled = enabled
                try self.context.save()
                
                // Update UI
                if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
                    let updatedExtension = InstalledExtension(from: entity, manifest: installedExtensions[index].manifest)
                    installedExtensions[index] = updatedExtension
                }
            }
        } catch {
            print("ExtensionManager: Failed to update extension enabled state: \(error)")
        }
    }
    
    // MARK: - File Picker
    
    func showExtensionInstallDialog() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Install Extension"
        openPanel.message = "Select an extension folder or ZIP file to install"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.zip, .directory]
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url) { result in
                switch result {
                case .success(let ext):
                    print("Successfully installed extension: \(ext.name)")
                case .failure(let error):
                    print("Failed to install extension: \(error.localizedDescription)")
                    self.showErrorAlert(error)
                }
            }
        }
    }
    
    private func showErrorAlert(_ error: ExtensionError) {
        let alert = NSAlert()
        alert.messageText = "Extension Installation Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Persistence
    
    private func loadInstalledExtensions() {
        do {
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>())
            var loadedExtensions: [InstalledExtension] = []
            
            for entity in entities {
                let manifestURL = URL(fileURLWithPath: entity.packagePath).appendingPathComponent("manifest.json")
                
                do {
                    let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                    let installedExtension = InstalledExtension(from: entity, manifest: manifest)
                    loadedExtensions.append(installedExtension)
                    
                    // Recreate native extension if enabled
                    if entity.isEnabled {
                        Task {
                            do {
                                let webExtension = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: entity.packagePath))
                                let extensionContext = WKWebExtensionContext(for: webExtension)
                                
                                // Debug extension details and permissions
                                print("ExtensionManager: Loading existing extension '\(webExtension.displayName ?? entity.name)'")
                                print("   Version: \(webExtension.version ?? entity.version)")
                                print("   Requested permissions: \(webExtension.requestedPermissions)")
                                print("   Current permissions: \(extensionContext.currentPermissions)")
                                
                                // Pre-grant common permissions for existing extensions (like Dark Reader)
                                let commonPermissions: [WKWebExtension.Permission] = [
                                    .storage,
                                    .tabs,
                                    .activeTab,
                                    .alarms,
                                    .contextMenus
                                ]
                                
                                for permission in commonPermissions {
                                    if webExtension.requestedPermissions.contains(permission) &&
                                       !extensionContext.currentPermissions.contains(permission) {
                                        extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
                                        print("   ✅ Pre-granted \(permission) permission for existing extension")
                                    }
                                }
                                
                                // Pre-grant match patterns for existing extensions
                                for matchPattern in webExtension.requestedPermissionMatchPatterns {
                                    extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
                                    print("   ✅ Pre-granted match pattern for existing extension: \(matchPattern)")
                                }
                                
                                extensionContexts[entity.id] = extensionContext
                                try extensionController?.load(extensionContext)

                                // If extension defines requested/optional permissions but none decided yet, prompt.
                                if extensionContext.currentPermissions.isEmpty &&
                                   (extensionContext.webExtension.requestedPermissions.isEmpty == false ||
                                    extensionContext.webExtension.optionalPermissions.isEmpty == false ||
                                    extensionContext.webExtension.requestedPermissionMatchPatterns.isEmpty == false ||
                                    extensionContext.webExtension.optionalPermissionMatchPatterns.isEmpty == false),
                                   let displayName = extensionContext.webExtension.displayName {
                                    self.presentPermissionPrompt(
                                        requestedPermissions: extensionContext.webExtension.requestedPermissions,
                                        optionalPermissions: extensionContext.webExtension.optionalPermissions,
                                        requestedMatches: extensionContext.webExtension.requestedPermissionMatchPatterns,
                                        optionalMatches: extensionContext.webExtension.optionalPermissionMatchPatterns,
                                        extensionDisplayName: displayName,
                                        onDecision: { grantedPerms, grantedMatches in
                                            for p in extensionContext.webExtension.requestedPermissions.union(extensionContext.webExtension.optionalPermissions) {
                                                extensionContext.setPermissionStatus(grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly, for: p)
                                            }
                                            for m in extensionContext.webExtension.requestedPermissionMatchPatterns.union(extensionContext.webExtension.optionalPermissionMatchPatterns) {
                                                extensionContext.setPermissionStatus(grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly, for: m)
                                            }
                                        },
                                        onCancel: {
                                            for p in extensionContext.webExtension.requestedPermissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                                            for m in extensionContext.webExtension.requestedPermissionMatchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                                        }
                                    )
                                }
                            } catch {
                                print("ExtensionManager: Failed to reload extension '\(entity.name)': \(error)")
                            }
                        }
                    }
                    
                } catch {
                    print("ExtensionManager: Failed to load manifest for extension '\(entity.name)': \(error)")
                }
            }
            
            self.installedExtensions = loadedExtensions
            print("ExtensionManager: Loaded \(loadedExtensions.count) extensions using native WKWebExtension")
            
        } catch {
            print("ExtensionManager: Failed to load installed extensions: \(error)")
        }
    }
    
    private func getExtensionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pulse").appendingPathComponent("Extensions")
    }
    
    // MARK: - Native Extension Access
    
    /// Get the native WKWebExtensionContext for an extension
    func getExtensionContext(for extensionId: String) -> WKWebExtensionContext? {
        return extensionContexts[extensionId]
    }
    
    /// Get the native WKWebExtensionController
    var nativeController: WKWebExtensionController? {
        return extensionController
    }
    
    // MARK: - Debugging Utilities
    
    /// Show debugging console for popup troubleshooting
    func showPopupConsole() {
        PopupConsole.shared.show()
    }
    
    /// Force refresh window/tab state with extension controller
    func refreshWindowState() {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        
        if #available(macOS 15.4, *) {
            if windowAdapter == nil {
                windowAdapter = ExtensionWindowAdapter(browserManager: bm)
            }
            
            if let window = windowAdapter {
                print("[ExtensionManager] 🔄 Refreshing window state with controller...")
                controller.didFocusWindow(window)
                
                // Also refresh current tab
                if let currentTab = bm.tabManager.currentTab {
                    let tabAdapter = adapter(for: currentTab, browserManager: bm)
                    controller.didActivateTab(tabAdapter, previousActiveTab: nil)
                    controller.didSelectTabs([tabAdapter])
                    print("[ExtensionManager] 🔄 Refreshed active tab: '\(currentTab.name)'")
                }
            }
        }
    }
    
    /// Get detailed status of extension system
    func getExtensionSystemStatus() -> [String: Any] {
        var status: [String: Any] = [:]
        
        status["isSupported"] = isExtensionSupportAvailable
        status["controllerConfigured"] = extensionController != nil
        status["installedExtensionsCount"] = installedExtensions.count
        status["loadedContextsCount"] = extensionContexts.count
        status["browserManagerAttached"] = browserManagerRef != nil
        
        if let controller = extensionController {
            status["controllerID"] = controller.configuration.identifier?.uuidString ?? "none"
            status["extensionContextsLoaded"] = controller.extensionContexts.count
        }
        
        var extensionDetails: [[String: Any]] = []
        for ext in installedExtensions {
            var extInfo: [String: Any] = [:]
            extInfo["id"] = ext.id
            extInfo["name"] = ext.name
            extInfo["enabled"] = ext.isEnabled
            extInfo["hasContext"] = extensionContexts[ext.id] != nil
            
            if let context = extensionContexts[ext.id] {
                extInfo["isLoaded"] = context.isLoaded
                extInfo["permissions"] = context.currentPermissions.map { String(describing: $0) }
                extInfo["hostMatches"] = context.currentPermissionMatchPatterns.map { String(describing: $0) }
                extInfo["baseURL"] = context.baseURL.absoluteString
            }
            
            extensionDetails.append(extInfo)
        }
        status["extensions"] = extensionDetails
        
        return status
    }
    
    /// Log comprehensive system status for debugging
    func logSystemStatus() {
        let status = getExtensionSystemStatus()
        print("=== Extension System Status ===")
        for (key, value) in status {
            print("  \(key): \(value)")
        }
        
        // Also log current browser state
        if let bm = browserManagerRef {
            print("  Browser Manager State:")
            print("    Current tab: \(bm.tabManager.currentTab?.name ?? "None")")
            print("    Total tabs: \(bm.tabManager.tabs.count)")
            print("    Pinned tabs: \(bm.tabManager.pinnedTabs.count)")
            print("    Current space: \(bm.tabManager.currentSpace?.name ?? "None")")
            print("    Total spaces: \(bm.tabManager.spaces.count)")
        }
        print("===============================")
    }
    
    /// Create a simple test extension for debugging popup issues
    func createTestExtension() {
        guard isExtensionSupportAvailable else {
            print("Extension support not available")
            return
        }
        
        let testExtensionDir = getExtensionsDirectory().appendingPathComponent("test-extension")
        
        do {
            try FileManager.default.createDirectory(at: testExtensionDir, withIntermediateDirectories: true)
            
            // Create manifest.json
            let manifest = [
                "manifest_version": 3,
                "name": "Test Extension",
                "version": "1.0",
                "description": "Simple test extension for debugging popup issues",
                "permissions": ["activeTab", "storage"],
                "action": [
                    "default_popup": "popup.html",
                    "default_title": "Test Extension"
                ]
            ] as [String : Any]
            
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
            let manifestURL = testExtensionDir.appendingPathComponent("manifest.json")
            try manifestData.write(to: manifestURL)
            
            // Create popup.html
            let popupHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>Test Extension Popup</title>
                <style>
                    body {
                        width: 300px;
                        padding: 20px;
                        font-family: system-ui, sans-serif;
                    }
                    .section {
                        margin-bottom: 15px;
                        padding: 10px;
                        border: 1px solid #ccc;
                        border-radius: 5px;
                    }
                    .status {
                        font-size: 12px;
                        color: #666;
                    }
                    button {
                        margin: 5px 0;
                        padding: 5px 10px;
                    }
                </style>
            </head>
            <body>
                <div class="section">
                    <h3>Test Extension Popup</h3>
                    <p class="status">If you can see this, the popup is loading correctly!</p>
                </div>
                
                <div class="section">
                    <h4>API Tests</h4>
                    <button id="testTabs">Test Tabs API</button>
                    <button id="testStorage">Test Storage API</button>
                    <div id="results"></div>
                </div>
                
                <script src="popup.js"></script>
            </body>
            </html>
            """
            
            let popupHTMLURL = testExtensionDir.appendingPathComponent("popup.html")
            try popupHTML.write(to: popupHTMLURL, atomically: true, encoding: .utf8)
            
            // Create popup.js
            let popupJS = """
            console.log('Test extension popup script loaded');
            console.log('Extension APIs available:', {
                browser: typeof browser !== 'undefined',
                chrome: typeof chrome !== 'undefined',
                runtime: typeof (browser?.runtime) !== 'undefined',
                storage: typeof (browser?.storage) !== 'undefined',
                tabs: typeof (browser?.tabs) !== 'undefined'
            });
            
            document.addEventListener('DOMContentLoaded', function() {
                const results = document.getElementById('results');
                
                function logResult(message) {
                    console.log(message);
                    const div = document.createElement('div');
                    div.textContent = message;
                    div.style.fontSize = '12px';
                    div.style.margin = '5px 0';
                    results.appendChild(div);
                }
                
                document.getElementById('testTabs').addEventListener('click', async function() {
                    try {
                        logResult('Testing tabs API...');
                        const tabs = await browser.tabs.query({active: true, currentWindow: true});
                        logResult(`✅ Found ${tabs.length} active tabs`);
                        if (tabs[0]) {
                            logResult(`Current tab: ${tabs[0].title} - ${tabs[0].url}`);
                        }
                    } catch (error) {
                        logResult(`❌ Tabs API error: ${error.message}`);
                    }
                });
                
                document.getElementById('testStorage').addEventListener('click', async function() {
                    try {
                        logResult('Testing storage API...');
                        await browser.storage.local.set({testKey: 'testValue'});
                        const result = await browser.storage.local.get('testKey');
                        logResult(`✅ Storage test successful: ${JSON.stringify(result)}`);
                    } catch (error) {
                        logResult(`❌ Storage API error: ${error.message}`);
                    }
                });
                
                logResult('Popup loaded successfully!');
            });
            """
            
            let popupJSURL = testExtensionDir.appendingPathComponent("popup.js")
            try popupJS.write(to: popupJSURL, atomically: true, encoding: .utf8)
            
            print("✅ Created test extension at: \(testExtensionDir.path)")
            print("   You can now install it using the extension manager")
            
        } catch {
            print("❌ Failed to create test extension: \(error)")
        }
    }

    /// Connect the browser manager so we can expose tabs/windows and present UI.
    func attach(browserManager: BrowserManager) {
        self.browserManagerRef = browserManager
        // Ensure a stable window adapter and notify controller about the window
        if #available(macOS 15.4, *), let controller = extensionController {
            let adapter = self.windowAdapter ?? ExtensionWindowAdapter(browserManager: browserManager)
            self.windowAdapter = adapter
            
            print("ExtensionManager: Notifying controller about window and tabs...")
            
            // Important: Notify about window FIRST
            controller.didOpenWindow(adapter)
            controller.didFocusWindow(adapter)
            
            // Notify about existing tabs 
            let allTabs = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
            for tab in allTabs {
                let tabAdapter = self.adapter(for: tab, browserManager: browserManager)
                controller.didOpenTab(tabAdapter)
            }
            
            // Notify about current active tab
            if let currentTab = browserManager.tabManager.currentTab {
                let tabAdapter = self.adapter(for: currentTab, browserManager: browserManager)
                controller.didActivateTab(tabAdapter, previousActiveTab: nil)
                controller.didSelectTabs([tabAdapter])
            }
            
            print("ExtensionManager: Attached to browser manager and synced \(allTabs.count) tabs in window")
        }
    }

    // MARK: - Controller event notifications for tabs
    private var lastCachedAdapterLog: Date = Date.distantPast
    
    @available(macOS 15.4, *)
    private func adapter(for tab: Tab, browserManager: BrowserManager) -> ExtensionTabAdapter {
        if let existing = tabAdapters[tab.id] { 
            // Only log cached adapter access every 10 seconds to prevent spam
            let now = Date()
            if now.timeIntervalSince(lastCachedAdapterLog) > 10.0 {
                print("[ExtensionManager] Returning CACHED adapter for '\(tab.name)': \(ObjectIdentifier(existing))")
                lastCachedAdapterLog = now
            }
            return existing 
        }
        let created = ExtensionTabAdapter(tab: tab, browserManager: browserManager)
        tabAdapters[tab.id] = created
        print("[ExtensionManager] Created NEW adapter for '\(tab.name)': \(ObjectIdentifier(created))")
        return created
    }

    // Expose a stable adapter getter for window adapters
    @available(macOS 15.4, *)
    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let bm = browserManagerRef else { return nil }
        return adapter(for: tab, browserManager: bm)
    }

    @available(macOS 15.4, *)
    func notifyTabOpened(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didOpenTab(a)
    }

    @available(macOS 15.4, *)
    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let newA = adapter(for: newTab, browserManager: bm)
        let oldA = previous.map { adapter(for: $0, browserManager: bm) }
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }
    }

    @available(macOS 15.4, *)
    func notifyTabClosed(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didCloseTab(a, windowIsClosing: false)
        tabAdapters[tab.id] = nil
    }

    @available(macOS 15.4, *)
    func notifyTabPropertiesChanged(_ tab: Tab, properties: WKWebExtension.TabChangedProperties) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didChangeTabProperties(properties, for: a)
    }

    /// Register a UI anchor view for an extension action button to position popovers.
    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        if actionAnchors[extensionId] == nil { actionAnchors[extensionId] = [] }
        // Remove stale anchors
        actionAnchors[extensionId]?.removeAll { $0.view == nil }
        if let idx = actionAnchors[extensionId]?.firstIndex(where: { $0.view === anchorView }) {
            actionAnchors[extensionId]?[idx] = anchor
        } else {
            actionAnchors[extensionId]?.append(anchor)
        }
        if anchor.window == nil {
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let view = anchorView else { return }
                let updated = WeakAnchor(view: view, window: view.window)
                if let idx = self?.actionAnchors[extensionId]?.firstIndex(where: { $0.view === view }) {
                    self?.actionAnchors[extensionId]?[idx] = updated
                }
            }
        }
    }
    
    // MARK: - WKWebExtensionControllerDelegate
    
    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("🎉 DELEGATE: Extension wants to present popup!")
        print("   Action: \(action)")
        print("   Extension: \(extensionContext.webExtension.displayName ?? "Unknown")")
        
        // Debug permission context to help diagnose popup scripts relying on APIs
        let perms = extensionContext.currentPermissions.map { String(describing: $0) }.sorted()
        let reqPerms = extensionContext.webExtension.requestedPermissions.map { String(describing: $0) }.sorted()
        let optPerms = extensionContext.webExtension.optionalPermissions.map { String(describing: $0) }.sorted()
        let hostMatches = extensionContext.currentPermissionMatchPatterns.map { String(describing: $0) }.sorted()
        print("   Current perms: \(perms)")
        print("   Current host matches: \(hostMatches)")
        print("   Requested perms: \(reqPerms)")
        print("   Optional perms: \(optPerms)")
        
        // Check Dark Reader's access to current page
        if extensionContext.webExtension.displayName?.lowercased().contains("dark") == true {
            if let windowAdapter = windowAdapter,
               let activeTab = windowAdapter.activeTab(for: extensionContext),
               let url = activeTab.url?(for: extensionContext) {
                print("   🔍 Current tab URL: \(url)")
                let hasAccess = extensionContext.hasAccess(to: url)
                print("   🔐 Has access to current URL: \(hasAccess)")
                if !hasAccess {
                    print("   ❌ This is why Dark Reader says 'page is protected by browser'!")
                    print("   💡 URL might be restricted (chrome://, about:, file://, etc.)")
                } else {
                    print("   ✅ Dark Reader has permission but still says 'protected' - content script injection issue!")
                    print("   🔍 Checking if WebView is associated with extension controller...")
                    
                    // Check if the current page's WebView is associated with our controller
                    if let tab = activeTab as? ExtensionTabAdapter {
                        let webView = tab.tab.webView
                        let hasController = webView.configuration.webExtensionController != nil
                        let isSameController = webView.configuration.webExtensionController === extensionController
                        print("      WebView has extension controller: \(hasController)")
                        print("      Is same controller: \(isSameController)")
                        
                        if !isSameController {
                            print("      ❌ WebView not associated with extension controller!")
                            print("      💡 This prevents content script injection")
                        } else {
                            print("      ✅ WebView properly associated - testing content script injection...")
                            
                            // Test if content scripts are actually injected by checking for Dark Reader's presence
                            webView.evaluateJavaScript("window.DarkReader !== undefined || document.querySelector('[data-darkreader-scheme]') !== null") { result, error in
                                if let isDarkReaderPresent = result as? Bool {
                                    print("      🔍 Dark Reader content scripts detected: \(isDarkReaderPresent)")
                                    if !isDarkReaderPresent {
                                        print("      ❌ Content scripts NOT injected - 'world' parameter issue likely!")
                                        print("      💡 WKWebExtension may not support 'world': 'MAIN'/'ISOLATED' properly")
                                    }
                                } else {
                                    print("      ⚠️ Could not test for Dark Reader content scripts: \(error?.localizedDescription ?? "unknown error")")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Get the native popover from the action
        guard let popover = action.popupPopover else {
            print("❌ DELEGATE: No popover available on action")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No popover available"]))
            return
        }
        
        print("✅ DELEGATE: Native popover available - configuring and presenting!")
        
        // Configure the popup WebView if available
        if let webView = action.popupWebView {
            print("   PopupWebView found, configuring...")
            
            // Ensure the WebView has proper configuration for extension resources
            if webView.configuration.webExtensionController == nil {
                webView.configuration.webExtensionController = controller
                print("   Attached extension controller to popup WebView")
            }
            
            // Attach navigation delegate for debugging
            webView.navigationDelegate = self
            
            // Enable inspection for debugging
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }
            
            // Attach console helper for manual JS evaluation
            PopupConsole.shared.attach(to: webView)
            
            // Log initial state
            let popupURL = webView.url?.absoluteString ?? "(nil)"
            print("   Popup URL: \"\(popupURL)\"")
            
            // Check document readiness
            webView.evaluateJavaScript("document.readyState") { value, _ in
                let state = (value as? String) ?? "(unknown)"
                print("   Popup document.readyState: \"\(state)\"")
            }
            
            // Ensure extension APIs are available
            let apiCheck = """
            (() => {
                return {
                    hasBrowser: typeof browser !== 'undefined',
                    hasChrome: typeof chrome !== 'undefined',
                    hasRuntime: typeof (browser?.runtime) !== 'undefined',
                    hasStorage: typeof (browser?.storage?.local) !== 'undefined',
                    hasTabs: typeof (browser?.tabs) !== 'undefined',
                    location: location.href
                };
            })()
            """
            
            webView.evaluateJavaScript(apiCheck) { result, error in
                if let error = error {
                    print("   API check error: \(error.localizedDescription)")
                } else {
                    print("   API availability: \(String(describing: result))")
                }
            }
        } else {
            print("   No popupWebView present on action")
        }
        
        // Present the popover on main thread
        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
            
            // Try to use registered anchor for this extension
            if let extId = self.extensionContexts.first(where: { $0.value === extensionContext })?.key,
               var anchors = self.actionAnchors[extId] {
                // Clean up stale anchors
                anchors.removeAll { $0.view == nil }
                self.actionAnchors[extId] = anchors
                
                // Find anchor in current window
                if let win = targetWindow, let match = anchors.first(where: { $0.window === win }), let view = match.view {
                    print("   Using registered anchor in current window")
                    popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
                    completionHandler(nil)
                    return
                }
                
                // Use first available anchor
                if let view = anchors.first?.view {
                    print("   Using first available anchor")
                    popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
                    completionHandler(nil)
                    return
                }
            }
            
            // Fallback to center of window
            if let window = targetWindow, let contentView = window.contentView {
                let rect = CGRect(x: contentView.bounds.midX - 10, y: contentView.bounds.maxY - 50, width: 20, height: 20)
                print("   Using fallback anchor in center of window")
                popover.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                completionHandler(nil)
                return
            }

            print("❌ DELEGATE: No anchor or contentView available")
            completionHandler(NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No window available"]))
        }
    }
    
    // MARK: - WKNavigationDelegate (popup diagnostics)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didStartProvisionalNavigation: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Started loading: \(urlString)")
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didCommit: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Committed: \(urlString)")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didFinish: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Finished: \(urlString)")
        
        // Get document title
        webView.evaluateJavaScript("document.title") { value, _ in
            let title = (value as? String) ?? "(unknown)"
            print("[Popup] document.title: \"\(title)\"")
            PopupConsole.shared.log("[Document] Title: \(title)")
        }
        
        // Comprehensive capability probe for extension APIs
        let comprehensiveProbe = """
        (() => {
            const result = {
                location: {
                    href: location.href,
                    protocol: location.protocol,
                    host: location.host
                },
                document: {
                    title: document.title,
                    readyState: document.readyState,
                    hasBody: !!document.body,
                    bodyText: document.body ? document.body.innerText.slice(0, 100) : null
                },
                apis: {
                    browser: typeof browser !== 'undefined',
                    chrome: typeof chrome !== 'undefined',
                    runtime: typeof (browser?.runtime || chrome?.runtime) !== 'undefined',
                    storage: {
                        available: typeof (browser?.storage || chrome?.storage) !== 'undefined',
                        local: typeof (browser?.storage?.local || chrome?.storage?.local) !== 'undefined',
                        sync: typeof (browser?.storage?.sync || chrome?.storage?.sync) !== 'undefined'
                    },
                    tabs: typeof (browser?.tabs || chrome?.tabs) !== 'undefined',
                    action: typeof (browser?.action || chrome?.action) !== 'undefined'
                },
                errors: []
            };
            
            // Check for common popup errors
            try {
                if (typeof browser !== 'undefined' && browser.runtime) {
                    result.runtime = {
                        id: browser.runtime.id,
                        url: browser.runtime.getURL ? browser.runtime.getURL('') : 'getURL not available'
                    };
                }
            } catch (e) {
                result.errors.push('Runtime error: ' + e.message);
            }
            
            return result;
        })()
        """
        
        webView.evaluateJavaScript(comprehensiveProbe) { value, error in
            if let error = error {
                print("[Popup] comprehensive probe error: \(error.localizedDescription)")
                PopupConsole.shared.log("[Error] Probe failed: \(error.localizedDescription)")
            } else if let dict = value as? [String: Any] {
                print("[Popup] comprehensive probe: \(dict)")
                PopupConsole.shared.log("[Probe] APIs: \(dict)")
            } else {
                print("[Popup] comprehensive probe: unexpected result type")
                PopupConsole.shared.log("[Warning] Probe returned unexpected result")
            }
        }
        
        // Note: Skipping automatic tabs.query test to avoid potential recursion issues
        // Extensions will call tabs.query naturally, and we can debug through console
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Popup] didFail: \(error.localizedDescription)")
        PopupConsole.shared.log("[Error] Navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[Popup] didFailProvisional: \(error.localizedDescription)")
        PopupConsole.shared.log("[Error] Provisional navigation failed: \(error.localizedDescription)")
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[Popup] content process terminated")
        PopupConsole.shared.log("[Critical] WebView process terminated")
    }

    // MARK: - Windows exposure (tabs/windows APIs)
    private var lastFocusedWindowCall: Date = Date.distantPast
    private var lastOpenWindowsCall: Date = Date.distantPast
    
    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        // Throttle logging to prevent spam
        let now = Date()
        if now.timeIntervalSince(lastFocusedWindowCall) > 10.0 {
            print("[ExtensionManager] 🎯 focusedWindowFor() called")
            lastFocusedWindowCall = now
        }
        
        guard let bm = browserManagerRef else { 
            return nil 
        }
        if windowAdapter == nil { 
            windowAdapter = ExtensionWindowAdapter(browserManager: bm) 
        }
        return windowAdapter
    }

    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        // Throttle logging to prevent spam
        let now = Date()
        if now.timeIntervalSince(lastOpenWindowsCall) > 10.0 {
            print("[ExtensionManager] 🎯 openWindowsFor() called")
            lastOpenWindowsCall = now
        }
        
        guard let bm = browserManagerRef else { 
            return [] 
        }
        if windowAdapter == nil { 
            windowAdapter = ExtensionWindowAdapter(browserManager: bm) 
        }
        return windowAdapter != nil ? [windowAdapter!] : []
    }

    // MARK: - Permission prompting helper (invoked by delegate when needed)
    @available(macOS 15.4, *)
    func presentPermissionPrompt(
        requestedPermissions: Set<WKWebExtension.Permission>,
        optionalPermissions: Set<WKWebExtension.Permission>,
        requestedMatches: Set<WKWebExtension.MatchPattern>,
        optionalMatches: Set<WKWebExtension.MatchPattern>,
        extensionDisplayName: String,
        onDecision: @escaping (_ grantedPermissions: Set<WKWebExtension.Permission>, _ grantedMatches: Set<WKWebExtension.MatchPattern>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let bm = browserManagerRef else { onCancel(); return }

        // Convert enums to readable strings for UI
        let reqPerms = requestedPermissions.map { String(describing: $0) }.sorted()
        let optPerms = optionalPermissions.map { String(describing: $0) }.sorted()
        let reqHosts = requestedMatches.map { String(describing: $0) }.sorted()
        let optHosts = optionalMatches.map { String(describing: $0) }.sorted()

        bm.showCustomContentDialog(
            header: AnyView(DialogHeader(icon: "puzzlepiece.extension", title: "Extension Permissions", subtitle: nil)),
            content: ExtensionPermissionView(
                extensionName: extensionDisplayName,
                requestedPermissions: reqPerms,
                optionalPermissions: optPerms,
                requestedHostPermissions: reqHosts,
                optionalHostPermissions: optHosts,
                onGrant: { selectedPerms, selectedHosts in
                    // Map strings back using string description matching across both requested and optional
                    let allPerms = requestedPermissions.union(optionalPermissions)
                    let allHosts = requestedMatches.union(optionalMatches)
                    let grantedPermissions = Set(allPerms.filter { selectedPerms.contains(String(describing: $0)) })
                    let grantedMatches = Set(allHosts.filter { selectedHosts.contains(String(describing: $0)) })
                    bm.closeDialog()
                    onDecision(grantedPermissions, grantedMatches)
                },
                onDeny: {
                    bm.closeDialog()
                    onCancel()
                }
            ),
            footer: AnyView(EmptyView())
        )
    }

    // Delegate entry point for permission requests from extensions at runtime
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in window: (any WKWebExtensionWindow)? ,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: permissions,
            optionalPermissions: extensionContext.webExtension.optionalPermissions,
            requestedMatches: extensionContext.webExtension.requestedPermissionMatchPatterns,
            optionalMatches: extensionContext.webExtension.optionalPermissionMatchPatterns,
            extensionDisplayName: displayName,
            onDecision: { grantedPerms, grantedMatches in
                for p in permissions.union(extensionContext.webExtension.optionalPermissions) {
                    extensionContext.setPermissionStatus(
                        grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly,
                        for: p
                    )
                }
                for m in extensionContext.webExtension.requestedPermissionMatchPatterns.union(extensionContext.webExtension.optionalPermissionMatchPatterns) {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(nil)
            },
            onCancel: {
                for p in permissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                for m in extensionContext.webExtension.requestedPermissionMatchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler(nil)
            }
        )
    }

    // Note: We can provide implementations for opening new tabs/windows once the
    // exact parameter types are finalized for the targeted SDK. These delegate
    // methods are optional; omitting them avoids type resolution issues across
    // SDK variations while retaining popup and permission handling.

    // MARK: - Opening tabs/windows requested by extensions
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let bm = browserManagerRef else { completionHandler(nil); return }

        let targetURL = configuration.url
        if let url = targetURL {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
            completionHandler(nil)
            return
        }
        // No URL specified — ignore per docs discretion
        completionHandler(nil)
    }

    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let bm = browserManagerRef else { completionHandler(nil); return }
        // Create a new space to emulate a separate window in our UI
        let newSpace = bm.tabManager.createSpace(name: "Window")
        if let firstURL = configuration.tabURLs.first {
            _ = bm.tabManager.createNewTab(url: firstURL.absoluteString, in: newSpace)
        } else {
            _ = bm.tabManager.createNewTab(in: newSpace)
        }
        bm.tabManager.setActiveSpace(newSpace)
        completionHandler(nil)
    }
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in window: (any WKWebExtensionWindow)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: [],
            optionalPermissions: [],
            requestedMatches: matchPatterns,
            optionalMatches: [],
            extensionDisplayName: displayName,
            onDecision: { _, grantedMatches in
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(nil)
            },
            onCancel: {
                for m in matchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler(nil)
            }
        )
    }
}

// MARK: - Weak View Reference Helper
final class WeakAnchor {
    weak var view: NSView?
    weak var window: NSWindow?
    init(view: NSView?, window: NSWindow?) {
        self.view = view
        self.window = window
    }
}
