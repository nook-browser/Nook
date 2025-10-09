//
//  ExtensionManager.swift
//  Nook
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
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    // Scope note: Installed/enabled state is global across profiles; extension storage/state
    // (chrome.storage, cookies, etc.) is isolated per-profile via profile-specific data stores.
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private var actionAnchors: [String: [WeakAnchor]] = [:]
    // Keep options windows alive per extension id
    private var optionsWindows: [String: NSWindow] = [:]
    // Stable adapters for tabs/windows used when notifying controller events
    private var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    internal weak var windowAdapter: ExtensionWindowAdapter?
    private weak var browserManagerRef: BrowserManager?
    // Whether to auto-resize extension action popovers to content. Disabled per UX preference.
    private let shouldAutoSizeActionPopups: Bool = false

    // No preference for action popups-as-tabs; keep native popovers per Apple docs
    
    let context: ModelContext
    
    // Profile-aware extension storage
    private var profileExtensionStores: [UUID: WKWebsiteDataStore] = [:]
    var currentProfileId: UUID?
    
    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable = ExtensionUtils.isExtensionSupportAvailable
        super.init()

        if isExtensionSupportAvailable {
            setupExtensionController()
            loadInstalledExtensions()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // MEMORY LEAK FIX: Clean up all extension contexts and break circular references
        extensionContexts.removeAll()
        tabAdapters.removeAll()
        actionAnchors.removeAll()

        // Close all options windows
        for (_, window) in optionsWindows {
            window.close()
        }
        optionsWindows.removeAll()

        // Clean up window adapter
        windowAdapter = nil

        // Unload extension controller
        if let controller = extensionController {
            for (_, context) in extensionContexts {
                try? controller.unload(context)
            }
        }
        extensionController = nil

        print("🧹 [ExtensionManager] Cleaned up all extension resources")
    }
    
    // MARK: - Setup
    
    private func setupExtensionController() {
        // Use persistent controller configuration with stable identifier
        let config: WKWebExtensionController.Configuration
        if let idString = UserDefaults.standard.string(forKey: "Nook.WKWebExtensionController.Identifier"),
           let uuid = UUID(uuidString: idString) {
            config = WKWebExtensionController.Configuration(identifier: uuid)
        } else {
            let uuid = UUID()
            UserDefaults.standard.set(uuid.uuidString, forKey: "Nook.WKWebExtensionController.Identifier")
            config = WKWebExtensionController.Configuration(identifier: uuid)
        }
        
        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        
        // Store controller reference first
        self.extensionController = controller
        
        let sharedWebConfig = BrowserConfiguration.shared.webViewConfiguration
        
        // Create or select a persistent data store for extensions.
        // If we already have a profile context, use a profile-specific store; otherwise use a shared fallback.
        let extensionDataStore: WKWebsiteDataStore
        if let pid = currentProfileId {
            extensionDataStore = getExtensionDataStore(for: pid)
        } else {
            // Fallback shared persistent store until a profile is assigned
            if #available(macOS 15.4, *) {
                extensionDataStore = WKWebsiteDataStore(forIdentifier: config.identifier!)
            } else {
                extensionDataStore = WKWebsiteDataStore.default()
            }
        }
        
        // Verify data store is properly initialized
        if !extensionDataStore.isPersistent {
            print("⚠️ Warning: Extension data store is not persistent - this may cause storage issues")
        }
        
        controller.configuration.defaultWebsiteDataStore = extensionDataStore
        controller.configuration.webViewConfiguration = sharedWebConfig
        
        print("ExtensionManager: WKWebExtensionController configured with persistent storage identifier: \(config.identifier?.uuidString ?? "none")")
        print("   Extension data store is persistent: \(extensionDataStore.isPersistent)")
        print("   Extension data store ID: \(extensionDataStore.identifier?.uuidString ?? "none")")
        print("   App WebViews use separate default data store for normal browsing")
        
        print("   Native storage types supported: .local, .session, .synchronized")
        print("   World support (MAIN/ISOLATED): \(ExtensionUtils.isWorldInjectionSupported)")
        
        // Handle macOS 15.4+ ViewBridge issues with delayed delegate assignment
        if #available(macOS 15.4, *) {
            print("⚠️ Running on macOS 15.4+ - using delayed delegate assignment to avoid ViewBridge issues")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                controller.delegate = self
            }
        } else {
            controller.delegate = self
        }
        
        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject
        if #available(macOS 15.5, *) {
            sharedWebConfig.webExtensionController = controller
            
            sharedWebConfig.preferences.javaScriptEnabled = true
            
            print("ExtensionManager: Configured shared WebView configuration with extension controller")
            
            // Update existing WebViews with controller
            updateExistingWebViewsWithController(controller)
        }
        
        extensionController = controller
        
        // Verify storage is working after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.verifyExtensionStorage(self.currentProfileId)
        }
        
        print("ExtensionManager: Native WKWebExtensionController initialized and configured")
        print("   Controller ID: \(config.identifier?.uuidString ?? "none")")
        print("   Data store: \(controller.configuration.defaultWebsiteDataStore)")
    }
    
    
    /// Verify extension storage is working properly
    private func verifyExtensionStorage(_ profileId: UUID? = nil) {
        guard let controller = extensionController else { return }
        
        guard let dataStore = controller.configuration.defaultWebsiteDataStore else {
            print("❌ Extension Storage Verification: No data store available.")
            return
        }
        if let pid = profileId {
            print("📊 Extension Storage Verification (profile=\(pid.uuidString)):")
        } else {
            print("📊 Extension Storage Verification:")
        }
        print("   Data store is persistent: \(dataStore.isPersistent)")
        print("   Data store identifier: \(dataStore.identifier?.uuidString ?? "nil")")
        
        // Test storage accessibility
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            DispatchQueue.main.async {
                print("   Storage records available: \(records.count)")
                if records.count > 0 {
                    print("   ✅ Extension storage appears to be working")
                } else {
                    print("   ⚠️ No storage records found - this may be normal for new installations")
                }
            }
        }
    }

    // MARK: - Profile-aware Data Store Management
    private func getExtensionDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        if let store = profileExtensionStores[profileId] {
            return store
        }
        // Use a persistent store identified by the profile UUID for deterministic mapping when available
        let store: WKWebsiteDataStore
        if #available(macOS 15.4, *) {
            store = WKWebsiteDataStore(forIdentifier: profileId)
        } else {
            store = WKWebsiteDataStore.default()
        }
        profileExtensionStores[profileId] = store
        print("🔧 [ExtensionManager] Created/loaded extension data store for profile=\(profileId.uuidString) (persistent=\(store.isPersistent))")
        return store
    }

    func switchProfile(_ profileId: UUID) {
        guard let controller = extensionController else { return }
        let store = getExtensionDataStore(for: profileId)
        controller.configuration.defaultWebsiteDataStore = store
        currentProfileId = profileId
        print("🔁 [ExtensionManager] Switched controller data store to profile=\(profileId.uuidString)")
        // Verify storage on the new profile
        verifyExtensionStorage(profileId)
    }

    func clearExtensionData(for profileId: UUID) {
        let store = getExtensionDataStore(for: profileId)
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            Task { @MainActor in
                if records.isEmpty {
                    print("🧹 [ExtensionManager] No extension data records to clear for profile=\(profileId.uuidString)")
                } else {
                    print("🧹 [ExtensionManager] Clearing \(records.count) extension data records for profile=\(profileId.uuidString)")
                }
                await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
            }
        }
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
            guard let webView = tab.webView else { continue }
            
            if webView.configuration.webExtensionController !== controller {
                print("  📝 Updating WebView for tab: \(tab.name)")
                webView.configuration.webExtensionController = controller
                updatedCount += 1
                
                webView.configuration.preferences.javaScriptEnabled = true
            }
        }
        
        print("✅ Updated \(updatedCount) existing WebViews with extension controller")
        
        if updatedCount > 0 {
            print("💡 Content script injection should now work on existing tabs")
        }
    }

    
    // MARK: - MV3 Support Methods
    
    // Note: commonPermissions array removed - now using minimalSafePermissions for better security
    
    /// Grant only minimal safe permissions by default - all others require user consent
    private func grantMinimalSafePermissions(to extensionContext: WKWebExtensionContext, webExtension: WKWebExtension, isExisting: Bool = false) {
        let existingLabel = isExisting ? " for existing extension" : ""
        
        // SECURITY FIX: Only grant absolutely essential permissions by default
        // These are required for basic extension functionality and are considered safe
        
        // Grant only basic permissions that are essential for extension operation
        let minimalSafePermissions: Set<WKWebExtension.Permission> = [
            .storage,  // Required for basic extension storage
            .alarms    // Required for basic extension functionality
        ]
        
        for permission in minimalSafePermissions {
            if webExtension.requestedPermissions.contains(permission) {
                if !isExisting || !extensionContext.currentPermissions.contains(permission) {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
                    print("   ✅ Granted minimal safe permission: \(permission)\(existingLabel)")
                }
            }
        }
        
        // SECURITY FIX: Do NOT auto-grant potentially dangerous permissions
        // These require explicit user consent:
        // - .tabs (can access all tab data)
        // - .activeTab (can access current tab)
        // - .scripting (can inject scripts)
        // - .contextMenus (can modify browser UI)
        // - .declarativeNetRequest (can modify network requests)
        // - .webNavigation (can monitor navigation)
        // - .cookies (can access cookies)
        
        print("   🔒 Potentially sensitive permissions require user consent:")
        let sensitivePermissions = webExtension.requestedPermissions.subtracting(minimalSafePermissions)
        for permission in sensitivePermissions {
            print("      - \(permission) (requires user approval)")
        }
        
        // Note: All other permissions will be handled by user consent prompts
    }
    
    /// Grant common permissions and MV2 compatibility for an extension context (DEPRECATED - use grantMinimalSafePermissions)
    private func grantCommonPermissions(to extensionContext: WKWebExtensionContext, webExtension: WKWebExtension, isExisting: Bool = false) {
        // This method is kept for backward compatibility but should not be used
        // Use grantMinimalSafePermissions instead for better security
        grantMinimalSafePermissions(to: extensionContext, webExtension: webExtension, isExisting: isExisting)
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
        
        // SECURITY FIX: Only grant minimal safe permissions by default
        // All other permissions require explicit user consent
        grantMinimalSafePermissions(to: extensionContext, webExtension: webExtension)
        
        // SECURITY FIX: Do NOT auto-grant host permissions - require user consent
        print("   🔒 Host permissions require user consent - not auto-granted")
        let hasAllUrls = webExtension.requestedPermissionMatchPatterns.contains(where: { $0.description.contains("all_urls") })
        let hasWildcardHosts = webExtension.requestedPermissionMatchPatterns.contains(where: { $0.description.contains("*://*/*") })
        
        if hasAllUrls || hasWildcardHosts {
            print("   ⚠️ Extension requests broad host permissions - will prompt user")
            // MV3: Log host_permissions from manifest for transparency
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
        
        func getLocaleText(key: String) -> String? {
            guard let manifestValue = manifest[key] as? String else {
                return nil
            }
            
            if manifestValue.hasPrefix("__MSG_") {
                let localesDirectory = destinationDir.appending(path: "_locales")
                guard FileManager.default.fileExists(atPath: localesDirectory.path(percentEncoded: false)) else {
                    return nil
                }
                
                var pathToDirectory: URL? = nil
                
                do {
                    let items = try FileManager.default.contentsOfDirectory(at: localesDirectory, includingPropertiesForKeys: nil)
                    for item in items {
                        // TODO: Get user locale
                        if item.lastPathComponent.hasPrefix("en") {
                            pathToDirectory = item
                            break
                        }
                    }
                } catch {
                    return nil
                }
                
                guard let pathToDirectory = pathToDirectory else {
                    return nil
                }
                
                let messagesPath = pathToDirectory.appending(path: "messages.json")
                guard FileManager.default.fileExists(atPath: messagesPath.path(percentEncoded: false)) else {
                    return nil
                }
                
                do {
                    let data = try Data(contentsOf: messagesPath)
                    guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
                        throw ExtensionError.invalidManifest("Invalid JSON structure")
                    }
                    
                    // Remove the __MSG_ from the start and the __ at the end
                    let formattedManifestValue = String(manifestValue.dropFirst(6).dropLast(2))
                                        
                    guard let messageText = manifest[formattedManifestValue]?["message"] as? String else {
                        return nil
                    }
                    
                    return messageText
                } catch {
                    return nil
                }
                
                
            }
            
            return nil
        }
        
        
        // Create extension entity for persistence
        let entity = ExtensionEntity(
            id: extensionId,
            name: manifest["name"] as? String ?? "Unknown Extension",
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            extensionDescription: getLocaleText(key: "description") ?? "",
            isEnabled: true,
            packagePath: destinationDir.path,
            iconPath: findExtensionIcon(in: destinationDir, manifest: manifest)
        )
        
        // Save to database
        self.context.insert(entity)
        try self.context.save()
        
        let installedExtension = InstalledExtension(from: entity, manifest: manifest)
        print("ExtensionManager: Successfully installed extension '\(installedExtension.name)' with native WKWebExtension")

        // SECURITY FIX: Always prompt for permissions that require user consent
        if #available(macOS 15.5, *),
           let displayName = extensionContext.webExtension.displayName {
            let requestedPermissions = extensionContext.webExtension.requestedPermissions
            let optionalPermissions = extensionContext.webExtension.optionalPermissions
            let requestedMatches = extensionContext.webExtension.requestedPermissionMatchPatterns
            let optionalMatches = extensionContext.webExtension.optionalPermissionMatchPatterns
            
            // Filter out permissions that were already granted as minimal safe permissions
            let minimalSafePermissions: Set<WKWebExtension.Permission> = [.storage, .alarms]
            let permissionsNeedingConsent = requestedPermissions.subtracting(minimalSafePermissions)
            
            // Always show permission prompt if there are any permissions or host patterns that need consent
            if !permissionsNeedingConsent.isEmpty || !requestedMatches.isEmpty || !optionalPermissions.isEmpty || !optionalMatches.isEmpty {
                print("   🔒 Showing permission prompt for extension: \(displayName)")
                print("      Permissions needing consent: \(permissionsNeedingConsent)")
                print("      Host patterns needing consent: \(requestedMatches)")
                
                self.presentPermissionPrompt(
                    requestedPermissions: permissionsNeedingConsent,
                    optionalPermissions: optionalPermissions,
                    requestedMatches: requestedMatches,
                    optionalMatches: optionalMatches,
                    extensionDisplayName: displayName,
                    onDecision: { grantedPerms, grantedMatches in
                        // Apply permission decisions
                        for p in permissionsNeedingConsent.union(optionalPermissions) {
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
                        print("   ✅ User granted permissions: \(grantedPerms)")
                        print("   ✅ User granted host patterns: \(grantedMatches)")
                    },
                    onCancel: {
                        // SECURITY FIX: Default deny all sensitive permissions if user cancels
                        for p in permissionsNeedingConsent { 
                            extensionContext.setPermissionStatus(.deniedExplicitly, for: p)
                        }
                        for m in requestedMatches { 
                            extensionContext.setPermissionStatus(.deniedExplicitly, for: m)
                        }
                        print("   ❌ User denied permissions - extension installed with minimal permissions only")
                    }
                )
            } else {
                print("   ✅ Extension only requests minimal safe permissions - no prompt needed")
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

    /// Disable all extensions (used when experimental extension support is disabled)
    func disableAllExtensions() {
        print("🔌 [ExtensionManager] Disabling all extensions...")

        let enabledExtensions = installedExtensions.filter { $0.isEnabled }

        for ext in enabledExtensions {
            disableExtension(ext.id)
            print("   Disabled: \(ext.name)")
        }

        print("🔌 [ExtensionManager] Disabled \(enabledExtensions.count) extensions")
    }

    /// Enable all previously enabled extensions (used when experimental extension support is re-enabled)
    func enableAllExtensions() {
        print("🔌 [ExtensionManager] Re-enabling previously enabled extensions...")

        let disabledExtensions = installedExtensions.filter { !$0.isEnabled }

        for ext in disabledExtensions {
            // Only enable extensions that were previously enabled (check database)
            do {
                let id = ext.id
                let predicate = #Predicate<ExtensionEntity> { $0.id == id }
                let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))

                if let entity = entities.first, entity.isEnabled {
                    enableExtension(ext.id)
                    print("   Re-enabled: \(ext.name)")
                }
            } catch {
                print("   Failed to check extension \(ext.name): \(error)")
            }
        }

        print("🔌 [ExtensionManager] Re-enabled extensions complete")
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
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
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
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
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
        return appSupport.appendingPathComponent("Nook").appendingPathComponent("Extensions")
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

    // Action popups remain popovers; options page behavior adjusted below
    

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
            if let currentTab = browserManager.currentTabForActiveWindow() {
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
        // Present the extension's action popover; keep behavior minimal and stable
        
        // Ensure critical permissions at popup time (user-invoked -> activeTab should be granted)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .activeTab)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .scripting)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .tabs)

        // No additional diagnostics

        // No extension-specific diagnostics

        // Focus state should already be correct, avoid re-notifying controller during delegate callback
        
        guard let popover = action.popupPopover else {
            print("❌ DELEGATE: No popover available on action")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No popover available"]))
            return
        }
        
        print("✅ DELEGATE: Native popover available - configuring and presenting!")
        
        if let webView = action.popupWebView {
            
            if let assoc = action.associatedTab as? ExtensionTabAdapter {
            } else {
            }
            if let active = windowAdapter?.activeTab(for: extensionContext) as? ExtensionTabAdapter {
            }
            
            // Ensure the WebView has proper configuration for extension resources
            if webView.configuration.webExtensionController == nil {
                webView.configuration.webExtensionController = controller
                print("   Attached extension controller to popup WebView")
            }
            
            // Enable inspection for debugging
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }
            
            // Temporarily disable console helper to test if it's causing container errors
            // PopupConsole.shared.attach(to: webView)

            // No custom message handlers; rely on native MV3 APIs

            if shouldAutoSizeActionPopups {
                // Install a light ResizeObserver to autosize the popover to content
                let resizeScript = """
                (function(){
                  try {
                    const post = (label, payload) => { try { webkit.messageHandlers.NookDiag.postMessage({label, payload, phase:'resize'}); } catch(_){} };
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
            }

            // Minimal polyfills for Chromium-only APIs some extensions feature-detect
            let polyfillScript = """
            (function(){
              try {
                window.chrome = window.chrome || {};
                var chromeNS = window.chrome;
                chromeNS.identity = chromeNS.identity || {};

                var pendingIdentityRequests = Object.create(null);
                var identityCounter = 0;

                chromeNS.identity.launchWebAuthFlow = function(details, callback){
                  var url = details && details.url ? String(details.url) : null;
                  if (!url) {
                    var missingUrlError = new Error('launchWebAuthFlow requires a url');
                    if (typeof callback === 'function') {
                      try { callback(null); } catch (_) {}
                    }
                    return Promise.reject(missingUrlError);
                  }

                  var interactive = !!(details && details.interactive);
                  var prefersEphemeral = !!(details && details.useEphemeralSession);
                  var callbackScheme = null;
                  if (details && typeof details.callbackURLScheme === 'string' && details.callbackURLScheme.length > 0) {
                    callbackScheme = details.callbackURLScheme;
                  }

                  var requestId = 'nook-auth-' + (++identityCounter);
                  var entry = {
                    resolve: null,
                    reject: null,
                    callback: (typeof callback === 'function') ? callback : null
                  };

                  var promise = new Promise(function(resolve, reject){
                    entry.resolve = resolve;
                    entry.reject = reject;
                  });

                  pendingIdentityRequests[requestId] = entry;

                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.NookIdentity) {
                      window.webkit.messageHandlers.NookIdentity.postMessage({
                        requestId: requestId,
                        url: url,
                        interactive: interactive,
                        prefersEphemeral: prefersEphemeral,
                        callbackScheme: callbackScheme
                      });
                    } else {
                      throw new Error('Native identity bridge unavailable');
                    }
                  } catch (error) {
                    delete pendingIdentityRequests[requestId];
                    if (entry.reject) { entry.reject(error); }
                    if (entry.callback) {
                      try { entry.callback(null); } catch (_) {}
                    }
                    return Promise.reject(error);
                  }

                  return promise;
                };

                if (typeof window.__nookCompleteIdentityFlow !== 'function') {
                  window.__nookCompleteIdentityFlow = function(result) {
                    if (!result || !result.requestId) { return; }
                    var entry = pendingIdentityRequests[result.requestId];
                    if (!entry) { return; }
                    delete pendingIdentityRequests[result.requestId];

                    var status = result.status || 'failure';
                    if (status === 'success') {
                      var payload = result.url || null;
                      if (entry.resolve) { entry.resolve(payload); }
                      if (entry.callback) {
                        try { entry.callback(payload); } catch (_) {}
                      }
                    } else {
                      var errMessage = result.message || 'Authentication failed';
                      var error = new Error(errMessage);
                      if (result.code) { error.code = result.code; }
                      if (entry.reject) { entry.reject(error); }
                      if (entry.callback) {
                        try { entry.callback(null); } catch (_) {}
                      }
                    }
                  };
                }

                if (typeof chromeNS.webRequestAuthProvider === 'undefined') {
                  chromeNS.webRequestAuthProvider = {
                    addListener: function(){},
                    removeListener: function(){}
                  };
                }
              } catch(_){}
            })();
            """
            let polyfill = WKUserScript(source: polyfillScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(polyfill)

            
            
            
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
                const res = await scriptingNS.executeScript({ target: { tabId: t.id }, world: 'MAIN', func: function(){ try { document.documentElement.setAttribute('data-Nook-probe','1'); return 'ok'; } catch(e){ return 'err:'+String(e); } } });
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
                    guard let pageWV = tabAdapter.tab.webView else { return }
                    pageWV.evaluateJavaScript("document.documentElement.getAttribute('data-Nook-probe')") { val, err in
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
            // Keep popover size fixed; no autosizing bookkeeping
            
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
        // No custom message handling
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
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didFailProvisional: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log("[Error] Provisional navigation failed: \(error.localizedDescription)")
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
        
        guard let bm = browserManagerRef else { 
            print("❌ Browser manager reference is nil")
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser manager not available"]))
            return 
        }
        
        // Special handling for extension page URLs (options, popup, etc.): use the extension's configuration
        if let url = configuration.url,
           (url.scheme?.lowercased() == "safari-web-extension" || url.scheme?.lowercased() == "webkit-extension"),
           let controller = extensionController,
           let resolvedContext = controller.extensionContext(for: url) {
            print("🎛️ [DELEGATE] Opening extension page in tab with extension configuration: \(url.absoluteString)")
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
            let cfg = resolvedContext.webViewConfiguration ?? BrowserConfiguration.shared.webViewConfiguration
            newTab.applyWebViewConfigurationOverride(cfg)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
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
        
        // OAuth flows from extensions should open in tabs to share the same data store
        // Miniwindows use separate data stores which breaks OAuth flows
        if let firstURL = configuration.tabURLs.first,
           isLikelyOAuthURL(firstURL) {
            print("🔐 [DELEGATE] Extension OAuth window detected, opening in new tab: \(firstURL.absoluteString)")
            // Create a new tab in the current space with the same profile/data store
            let newTab = bm.tabManager.createNewTab(url: firstURL.absoluteString, in: bm.tabManager.currentSpace)
            bm.tabManager.setActiveTab(newTab)

            // Return a dummy window adapter for OAuth flows
            if windowAdapter == nil {
                windowAdapter = ExtensionWindowAdapter(browserManager: bm)
            }
            completionHandler(windowAdapter, nil)
            return
        }
        
        // For regular extension windows, create a new space to emulate a separate window in our UI
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
    
    private func isLikelyOAuthURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        
        // Check for OAuth-related URLs
        let oauthHosts = [
            "accounts.google.com", "login.microsoftonline.com", "login.live.com",
            "appleid.apple.com", "github.com", "gitlab.com", "bitbucket.org",
            "auth0.com", "okta.com", "onelogin.com", "pingidentity.com",
            "slack.com", "zoom.us", "login.cloudflareaccess.com",
            "oauth", "auth", "login", "signin"
        ]
        
        // Check if host contains OAuth-related terms
        if oauthHosts.contains(where: { host.contains($0) }) {
            return true
        }
        
        // Check for OAuth paths and query parameters
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize") || 
           path.contains("/signin") || path.contains("/login") || path.contains("/callback") {
            return true
        }
        
        if query.contains("client_id=") || query.contains("redirect_uri=") || 
           query.contains("response_type=") || query.contains("scope=") {
            return true
        }
        
        return false
    }

    // Open the extension's options page (inside a browser tab)
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        print("🆕 [DELEGATE] openOptionsPageFor called!")
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        print("   Extension: \(displayName)")

        // Resolve the options page URL. Prefer the SDK property when available.
        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = self.computeOptionsPageURL(for: extensionContext)
        let kvcURL = (extensionContext as AnyObject).value(forKey: "optionsPageURL") as? URL
        let optionsURL: URL?
        if let u = sdkURL {
            optionsURL = u
        } else if let u = manifestURL {
            optionsURL = u
        } else if let u = kvcURL, u.scheme?.lowercased() != "file" {
            optionsURL = u
        } else if let u = kvcURL {
            optionsURL = u
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            print("❌ No options page URL found for extension")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No options page URL found for extension"]))
            return
        }

        print("✅ Opening options page: \(optionsURL.absoluteString)")

        // Create a dedicated WebView using the extension's webViewConfiguration so
        // the WebExtensions environment (browser/chrome APIs) is available.
        let config = extensionContext.webViewConfiguration ?? BrowserConfiguration.shared.webViewConfiguration
        // Ensure the controller is attached for safety
        if config.webExtensionController == nil, let c = extensionController {
            config.webExtensionController = c
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        // No navigation delegate needed for options page

        // Provide a lightweight alias to help extensions that only check `chrome`.
        // This only affects the options page web view, not normal websites.
        let aliasJS = """
        if (typeof window.chrome === 'undefined' && typeof window.browser !== 'undefined') {
          try { window.chrome = window.browser; } catch (e) {}
        }
        """
        let aliasScript = WKUserScript(source: aliasJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(aliasScript)

        // SECURITY FIX: Load the options page with restricted file access
        if optionsURL.isFileURL {
            // SECURITY FIX: Only allow access to the specific extension directory, not the entire package
            guard let extId = extensionContexts.first(where: { $0.value === extensionContext })?.key,
                  let inst = installedExtensions.first(where: { $0.id == extId }) else {
                print("❌ Could not resolve extension for secure file access")
                completionHandler(NSError(domain: "ExtensionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not resolve extension for secure file access"]))
                return
            }
            
            // SECURITY FIX: Validate that the options URL is within the extension directory
            let extensionRoot = URL(fileURLWithPath: inst.packagePath, isDirectory: true)
            
            // SECURITY FIX: Normalize paths to prevent path traversal attacks
            let normalizedExtensionRoot = extensionRoot.standardizedFileURL
            let normalizedOptionsURL = optionsURL.standardizedFileURL
            
            // Check if options URL is within the extension directory (prevent path traversal)
            if !normalizedOptionsURL.path.hasPrefix(normalizedExtensionRoot.path) {
                print("❌ SECURITY: Options URL outside extension directory: \(normalizedOptionsURL.path)")
                print("   Extension root: \(normalizedExtensionRoot.path)")
                completionHandler(NSError(domain: "ExtensionManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Options URL outside extension directory"]))
                return
            }
            
            // SECURITY FIX: Additional validation - ensure no path traversal attempts
            let relativePath = String(normalizedOptionsURL.path.dropFirst(normalizedExtensionRoot.path.count))
            if relativePath.contains("..") || relativePath.hasPrefix("/") {
                print("❌ SECURITY: Path traversal attempt detected: \(relativePath)")
                completionHandler(NSError(domain: "ExtensionManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Path traversal attempt detected"]))
                return
            }
            
            // SECURITY FIX: Only grant access to the extension's specific directory, not parent directories
            print("   🔒 SECURITY: Restricting file access to extension directory only: \(extensionRoot.path)")
            webView.loadFileURL(optionsURL, allowingReadAccessTo: extensionRoot)
        } else {
            // For non-file URLs (http/https), load normally
            webView.load(URLRequest(url: optionsURL))
        }

        // Present in a lightweight NSWindow to avoid coupling to Tab UI.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(displayName) – Options"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Keep window alive keyed by extension id
        if let extId = extensionContexts.first(where: { $0.value === extensionContext })?.key {
            optionsWindows[extId] = window
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        completionHandler(nil)
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
                    let fullFilePath = URL(fileURLWithPath: inst.packagePath).appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: fullFilePath.path) {
                        pagePath = path
                        print("   ✅ Found options page at: \(path)")
                        break
                    }
                }
            }
            
            if let page = pagePath {
                // Build an extension-scheme URL using the context baseURL
                let extBase = context.baseURL
                let optionsURL = extBase.appendingPathComponent(page)
                print("✅ Generated options extension URL: \(optionsURL.absoluteString)")
                return optionsURL
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
    
    // MARK: - URL Conversion Helpers
    
    /// Convert extension URL (webkit-extension:// or safari-web-extension://) to file URL
    @available(macOS 15.5, *)
    private func convertExtensionURLToFileURL(_ urlString: String, for context: WKWebExtensionContext) -> URL? {
        print("🔄 [convertExtensionURLToFileURL] Converting: \(urlString)")
        
        // Extract the path from the extension URL
        guard let url = URL(string: urlString) else {
            print("   ❌ Invalid URL string")
            return nil
        }
        
        let path = url.path
        print("   📂 Extracted path: \(path)")
        
        // Find the corresponding installed extension
        if let extId = extensionContexts.first(where: { $0.value === context })?.key,
           let inst = installedExtensions.first(where: { $0.id == extId }) {
            print("   📦 Found extension: \(inst.name)")
            
            // Build file URL from extension package path
            let extensionURL = URL(fileURLWithPath: inst.packagePath)
            let fileURL = extensionURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
            
            // Verify the file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("   ✅ File exists at: \(fileURL.path)")
                return fileURL
            } else {
                print("   ❌ File not found at: \(fileURL.path)")
            }
        } else {
            print("   ❌ Could not find installed extension for context")
        }
        
        return nil
    }
    
    // MARK: - Extension Resource Testing
    
    /// List all installed extensions with their UUIDs for easy testing
    func listInstalledExtensionsForTesting() {
        print("=== Installed Extensions ===")
        
        if installedExtensions.isEmpty {
            print("❌ No extensions installed")
            return
        }
        
        for (index, ext) in installedExtensions.enumerated() {
            print("\(index + 1). \(ext.name)")
            print("   UUID: \(ext.id)")
            print("   Version: \(ext.version)")
            print("   Manifest Version: \(ext.manifestVersion)")
            print("   Enabled: \(ext.isEnabled)")
            print("")
        }
    }
    
    // MARK: - Chrome Web Store Integration
    
    /// Install extension from Chrome Web Store by extension ID
    func installFromWebStore(extensionId: String, completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void) {
        WebStoreDownloader.downloadExtension(extensionId: extensionId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let zipURL):
                // Install the downloaded extension
                self.installExtension(from: zipURL) { installResult in
                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: zipURL)
                    completionHandler(installResult)
                }
                
            case .failure(let error):
                completionHandler(.failure(.installationFailed(error.localizedDescription)))
            }
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
