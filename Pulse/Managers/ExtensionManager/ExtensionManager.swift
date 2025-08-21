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
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private var actionAnchors: [String: [WeakAnchor]] = [:]
    // Map extension UUID (from webkit-extension://<uuid>/...) to target tab adapter for popup-initiated host injections
    private var popupTargetTabs: [String: ExtensionTabAdapter] = [:]
    // Track active popovers keyed by extension UUID (webkit-extension://<uuid>/)
    private var activePopoversByHost: [String: NSPopover] = [:]
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
        print("   World support (MAIN/ISOLATED): \(ExtensionUtils.isWorldInjectionSupported)")
        
        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject
        if #available(macOS 15.5, *) {
            sharedWebConfig.webExtensionController = controller
            
            // Ensure JavaScript is enabled for extension APIs
            sharedWebConfig.preferences.javaScriptEnabled = true
            
            print("ExtensionManager: Configured shared WebView configuration with extension controller")
            
            // CRITICAL FIX: Update existing WebViews that were created before extension controller setup
            updateExistingWebViewsWithController(controller)
        }
        
        extensionController = controller
        print("ExtensionManager: Native WKWebExtensionController initialized and configured")
        print("   Controller ID: \(config.identifier?.uuidString ?? "none")")
        print("   Data store: \(controller.configuration.defaultWebsiteDataStore)")
    }
    
    
    // MARK: - WebView Extension Controller Association
    
    /// Update existing WebViews to use the extension controller
    /// This fixes content script injection issues for tabs created before extension setup
    @available(macOS 15.5, *)
    private func updateExistingWebViewsWithController(_ controller: WKWebExtensionController) {
        guard let bm = browserManagerRef else { return }
        
        print("🔧 Updating existing WebViews with extension controller...")
        
        let allTabs = bm.tabManager.pinnedTabs + bm.tabManager.tabs
        var updatedCount = 0
        
        for tab in allTabs {
            // Access the WebView (this creates it if not exists)
            let webView = tab.webView
            
            if webView.configuration.webExtensionController !== controller {
                print("  📝 Updating WebView for tab: \(tab.name)")
                webView.configuration.webExtensionController = controller
                updatedCount += 1
                
                // Also ensure JavaScript is enabled
                webView.configuration.preferences.javaScriptEnabled = true
            }
        }
        
        print("✅ Updated \(updatedCount) existing WebViews with extension controller")
        
        if updatedCount > 0 {
            print("💡 Content script injection should now work on existing tabs")
        }
    }

    /// Diagnose content script injection issues
    func diagnoseContentScriptIssues() {
        print("=== Content Script Injection Diagnosis ===")
        
        guard let bm = browserManagerRef else {
            print("❌ Browser manager not attached")
            return
        }
        
        guard let currentTab = bm.tabManager.currentTab else {
            print("❌ No current tab")
            return
        }
        
        let currentURL = currentTab.url
        print("🔍 Current tab URL: \(currentURL)")
        print("🔍 Current tab name: \(currentTab.name)")
        print("🔍 Tab ID: \(currentTab.id)")
        
        // Check URL scheme
        let url = currentURL
        let scheme = url.scheme ?? "unknown"
        let isRestrictedScheme = ["chrome", "about", "file", "webkit-extension", "moz-extension"].contains(scheme)
        print("🔍 URL scheme: \(scheme) - \(isRestrictedScheme ? "❌ Restricted" : "✅ Injectable")")
        
        if isRestrictedScheme {
            print("💡 Navigate to http:// or https:// page for content injection tests")
        }
        
        // Check WebView extension controller association
        let webView = currentTab.webView
        let hasController = webView.configuration.webExtensionController != nil
        let isSameController = webView.configuration.webExtensionController === extensionController
        print("🔍 WebView has extension controller: \(hasController)")
        print("🔍 Is same controller: \(isSameController)")
        
        if !isSameController {
            print("❌ WebView not properly associated with extension controller!")
            print("💡 This prevents content script injection - fixing now...")
            
            // Fix the association for current tab
            if let controller = extensionController {
                print("🔧 Fixing WebView association for current tab...")
                webView.configuration.webExtensionController = controller
                webView.configuration.preferences.javaScriptEnabled = true
                print("✅ WebView association updated for current tab")
                
                // Fix all other tabs too
                if #available(macOS 15.5, *) {
                    updateExistingWebViewsWithController(controller)
                }
            }
        } else {
            print("✅ WebView properly associated with extension controller")
        }
        
        // Check extension contexts
        if let controller = extensionController {
            print("🔍 Extension controller has \(controller.extensionContexts.count) loaded contexts")
            
            for context in controller.extensionContexts {
                if let displayName = context.webExtension.displayName {
                    print("  📦 Extension: \(displayName)")
                    print("     Permissions: \(context.currentPermissions.count)")
                    print("     Match patterns: \(context.currentPermissionMatchPatterns.count)")
                    
                    let url = currentURL
                    let hasAccess = context.hasAccess(to: url)
                    print("     Has access to current URL: \(hasAccess ? "✅" : "❌")")
                }
            }
        }
        
        // Check tab adapter
        if let tabAdapter = tabAdapters[currentTab.id] {
            print("🔍 Tab adapter exists: ✅")
            print("   Adapter ID: \(ObjectIdentifier(tabAdapter))")
        } else {
            print("🔍 Tab adapter exists: ❌")
            print("💡 Creating tab adapter...")
            let adapter = self.adapter(for: currentTab, browserManager: bm)
            print("✅ Tab adapter created: \(ObjectIdentifier(adapter))")
        }
        
        print("==========================================\n")
    }
    
    /// Test MV3 extension functionality
    func testMV3Functionality() {
        print("=== MV3 Extension Functionality Test ===")
        
        // Check if we have any MV3 extensions installed
        let mv3Extensions = installedExtensions.filter { $0.manifestVersion == 3 }
        print("MV3 Extensions installed: \(mv3Extensions.count)")
        
        for ext in mv3Extensions {
            print("\n  Testing: \(ext.name) (v\(ext.version))")
            
            if let context = extensionContexts[ext.id] {
                // Test basic extension state
                print("    ✅ Extension context loaded: \(context.isLoaded)")
                print("    ✅ Current permissions: \(context.currentPermissions.count)")
                print("    ✅ Host access patterns: \(context.currentPermissionMatchPatterns.count)")
                
                // Test action availability
                if let action = context.action(for: nil) {
                    print("    ✅ Action available - popup: \(action.presentsPopup)")
                } else {
                    print("    ⚠️  No action available")
                }
                
                // Test world injection capability
                if #available(macOS 15.5, *) {
                    print("    ✅ MAIN/ISOLATED world support available")
                } else {
                    print("    ⚠️  Limited world support (macOS 15.4)")
                }
            } else {
                print("    ❌ No extension context found")
            }
        }
        
        // Test controller state
        if let controller = extensionController {
            print("\n  Controller State:")
            print("    Extension contexts loaded: \(controller.extensionContexts.count)")
            print("    Web view controller associated: \(BrowserConfiguration.shared.webViewConfiguration.webExtensionController != nil)")
        }
        
        print("\n  Browser State:")
        if let bm = browserManagerRef {
            print("    Browser manager attached: ✅")
            print("    Current tab: \(bm.tabManager.currentTab?.name ?? "None")")
            print("    Window adapter: \(windowAdapter != nil ? "✅" : "❌")")
        } else {
            print("    Browser manager attached: ❌")
        }
        
        print("=====================================\n")
    }
    
    // MARK: - MV3 Support Methods
    
    /// Common permissions that should be granted for extensions
    private static let commonPermissions: [WKWebExtension.Permission] = [
        .storage,
        .tabs,
        .activeTab,
        .scripting,
        .alarms,
        .contextMenus,
        .declarativeNetRequest, // MV3: For content blocking
        .webNavigation,         // MV3: For navigation events
        .cookies               // MV3: For cookie access
    ]
    
    /// Grant common permissions and MV2 compatibility for an extension context
    private func grantCommonPermissions(to extensionContext: WKWebExtensionContext, webExtension: WKWebExtension, isExisting: Bool = false) {
        let existingLabel = isExisting ? " for existing extension" : ""
        
        // Grant common permissions if requested
        for permission in Self.commonPermissions {
            if webExtension.requestedPermissions.contains(permission) {
                if !isExisting || !extensionContext.currentPermissions.contains(permission) {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
                    print("   ✅ Pre-granted \(permission) permission\(existingLabel)")
                }
            }
        }
        
        // Compatibility: proactively grant scripting and tabs even if not declared.
        // Apple’s APIs may require these to resolve tab targets and allow injections.
        if !isExisting || !extensionContext.currentPermissions.contains(.scripting) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: .scripting)
            print("   ✅ Ensured .scripting is granted\(existingLabel)")
        }
        if !isExisting || !extensionContext.currentPermissions.contains(.tabs) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: .tabs)
            print("   ✅ Ensured .tabs is granted\(existingLabel)")
        }
    }
    
    /// Validate MV3-specific requirements
    private func validateMV3Requirements(manifest: [String: Any], baseURL: URL) throws {
        // Check for service worker
        if let background = manifest["background"] as? [String: Any] {
            if let serviceWorker = background["service_worker"] as? String {
                let serviceWorkerPath = baseURL.appendingPathComponent(serviceWorker)
                if !FileManager.default.fileExists(atPath: serviceWorkerPath.path) {
                    throw ExtensionError.installationFailed("MV3 service worker not found: \(serviceWorker)")
                }
                print("   ✅ MV3 service worker found: \(serviceWorker)")
            }
        }
        
        // Validate content scripts with world parameter
        if let contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for script in contentScripts {
                if let world = script["world"] as? String {
                    print("   🌍 Content script with world: \(world)")
                    if world == "MAIN" {
                        print("   ⚠️  MAIN world content script - requires macOS 15.5+ for full support")
                    }
                }
            }
        }
        
        // Validate host_permissions vs permissions
        if let hostPermissions = manifest["host_permissions"] as? [String] {
            print("   🏠 MV3 host_permissions: \(hostPermissions)")
        }
    }
    
    /// Configure MV3-specific extension features
    private func configureMV3Extension(webExtension: WKWebExtension, context: WKWebExtensionContext, manifest: [String: Any]) async throws {
        // MV3: Service worker background handling
        if webExtension.hasBackgroundContent {
            print("   🔧 MV3 service worker background detected")
        }
        
        // MV3: Enhanced content script injection support
        if webExtension.hasInjectedContent {
            print("   💉 MV3 content scripts detected - ensuring MAIN/ISOLATED world support")
        }
        
        // MV3: Action popup validation
        if let action = manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String {
                print("   🔧 MV3 action popup: \(popup)")
            }
        }
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
        
        // MV3 Validation: Ensure proper manifest version support
        if let manifestVersion = manifest["manifest_version"] as? Int {
            print("ExtensionManager: Installing MV\(manifestVersion) extension")
            if manifestVersion == 3 {
                try validateMV3Requirements(manifest: manifest, baseURL: destinationDir)
            }
        }
        
        // Use native WKWebExtension for loading with explicit manifest parsing
        print("🔧 [ExtensionManager] Initializing WKWebExtension...")
        print("   Resource base URL: \(destinationDir.path)")
        print("   Manifest version: \(manifest["manifest_version"] ?? "unknown")")
        
        // Try the recommended initialization method with proper manifest parsing
        let webExtension = try await WKWebExtension(resourceBaseURL: destinationDir)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        
        // Debug the loaded extension
        print("✅ WKWebExtension created successfully")
        print("   Display name: \(webExtension.displayName ?? "Unknown")")
        print("   Version: \(webExtension.version ?? "Unknown")")
        print("   Unique ID: \(extensionContext.uniqueIdentifier)")
        
        // MV3: Enhanced permission validation and service worker support
        if let manifestVersion = manifest["manifest_version"] as? Int, manifestVersion == 3 {
            try await configureMV3Extension(webExtension: webExtension, context: extensionContext, manifest: manifest)
        }
        
        // Debug extension details and permissions
        print("ExtensionManager: Installing extension '\(webExtension.displayName ?? "Unknown")'")
        print("   Version: \(webExtension.version ?? "Unknown")")
        print("   Requested permissions: \(webExtension.requestedPermissions)")
        print("   Requested match patterns: \(webExtension.requestedPermissionMatchPatterns)")
        
        // Pre-grant common permissions for extensions that need them (like Dark Reader)
        grantCommonPermissions(to: extensionContext, webExtension: webExtension)
        
        // MV3: Handle host permissions (formerly <all_urls>)
        for matchPattern in webExtension.requestedPermissionMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
            print("   ✅ Pre-granted match pattern: \(matchPattern)")
            print("      Pattern string: '\(matchPattern.description)'")
        }
        
        // MV3: Special handling for host permissions
        let hasAllUrls = webExtension.requestedPermissionMatchPatterns.contains(where: { $0.description.contains("all_urls") })
        let hasWildcardHosts = webExtension.requestedPermissionMatchPatterns.contains(where: { $0.description.contains("*://*/*") })
        
        if hasAllUrls || hasWildcardHosts {
            print("   🌐 MV3 extension has broad host permissions - content scripts should work!")
            // MV3: Ensure we also grant the host_permissions from manifest
            if let hostPermissions = manifest["host_permissions"] as? [String] {
                print("   📝 MV3 host_permissions found: \(hostPermissions)")
            }
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
        if #available(macOS 15.5, *),
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
                                print("🔧 [ExtensionManager] Re-loading existing extension...")
                                print("   Package path: \(entity.packagePath)")
                                
                                let webExtension = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: entity.packagePath))
                                let extensionContext = WKWebExtensionContext(for: webExtension)
                                
                                print("✅ Existing extension re-loaded")
                                print("   Display name: \(webExtension.displayName ?? "Unknown")")
                                print("   Version: \(webExtension.version ?? "Unknown")")
                                print("   Unique ID: \(extensionContext.uniqueIdentifier)")
                                
                                // Debug extension details and permissions
                                print("ExtensionManager: Loading existing extension '\(webExtension.displayName ?? entity.name)'")
                                print("   Version: \(webExtension.version ?? entity.version)")
                                print("   Requested permissions: \(webExtension.requestedPermissions)")
                                print("   Current permissions: \(extensionContext.currentPermissions)")
                                
                                // Pre-grant common permissions for existing extensions (like Dark Reader)
                                grantCommonPermissions(to: extensionContext, webExtension: webExtension, isExisting: true)
                                
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
        
        if #available(macOS 15.5, *) {
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
    
    /// Install test MV3 extension for generic testing
    func installTestMV3Extension() {
        guard isExtensionSupportAvailable else {
            print("Extension support not available")
            return
        }
        
        let testExtensionPath = "/tmp/test-mv3-extension"
        let testExtensionURL = URL(fileURLWithPath: testExtensionPath)
        
        guard FileManager.default.fileExists(atPath: testExtensionPath) else {
            print("❌ Test MV3 extension not found at: \(testExtensionPath)")
            print("   Run ExtensionManager.shared.createTestMV3Extension() first")
            return
        }
        
        print("🧪 Installing Test MV3 extension...")
        
        installExtension(from: testExtensionURL) { result in
            switch result {
            case .success(let ext):
                print("✅ Successfully installed Test MV3 extension: \(ext.name)")
                print("   Extension ID: \(ext.id)")
                print("   Manifest Version: \(ext.manifestVersion)")
                print("   This extension will:")
                print("     • Change page fonts to Comic Sans MS")
                print("     • Add colorful gradients")
                print("     • Make paragraphs clickable with sparkle effects")
                print("     • Test MAIN/ISOLATED world injection")
                print("     • Show world indicators in corners")
                
                // Enable the extension immediately
                self.enableExtension(ext.id)
                
                // Test MV3 functionality
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.testMV3Functionality()
                }
                
            case .failure(let error):
                print("❌ Failed to install Test MV3 extension: \(error.localizedDescription)")
                self.showErrorAlert(error)
            }
        }
    }
    
    /// Install MV3 Dark Reader extension for testing
    func installMV3DarkReader() {
        guard isExtensionSupportAvailable else {
            print("Extension support not available")
            return
        }
        
        let darkReaderPath = "/Users/jonathancaudill/Downloads/DARKREADERMV3"
        let darkReaderURL = URL(fileURLWithPath: darkReaderPath)
        
        guard FileManager.default.fileExists(atPath: darkReaderPath) else {
            print("❌ Dark Reader MV3 extension not found at: \(darkReaderPath)")
            return
        }
        
        print("🌙 Installing Dark Reader MV3 extension...")
        
        installExtension(from: darkReaderURL) { result in
            switch result {
            case .success(let ext):
                print("✅ Successfully installed Dark Reader MV3: \(ext.name)")
                print("   Extension ID: \(ext.id)")
                print("   Manifest Version: \(ext.manifestVersion)")
                
                // Enable the extension immediately
                self.enableExtension(ext.id)
                
            case .failure(let error):
                print("❌ Failed to install Dark Reader MV3: \(error.localizedDescription)")
                self.showErrorAlert(error)
            }
        }
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
                    <button id="testTabsCreate">Test tabs.create()</button>
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
                
                document.getElementById('testTabsCreate').addEventListener('click', async function() {
                    try {
                        logResult('Testing tabs.create()...');
                        // Test with a simple URL first
                        const newTab = await browser.tabs.create({
                            url: 'https://www.google.com',
                            active: true
                        });
                        logResult(`✅ Created tab with ID: ${newTab.id}`);
                        logResult(`   URL: ${newTab.url}`);
                        
                        // Now test with a webkit-extension URL
                        setTimeout(async () => {
                            try {
                                logResult('Testing webkit-extension URL...');
                                const extTab = await browser.tabs.create({
                                    url: browser.runtime.getURL('popup.html'),
                                    active: true
                                });
                                logResult(`✅ Created extension tab with ID: ${extTab.id}`);
                            } catch (extError) {
                                logResult(`❌ Extension URL error: ${extError.message}`);
                            }
                        }, 1000);
                        
                    } catch (error) {
                        logResult(`❌ tabs.create() error: ${error.message}`);
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
        if #available(macOS 15.5, *), let controller = extensionController {
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
    
    @available(macOS 15.5, *)
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
        
        // Ensure critical permissions at popup time (user-invoked -> activeTab should be granted)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .activeTab)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .scripting)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .tabs)

        // Context visibility checks
        let openTabsCount = extensionContext.openTabs.count
        let openWindowsCount = extensionContext.openWindows.count
        let focusedWin = extensionContext.focusedWindow
        print("   [Diag] Context openTabs: \(openTabsCount) openWindows: \(openWindowsCount) focusedWindow: \(focusedWin != nil ? "yes" : "no")")
        print("   [Diag] Shared config has controller: \(BrowserConfiguration.shared.webViewConfiguration.webExtensionController != nil)")
        if let c = BrowserConfiguration.shared.webViewConfiguration.webExtensionController {
            print("   [Diag] Shared config controller === our controller: \(c === controller)")
        }

        // Check access to current page
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

        // Re-sync controller focus/selection to be extra explicit for scripting target resolution
        if let window = windowAdapter {
            controller.didFocusWindow(window)
            if let active = window.activeTab(for: extensionContext) as? ExtensionTabAdapter {
                controller.didActivateTab(active, previousActiveTab: nil)
                controller.didSelectTabs([active])
                print("   [Diag] Re-synced focus + active tab for scripting target")
                if let url = active.url(for: extensionContext) {
                    let hasAccess = extensionContext.hasAccess(to: url)
                    print("   [Diag] Has access to active URL: \(hasAccess) -> \(url)")
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

            // Diagnostic: compare associated tab vs active tab
            if let assoc = action.associatedTab as? ExtensionTabAdapter {
                print("   [Diag] Action associatedTab adapter: \(ObjectIdentifier(assoc)) for tab '\(assoc.tab.name)'")
            } else {
                print("   [Diag] Action has no associatedTab")
            }
            if let active = windowAdapter?.activeTab(for: extensionContext) as? ExtensionTabAdapter {
                print("   [Diag] Active adapter: \(ObjectIdentifier(active)) for tab '\(active.tab.name)'")
            }
            
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

            // Register a message handler for host-side injection fallback
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "pulseScripting")
            webView.configuration.userContentController.add(self, name: "pulseScripting")

            // Register a diagnostic message handler for verbose logging from popup
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "pulseDiag")
            webView.configuration.userContentController.add(self, name: "pulseDiag")

            // Install a light ResizeObserver to autosize the popover to content
            let resizeScript = """
            (function(){
              try {
                const post = (label, payload) => { try { webkit.messageHandlers.pulseDiag.postMessage({label, payload, phase:'resize'}); } catch(_){} };
                const measure = () => {
                  const d=document, e=d.documentElement, b=d.body;
                  const w = Math.ceil(Math.max(e.scrollWidth, b?b.scrollWidth:0, e.clientWidth));
                  const h = Math.ceil(Math.max(e.scrollHeight, b?b.scrollHeight:0, e.clientHeight));
                  post('popupSize', {w, h});
                };
                new ResizeObserver(measure).observe(document.documentElement);
                window.addEventListener('load', measure);
                setTimeout(measure, 50); setTimeout(measure, 250); setTimeout(measure, 800);
              } catch(_){}
            })();
            """
            let user = WKUserScript(source: resizeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(user)

            // Minimal polyfills for Chromium-only APIs some extensions feature-detect
            let polyfillScript = """
            (function(){
              try {
                // Ensure chrome namespace exists
                window.chrome = window.chrome || {};

                // identity: Safari doesn't support it; recommend opening OAuth in a new tab.
                if (typeof window.chrome.identity === 'undefined') {
                  window.chrome.identity = {
                    launchWebAuthFlow: function(details, callback){
                      try {
                        var url = details && details.url ? details.url : null;
                        var interactive = !!(details && details.interactive);
                        if (url && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pulseIdentity) {
                          window.webkit.messageHandlers.pulseIdentity.postMessage({ url: url, interactive: interactive });
                        }
                      } catch(_){}
                      // Resolve immediately with null to unblock code paths that only check for existence
                      try { if (typeof callback === 'function') callback(null); } catch(_){}
                      return Promise.resolve(null);
                    }
                  };
                }

                // webRequestAuthProvider: Chromium-only, define no-op to satisfy feature checks
                if (typeof window.chrome.webRequestAuthProvider === 'undefined') {
                  window.chrome.webRequestAuthProvider = {
                    addListener: function(){},
                    removeListener: function(){}
                  };
                }
              } catch(_){}
            })();
            """
            let polyfill = WKUserScript(source: polyfillScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(polyfill)

            // Remember which tab this popup should target for host fallbacks
            if let host = webView.url?.host {
                // Prefer the action's associated tab if provided; otherwise use the current active tab
                if let assoc = action.associatedTab as? ExtensionTabAdapter {
                    popupTargetTabs[host] = assoc
                } else if let active = windowAdapter?.activeTab(for: extensionContext) as? ExtensionTabAdapter {
                    popupTargetTabs[host] = active
                }
            }
            
            // Log initial state
            let popupURL = webView.url?.absoluteString ?? "(nil)"
            print("   Popup URL: \"\(popupURL)\"")
            
            // Check document readiness
            webView.evaluateJavaScript("document.readyState") { value, _ in
                let state = (value as? String) ?? "(unknown)"
                print("   Popup document.readyState: \"\(state)\"")
            }
            
            // Ensure extension APIs are available (sync-only to avoid Promise result type)
            let apiCheck = """
            (function(){
              try {
                return {
                  hasBrowser: (typeof browser !== 'undefined'),
                  hasChrome: (typeof chrome !== 'undefined'),
                  hasRuntime: (typeof (browser?.runtime) !== 'undefined') || (typeof (chrome?.runtime) !== 'undefined'),
                  hasStorage: (typeof (browser?.storage?.local) !== 'undefined') || (typeof (chrome?.storage?.local) !== 'undefined'),
                  hasTabs: (typeof (browser?.tabs || chrome?.tabs) !== 'undefined'),
                  hasScriptingAPI: (typeof (browser?.scripting?.executeScript || chrome?.scripting?.executeScript) === 'function'),
                  location: location.href
                };
              } catch(e) { return { error: String(e) }; }
            })();
            """
            
            webView.evaluateJavaScript(apiCheck) { result, error in
                if let error = error {
                    print("   API check error: \(error.localizedDescription)")
                } else {
                    print("   API availability: \(String(describing: result))")
                }
            }

            // MV3: Enhanced polyfill that handles MAIN/ISOLATED worlds properly
            // Maps tabs.executeScript(...) to scripting.executeScript(...) with world support
            // Critical for MV3 extensions like Dark Reader that need MAIN world injection
            let tabsExecuteScriptPolyfill = """
            (function(){
              try {
                const g = (typeof window !== 'undefined' ? window : self);
                const chromeNS = g.chrome || g.browser || {};
                if (!chromeNS.tabs) chromeNS.tabs = {};
                if (!chromeNS.scripting || typeof chromeNS.scripting.executeScript !== 'function') return;
                if (typeof chromeNS.tabs.executeScript === 'function') return; // already provided

                function normalize(tabIdOrDetails, detailsOrCb, maybeCb) {
                  let tabId, details, cb;
                  if (typeof tabIdOrDetails === 'number') {
                    tabId = tabIdOrDetails; details = detailsOrCb; cb = maybeCb;
                  } else {
                    details = tabIdOrDetails; cb = detailsOrCb;
                  }
                  return { tabId, details: details || {}, cb: (typeof cb === 'function') ? cb : null };
                }

                chromeNS.tabs.executeScript = function(tabIdOrDetails, detailsOrCb, maybeCb) {
                  const { tabId, details, cb } = normalize(tabIdOrDetails, detailsOrCb, maybeCb);
                  function buildOpts(realTabId) {
                    const target = { tabId: realTabId, allFrames: !!details.allFrames };
                    if (Number.isInteger(details.frameId)) target.frameIds = [details.frameId];
                    const world = 'MAIN'; // favor page-world compat
                    const opts = { target, world };
                    if (typeof details.code === 'string' && details.code.length) {
                      const src = details.code;
                      opts.func = function(source){ try { (0,eval)(source); } catch(e){ console.error('executeScript eval error', e); } };
                      opts.args = [src];
                    } else if (typeof details.file === 'string') {
                      opts.files = [details.file];
                    } else if (Array.isArray(details.files) && details.files.length) {
                      opts.files = details.files;
                    } else {
                      throw new Error('tabs.executeScript: no code/file specified');
                    }
                    return opts;
                  }
                  async function hostFallback(realTabId) {
                    try {
                      if (!(g.webkit && g.webkit.messageHandlers && g.webkit.messageHandlers.pulseScripting)) throw new Error('no-host-bridge');
                      const details = currentDetails;
                      let code = details && details.code;
                      if (!code && (details.file || (details.files && details.files.length))) {
                        const files = details.file ? [details.file] : details.files;
                        const texts = [];
                        for (const f of files) {
                          const url = (chromeNS.runtime && chromeNS.runtime.getURL) ? chromeNS.runtime.getURL(f) : f;
                          const res = await fetch(url);
                          texts.push(await res.text());
                        }
                        code = texts.join('\n;');
                      }
                      if (typeof code !== 'string' || !code.length) throw new Error('no-code');
                      g.webkit.messageHandlers.pulseScripting.postMessage({ tabId: realTabId, code, world: 'MAIN' });
                      return [];
                    } catch (e) {
                      console.error('hostFallback failed', e);
                      return [];
                    }
                  }

                  let currentDetails = null;

                  function runWithTabId(realTabId) {
                    const base = buildOpts(realTabId);
                    const exec = (opts) => chromeNS.scripting.executeScript(opts);
                    // Try MAIN first; fall back to ISOLATED and then default (no world)
                    const tryMain = exec(base);
                    const tryIso = () => exec(Object.assign({}, base, { world: 'ISOLATED' }));
                    const tryDefault = () => { const c = Object.assign({}, base); delete c.world; return exec(c); };
                    const p = tryMain.catch(() => tryIso()).catch(() => tryDefault()).catch(() => hostFallback(realTabId));
                    if (cb) { p.then((res)=>{ try { cb(res); } catch(_){} }).catch((e)=>{ console.error(e); try { cb(undefined); } catch(_){} }); }
                    return p;
                  }
                  try {
                    if (typeof tabId === 'number') {
                      currentDetails = details;
                      return runWithTabId(tabId);
                    }
                    const tabsNS = (chromeNS.tabs || (chromeNS.browser && chromeNS.browser.tabs));
                    if (tabsNS && typeof tabsNS.query === 'function') {
                      // Prefer Promise if available (MV3), else callback style
                      try {
                        const q = tabsNS.query({active: true, currentWindow: true});
                        if (q && typeof q.then === 'function') {
                          return q.then(tabs => { currentDetails = details; return (tabs && tabs[0] && tabs[0].id != null) ? runWithTabId(tabs[0].id) : Promise.reject(new Error('No active tab found')); });
                        }
                      } catch (_) {}
                      // Callback path
                      return new Promise((resolve, reject) => {
                        try {
                          tabsNS.query({active: true, currentWindow: true}, function(tabs){
                            try {
                              const tid = (tabs && tabs[0] && tabs[0].id != null) ? tabs[0].id : null;
                              if (tid == null) { throw new Error('No active tab found'); }
                              currentDetails = details; resolve(runWithTabId(tid));
                            } catch (e) { reject(e); }
                          });
                        } catch (e) { reject(e); }
                      });
                    }
                    return Promise.reject(new Error('tabs.executeScript: no tabId and cannot determine active tab'));
                  } catch (e) {
                    if (cb) { try { cb(undefined); } catch(_){} }
                    return Promise.reject(e);
                  }
                };

                // Helper: resolve active tabId if missing
                async function resolveActiveTabId() {
                  const tabsNS = (chromeNS.tabs || (chromeNS.browser && chromeNS.browser.tabs));
                  if (!tabsNS) return null;
                  try {
                    const q = tabsNS.query({active: true, currentWindow: true});
                    if (q && typeof q.then === 'function') {
                      const ts = await q; return (ts && ts[0] && ts[0].id != null) ? ts[0].id : null;
                    }
                  } catch (_) {}
                  return await new Promise((resolve)=>{
                    try { tabsNS.query({active:true,currentWindow:true}, (ts)=>{ try { resolve((ts && ts[0] && ts[0].id != null) ? ts[0].id : null); } catch { resolve(null); } }); } catch { resolve(null); }
                  });
                }

                // Wrap MV3 scripting.executeScript to add host fallback and infer target.tabId when missing
                try {
                  const originalExec = chromeNS.scripting.executeScript.bind(chromeNS.scripting);
                  chromeNS.scripting.executeScript = async function(opts){
                    try {
                      const o = Object.assign({}, opts||{});
                      o.target = Object.assign({}, o.target||{});
                      if (o.target.tabId == null) { const tid = await resolveActiveTabId(); if (tid != null) o.target.tabId = tid; }
                      return await originalExec(o);
                    } catch (e) {
                      try {
                        if (!(g.webkit && g.webkit.messageHandlers && g.webkit.messageHandlers.pulseScripting)) throw e;
                        // Build a code string from func/args or fetch files
                        let code = null;
                        if (typeof opts.func === 'function') {
                          const argList = JSON.stringify(Array.isArray(opts.args) ? opts.args : []);
                          code = `(${opts.func})(...${argList})`;
                        } else if (Array.isArray(opts.files) && opts.files.length) {
                          const texts = [];
                          for (const f of opts.files) {
                            const url = (chromeNS.runtime && chromeNS.runtime.getURL) ? chromeNS.runtime.getURL(f) : f;
                            const res = await fetch(url);
                            texts.push(await res.text());
                          }
                          code = texts.join('\n;');
                        }
                        if (!code) throw e;
                        // ensure a tab id for host bridge
                        let hostTid = (opts.target && opts.target.tabId) || await resolveActiveTabId();
                        g.webkit.messageHandlers.pulseScripting.postMessage({ tabId: hostTid || null, code, world: (opts.world||'MAIN'), via: 'scripting.wrap' });
                        return [];
                      } catch (e2) {
                        throw e; // surface original error if fallback unsupported
                      }
                    }
                  }
                } catch(_) {}

                // Wrap MV3 scripting.insertCSS to infer target.tabId and provide host fallback
                try {
                  if (chromeNS.scripting && typeof chromeNS.scripting.insertCSS === 'function') {
                    const originalInsert = chromeNS.scripting.insertCSS.bind(chromeNS.scripting);
                    chromeNS.scripting.insertCSS = async function(opts){
                      try {
                        const o = Object.assign({}, opts||{});
                        o.target = Object.assign({}, o.target||{});
                        if (o.target.tabId == null) { const tid = await resolveActiveTabId(); if (tid != null) o.target.tabId = tid; }
                        // Apple's engine may not support world for CSS; don't set it here
                        return await originalInsert(o);
                      } catch (e) {
                        try {
                          if (!(g.webkit && g.webkit.messageHandlers && g.webkit.messageHandlers.pulseScripting)) throw e;
                          // Build CSS text from css or files
                          let css = opts && opts.css;
                          if (!css && Array.isArray(opts?.files) && opts.files.length) {
                            const texts = [];
                            for (const f of opts.files) {
                              const url = (chromeNS.runtime && chromeNS.runtime.getURL) ? chromeNS.runtime.getURL(f) : f;
                              const res = await fetch(url);
                              texts.push(await res.text());
                            }
                            css = texts.join('\n');
                          }
                          if (typeof css !== 'string' || !css.length) throw e;
                          const code = `(() => { try { const el = document.createElement('style'); el.textContent = ${JSON.stringify(css)}; document.documentElement.appendChild(el); return true; } catch(e){ return false; } })();`;
                          let hostTid = (opts && opts.target && opts.target.tabId) || await resolveActiveTabId();
                          g.webkit.messageHandlers.pulseScripting.postMessage({ tabId: hostTid || null, code, world: 'MAIN', via: 'scripting.insertCSS.wrap' });
                          return [];
                        } catch (e2) {
                          throw e;
                        }
                      }
                    }
                  }
                } catch(_) {}

                // MV2: tabs.insertCSS -> MV3: scripting.insertCSS
                if (typeof chromeNS.tabs.insertCSS !== 'function' && typeof chromeNS.scripting.insertCSS === 'function') {
                  chromeNS.tabs.insertCSS = function(tabIdOrDetails, detailsOrCb, maybeCb) {
                    const { tabId, details, cb } = normalize(tabIdOrDetails, detailsOrCb, maybeCb);
                    const target = { tabId: tabId };
                    const css = (typeof details.code === 'string') ? details.code : null;
                    const files = details.file ? [details.file] : (details.files||null);
                    if (!css && (!files || !files.length)) {
                      const err = new Error('tabs.insertCSS: no code/file specified');
                      if (cb) { try { cb(); } catch(_){} }
                      return Promise.reject(err);
                    }
                    const opts = { target };
                    if (css) opts.css = css; else opts.files = files;
                    const p = chromeNS.scripting.insertCSS(opts);
                    if (cb) { p.then(()=>{ try { cb(); } catch(_){} }).catch((e)=>{ console.error(e); try { cb(); } catch(_){} }); }
                    return p;
                  };
                }

                // MV2: tabs.removeCSS -> MV3: scripting.removeCSS
                if (typeof chromeNS.tabs.removeCSS !== 'function' && typeof chromeNS.scripting.removeCSS === 'function') {
                  chromeNS.tabs.removeCSS = function(tabIdOrDetails, detailsOrCb, maybeCb) {
                    const { tabId, details, cb } = normalize(tabIdOrDetails, detailsOrCb, maybeCb);
                    const target = { tabId: tabId };
                    const css = (typeof details.code === 'string') ? details.code : null;
                    const files = details.file ? [details.file] : (details.files||null);
                    if (!css && (!files || !files.length)) {
                      const err = new Error('tabs.removeCSS: no code/file specified');
                      if (cb) { try { cb(); } catch(_){} }
                      return Promise.reject(err);
                    }
                    const opts = { target };
                    if (css) opts.css = css; else opts.files = files;
                    const p = chromeNS.scripting.removeCSS(opts);
                    if (cb) { p.then(()=>{ try { cb(); } catch(_){} }).catch((e)=>{ console.error(e); try { cb(); } catch(_){} }); }
                    return p;
                  };
                }

                // Expose patched namespaces back to window
                if (!g.chrome && (g.browser || chromeNS)) { g.chrome = chromeNS; }
                if (!g.browser && g.chrome) { g.browser = g.chrome; }
              } catch (e) {
                console.error('tabs.executeScript polyfill error', e);
              }
            })();
            """

            webView.evaluateJavaScript(tabsExecuteScriptPolyfill) { _, error in
                if let error = error {
                    print("   Polyfill injection error: \(error.localizedDescription)")
                } else {
                    print("   Installed tabs.executeScript -> scripting.executeScript polyfill in popup context")
                }
            }

            // Probe end-to-end MAIN-world injection capability on active tab
            let worldProbe = """
            (async function(){
              try {
                const tabsNS = (browser?.tabs || chrome?.tabs);
                const scriptingNS = (browser?.scripting || chrome?.scripting);
                if (!tabsNS || !scriptingNS) return 'no-apis';
                let tabs;
                try { tabs = await tabsNS.query({active:true, currentWindow:true}); } catch(_) {
                  // callback fallback
                  tabs = await new Promise((resolve,reject)=>{ try { tabsNS.query({active:true,currentWindow:true}, (t)=>resolve(t)); } catch(e){ reject(e); } });
                }
                const t = tabs && tabs[0];
                if (!t || t.id == null) return 'no-tab';
                const res = await scriptingNS.executeScript({ target: { tabId: t.id }, world: 'MAIN', func: function(){ try { document.documentElement.setAttribute('data-pulse-probe','1'); return 'ok'; } catch(e){ return 'err:'+String(e); } } });
                return 'ok:' + (res && res.length ? 'len='+res.length : 'nores');
              } catch(e) {
                return 'err:' + (e && (e.message||String(e)));
              }
            })();
            """

            webView.evaluateJavaScript(worldProbe) { result, error in
                if let error = error {
                    print("   World probe error: \(error.localizedDescription)")
                } else {
                    print("   World probe result: \(String(describing: result))")
                }
            }

            // After a short delay, verify in the page WebView whether the probe attribute was set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                if let windowAdapter = self.windowAdapter,
                   let activeTab = windowAdapter.activeTab(for: extensionContext),
                   let tabAdapter = activeTab as? ExtensionTabAdapter {
                    let pageWV = tabAdapter.tab.webView
                    pageWV.evaluateJavaScript("document.documentElement.getAttribute('data-pulse-probe')") { val, err in
                        if let err = err {
                            print("   Page probe read error: \(err.localizedDescription)")
                        } else {
                            print("   Page probe attribute: \(String(describing: val))")
                        }
                    }
                }
            }
        } else {
            print("   No popupWebView present on action")
        }
        
        // Present the popover on main thread
        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
            // Remember this popover for autosizing based on popup webView host UUID
            if let host = action.popupWebView?.url?.host {
                self.activePopoversByHost[host] = popover
            }
            
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

    // MARK: - WKScriptMessageHandler (popup bridge)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "pulseScripting" {
            // Identify the extension by popup URL host
            var extUUID: String? = nil
            if let urlString = (message.webView?.url?.absoluteString),
               let url = URL(string: urlString),
               url.scheme == "webkit-extension" {
                extUUID = url.host
            }
            guard let extUUID, let target = popupTargetTabs[extUUID] else {
                print("   [Bridge] No popup target tab found for message")
                return
            }
            guard let dict = message.body as? [String: Any] else { return }
            let code = dict["code"] as? String
            let world = (dict["world"] as? String) ?? "MAIN"
            guard let js = code, !js.isEmpty else { return }
            let pageWV = target.tab.webView
            pageWV.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("   [Bridge] Injection error (world=\(world)): \(error.localizedDescription)")
                } else {
                    print("   [Bridge] Injected code into page via host bridge (world=\(world))")
                }
            }
            return
        }
        if message.name == "pulseIdentity" {
            // Open OAuth in a new tab per Apple's guidance for Safari
            if let dict = message.body as? [String: Any], let urlString = dict["url"] as? String, let url = URL(string: urlString) {
                if let bm = browserManagerRef {
                    let space = bm.tabManager.currentSpace
                    _ = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
                }
            }
            return
        }
        if message.name == "pulseDiag" {
            // Handle autosize and diagnostics from popup
            guard let dict = message.body as? [String: Any] else { print("[Diag] Non-dictionary payload received"); return }
            let label = dict["label"] as? String ?? "?"
            if label == "popupSize" {
                if let payload = dict["payload"] as? [String: Any] {
                    let w = (payload["w"] as? NSNumber)?.doubleValue ?? 0
                    let h = (payload["h"] as? NSNumber)?.doubleValue ?? 0
                    if w > 0 && h > 0 {
                        // Clamp to reasonable bounds
                        let cw = max(280.0, min(w, 700.0))
                        let ch = max(120.0, min(h, 800.0))
                        if let host = message.webView?.url?.host, let pop = activePopoversByHost[host] {
                            // Update content size on main thread
                            DispatchQueue.main.async {
                                if pop.contentSize != NSSize(width: cw, height: ch) {
                                    pop.contentSize = NSSize(width: cw, height: ch)
                                }
                            }
                        }
                    }
                }
            } else {
                let phase = dict["phase"] as? String ?? "?"
                print("[Diag] phase=\(phase) label=\(label) payload=\(dict)")
            }
            return
        }
    }
    
    // MARK: - WKNavigationDelegate (popup diagnostics)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didStartProvisionalNavigation: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Started loading: \(urlString)")
        
        if urlString.contains("webkit-extension://") {
            print("   🔧 This is a webkit-extension URL - checking WebView config...")
            print("   Has extension controller: \(webView.configuration.webExtensionController != nil)")
            if let controller = webView.configuration.webExtensionController {
                print("   Controller contexts: \(controller.extensionContexts.count)")
                
                // Extract UUID from URL
                if let url = URL(string: urlString), let host = url.host {
                    print("   Extension UUID: \(host)")
                    
                    // Check if this extension context exists
                    let matchingContext = controller.extensionContexts.first { context in
                        context.uniqueIdentifier == host
                    }
                    if let context = matchingContext {
                        print("   ✅ Found matching extension context")
                        print("   Extension name: \(context.webExtension.displayName ?? "Unknown")")
                        print("   Extension version: \(context.webExtension.version ?? "Unknown")")
                        print("   Context unique ID: \(context.uniqueIdentifier)")
                    } else {
                        print("   ❌ No matching extension context found for UUID: \(host)")
                        print("   Available contexts:")
                        for context in controller.extensionContexts {
                            print("     - \(context.uniqueIdentifier): \(context.webExtension.displayName ?? "Unknown")")
                        }
                    }
                }
            } else {
                print("   ❌ No extension controller found on WebView!")
            }
        }
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

        // Patch scripting.executeScript in popup context to avoid hard failures on unsupported targets
        let safeScriptingPatch = """
        (function(){
          try {
            if (typeof chrome !== 'undefined' && chrome.scripting && typeof chrome.scripting.executeScript === 'function') {
              const originalExec = chrome.scripting.executeScript.bind(chrome.scripting);
              chrome.scripting.executeScript = async function(opts){
                try { return await originalExec(opts); }
                catch (e) { console.warn('shim: executeScript failed', e); return []; }
              };
            }
            if (typeof chrome !== 'undefined' && (!chrome.tabs || typeof chrome.tabs.executeScript !== 'function') && chrome.scripting && typeof chrome.scripting.executeScript === 'function') {
              chrome.tabs = chrome.tabs || {};
              chrome.tabs.executeScript = function(tabIdOrDetails, detailsOrCb, maybeCb){
                function normalize(a,b,c){ let tabId, details, cb; if (typeof a==='number'){ tabId=a; details=b; cb=c; } else { details=a; cb=b; } return {tabId, details: details||{}, cb: (typeof cb==='function')?cb:null}; }
                const { tabId, details, cb } = normalize(tabIdOrDetails, detailsOrCb, maybeCb);
                const target = { tabId: tabId||undefined };
                const files = details && (details.file ? [details.file] : details.files);
                const code = details && details.code;
                const opts = { target };
                if (Array.isArray(files) && files.length) opts.files = files; else if (typeof code==='string') { opts.func = function(src){ try{(0,eval)(src);}catch(e){}}; opts.args=[code]; } else { const p = Promise.resolve([]); if (cb) { try{cb([]);}catch(_){} } return p; }
                const p = chrome.scripting.executeScript(opts);
                if (cb) { p.then(r=>{ try{cb(r);}catch(_){} }).catch(_=>{ try{cb([]);}catch(_){} }); }
                return p;
              };
            }
          } catch(_){}
        })();
        """
        webView.evaluateJavaScript(safeScriptingPatch) { _, err in
            if let err = err { print("[Popup] safeScriptingPatch error: \(err.localizedDescription)") }
        }
        
        // Note: Skipping automatic tabs.query test to avoid potential recursion issues
        // Extensions will call tabs.query naturally, and we can debug through console
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didFail: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log("[Error] Navigation failed: \(error.localizedDescription)")
        
        if urlString.contains("webkit-extension://") {
            print("   💥 webkit-extension URL failed to load!")
            print("   Error domain: \(error._domain)")
            print("   Error code: \(error._code)")
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didFailProvisional: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log("[Error] Provisional navigation failed: \(error.localizedDescription)")
        
        if urlString.contains("webkit-extension://") {
            print("   💥 webkit-extension URL failed to start loading!")
            print("   Error domain: \(error._domain)")
            print("   Error code: \(error._code)")
        }
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[Popup] content process terminated")
        PopupConsole.shared.log("[Critical] WebView process terminated")
    }

    // MARK: - Windows exposure (tabs/windows APIs)
    private var lastFocusedWindowCall: Date = Date.distantPast
    private var lastOpenWindowsCall: Date = Date.distantPast
    
    @available(macOS 15.5, *)
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

    @available(macOS 15.5, *)
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
    @available(macOS 15.5, *)
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
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        print("🆕 [DELEGATE] openNewTabUsing called!")
        print("   URL: \(configuration.url?.absoluteString ?? "nil")")
        print("   Should be active: \(configuration.shouldBeActive)")
        print("   Should be pinned: \(configuration.shouldBePinned)")
        
        // Special handling for extension page URLs (options, popup, etc.)
        if let url = configuration.url?.absoluteString,
           url.contains("webkit-extension://") {
            print("🎛️ [DELEGATE] Extension requesting internal page: \(url)")
            
            // Check if this is an options page - present it natively like a popup
            if url.contains("/options") || url.contains("/settings") {
                print("   🎛️ Presenting options page natively in popup window")
                
                // Present options page in a native popup window like the regular popup
                DispatchQueue.main.async {
                    // Create a native options window using the same mechanism as popups
                    let window = NSApp.keyWindow ?? NSApp.mainWindow
                    if let window = window {
                        
                        // Create a popover for the options page
                        let popover = NSPopover()
                        popover.contentSize = NSSize(width: 800, height: 600) // Larger for options
                        popover.behavior = .transient
                        popover.animates = true
                        
                        // Create WebView with the same configuration that works for popups
                        let config = WKWebViewConfiguration()
                        if let controller = self.nativeController {
                            config.webExtensionController = controller
                            print("   ✅ Set extension controller on WebView config")
                        }
                        config.preferences.javaScriptEnabled = true
                        config.defaultWebpagePreferences.allowsContentJavaScript = true
                        
                        let webView = WKWebView(frame: NSRect(origin: .zero, size: popover.contentSize), configuration: config)
                        
                        // Load the options page directly from the extension's file system
                        // Extract the UUID from the webkit-extension URL
                        if let host = URL(string: url)?.host,
                           let controller = self.nativeController,
                           let context = controller.extensionContexts.first(where: { $0.uniqueIdentifier == host }) {
                            
                            // Get the extension's base URL (file system path)
                            let extensionBaseURL = context.baseURL
                            let optionsFilePath = extensionBaseURL.appendingPathComponent("ui/options/index.html")
                            
                            print("   🔧 Loading options page from file system: \(optionsFilePath)")
                            
                            if FileManager.default.fileExists(atPath: optionsFilePath.path) {
                                webView.loadFileURL(optionsFilePath, allowingReadAccessTo: extensionBaseURL)
                                print("   ✅ Loading options page from file system")
                            } else {
                                print("   ❌ Options file not found at: \(optionsFilePath.path)")
                                // Try loading the webkit-extension URL as fallback
                                if let optionsURL = URL(string: url) {
                                    webView.load(URLRequest(url: optionsURL))
                                }
                            }
                        } else {
                            print("   ❌ Could not find extension context for URL")
                            // Fallback to webkit-extension URL
                            if let optionsURL = URL(string: url) {
                                webView.load(URLRequest(url: optionsURL))
                            }
                        }
                        
                        // Create view controller and present
                        let viewController = NSViewController()
                        viewController.view = webView
                        popover.contentViewController = viewController
                        
                        // Show the popover
                        if let contentView = window.contentView {
                            let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
                            popover.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                        }
                        
                        print("   ✅ Presented options page in native popover")
                    }
                    
                    // Return success to the extension
                    completionHandler(nil, nil)
                }
                return
            }
            
            print("   🔧 Allowing WebView to serve extension resource directly")
        }
        
        guard let bm = browserManagerRef else { 
            print("❌ Browser manager reference is nil")
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return 
        }

        let targetURL = configuration.url
        if let url = targetURL {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
            print("✅ Created new tab: \(newTab.name)")
            
            // Return the created tab adapter to the extension
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
            return
        }
        // No URL specified — create a blank tab
        print("⚠️ No URL specified, creating blank tab")
        let space = bm.tabManager.currentSpace
        let newTab = bm.tabManager.createNewTab(in: space)
        if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
        print("✅ Created blank tab: \(newTab.name)")
        
        // Return the created tab adapter to the extension
        let tabAdapter = self.stableAdapter(for: newTab)
        completionHandler(tabAdapter, nil)
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        print("🆕 [DELEGATE] openNewWindowUsing called!")
        print("   Tab URLs: \(configuration.tabURLs.map { $0.absoluteString })")
        
        guard let bm = browserManagerRef else { 
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return 
        }
        
        // Create a new space to emulate a separate window in our UI
        let newSpace = bm.tabManager.createSpace(name: "Window")
        if let firstURL = configuration.tabURLs.first {
            _ = bm.tabManager.createNewTab(url: firstURL.absoluteString, in: newSpace)
        } else {
            _ = bm.tabManager.createNewTab(in: newSpace)
        }
        bm.tabManager.setActiveSpace(newSpace)
        
        // Return the window adapter
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        print("✅ Created new window (space): \(newSpace.name)")
        completionHandler(windowAdapter, nil)
    }

    // Open the extension's options page in a new tab
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        print("🆕 [DELEGATE] openOptionsPageFor called!")
        print("   Extension: \(extensionContext.webExtension.displayName ?? "Unknown")")
        
        guard let bm = browserManagerRef else { 
            print("❌ Browser manager reference is nil")
            completionHandler(NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return 
        }
        
        // Prefer SDK-provided URL if available; otherwise compute from manifest
        if let url = (extensionContext as AnyObject).value(forKey: "optionsPageURL") as? URL ?? self.computeOptionsPageURL(for: extensionContext) {
            print("✅ Opening options page: \(url.absoluteString)")
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
            bm.tabManager.setActiveTab(newTab)
            print("✅ Created options page tab: \(newTab.name)")
            completionHandler(nil)
        } else {
            print("❌ No options page URL found for extension")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No options page URL found for extension"]))
        }
    }

    // Resolve options page URL from manifest as a fallback for SDKs that don't expose optionsPageURL
    @available(macOS 15.5, *)
    private func computeOptionsPageURL(for context: WKWebExtensionContext) -> URL? {
        print("🔍 [computeOptionsPageURL] Looking for options page...")
        print("   Extension: \(context.webExtension.displayName ?? "Unknown")")
        print("   Unique ID: \(context.uniqueIdentifier)")
        
        // Try to map the context back to our InstalledExtension via dictionary identity
        if let extId = extensionContexts.first(where: { $0.value === context })?.key,
           let inst = installedExtensions.first(where: { $0.id == extId }) {
            print("   Found installed extension: \(inst.name)")
            
            // MV3/MV2: options_ui.page; MV2 legacy: options_page
            var pagePath: String?
            if let options = inst.manifest["options_ui"] as? [String: Any], let p = options["page"] as? String, !p.isEmpty {
                pagePath = p
                print("   Found options_ui.page: \(p)")
            } else if let p = inst.manifest["options_page"] as? String, !p.isEmpty {
                pagePath = p
                print("   Found options_page: \(p)")
            } else {
                print("   No options page declared in manifest, checking common paths...")
                
                // Fallback: Check for common options page paths
                let commonPaths = [
                    "ui/options/index.html",
                    "options/index.html", 
                    "options.html",
                    "settings.html"
                ]
                
                for path in commonPaths {
                    let fullPath = URL(fileURLWithPath: inst.packagePath).appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: fullPath.path) {
                        pagePath = path
                        print("   ✅ Found options page at: \(path)")
                        break
                    }
                }
            }
            
            if let page = pagePath {
                let host = context.uniqueIdentifier
                let urlString = "webkit-extension://\(host)/\(page)"
                print("✅ Generated options URL: \(urlString)")
                return URL(string: urlString)
            } else {
                print("❌ No options page found in manifest or common paths")
                print("   Manifest keys: \(inst.manifest.keys.sorted())")
            }
        } else {
            print("❌ Could not find installed extension for context")
        }
        return nil
    }
    @available(macOS 15.5, *)
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

    // URL-specific access prompts (used for cross-origin network requests from extension contexts)
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)? ,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        // Temporarily grant all requested URLs to unblock background networking for popular extensions
        // TODO: replace with a user-facing prompt + persistence
        print("[ExtensionManager] Granting URL access to: \(urls.map{ $0.absoluteString })")
        completionHandler(urls, nil)
    }
    
    // MARK: - URL Scheme Handler Testing
    
    /// Test the webkit-extension URL scheme handler with an existing extension
    @available(macOS 15.4, *)
    func testWebKitExtensionURLSchemeHandler() {
        print("=== WebKit Extension URL Scheme Handler Test ===")
        
        guard isExtensionSupportAvailable else {
            print("❌ Extension support not available")
            return
        }
        
        // Test with the first available extension
        guard let firstExtension = installedExtensions.first else {
            print("❌ No extensions installed for testing")
            return
        }
        
        let extensionUUID = firstExtension.id
        print("🧪 Testing with extension UUID: \(extensionUUID)")
        
        // Test various URLs
        let testURLs = [
            "webkit-extension://\(extensionUUID)/popup.html",
            "webkit-extension://\(extensionUUID)/manifest.json",
            "webkit-extension://\(extensionUUID)/css/popup.css",
            "webkit-extension://\(extensionUUID)/js/popup.js",
            "webkit-extension://\(extensionUUID)/",  // Should default to index.html
            "webkit-extension://\(extensionUUID)/nonexistent.html"  // Should fail
        ]
        
        for urlString in testURLs {
            if let url = URL(string: urlString) {
                testSingleWebKitExtensionURL(url)
            }
        }
        
        print("=== WebKit Extension URL Scheme Handler Test Complete ===")
    }
    
    /// List all installed extensions with their UUIDs for easy testing
    func listInstalledExtensionsForTesting() {
        print("=== Installed Extensions ===")
        
        if installedExtensions.isEmpty {
            print("❌ No extensions installed")
            return
        }
        
        for (index, extension) in installedExtensions.enumerated() {
            print("\(index + 1). \(extension.name)")
            print("   UUID: \(extension.id)")
            print("   Version: \(extension.version)")
            print("   Manifest Version: \(extension.manifestVersion)")
            print("   Enabled: \(extension.isEnabled)")
            print("")
        }
        
        print("Use ExtensionManager.shared.testWebKitExtensionURLSchemeHandler() to test URL scheme handler")
    }
    
    @available(macOS 15.4, *)
    private func testSingleWebKitExtensionURL(_ url: URL) {
        print("🔍 Testing URL: \(url.absoluteString)")
        
        // Create a test WebView with the configured URL scheme handler
        let webView = WKWebView(frame: .zero, configuration: BrowserConfiguration.shared.webViewConfiguration)
        
        // Create a simple navigation delegate to track results
        let testDelegate = WebKitExtensionTestDelegate()
        webView.navigationDelegate = testDelegate
        
        // Load the URL
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Give it a moment to load and then check results
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            testDelegate.printResults(for: url)
        }
    }
}

// MARK: - Test Helper Classes

@available(macOS 15.4, *)
class WebKitExtensionTestDelegate: NSObject, WKNavigationDelegate {
    private var loadStartTime: Date?
    private var lastError: Error?
    private var didFinishLoading = false
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadStartTime = Date()
        didFinishLoading = false
        lastError = nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoading = true
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastError = error
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastError = error
    }
    
    func printResults(for url: URL) {
        let elapsed = loadStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        if let error = lastError {
            print(String(format: "   ❌ Failed to load (%.2fs): %@", elapsed, error.localizedDescription))
        } else if didFinishLoading {
            print(String(format: "   ✅ Successfully loaded (%.2fs)", elapsed))
        } else {
            print(String(format: "   ⏳ Still loading or timed out (%.2fs)", elapsed))
        }
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
