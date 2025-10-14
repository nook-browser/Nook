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
import UserNotifications

@available(macOS 15.4, *)
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate, WKScriptMessageHandler {
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
    // Extension command storage and management
    private var extensionCommands: [String: [String: WKWebExtension.Command]] = [:] // extensionId -> commandId -> Command
    // Extension message port management
    private var extensionMessagePorts: [String: WKWebExtension.MessagePort] = [:] // portName -> MessagePort
    private var messagePortHandlers: [String: (Any, WKWebExtensionContext) -> Void] = [:] // portName -> handler
    // Extension storage data management
    private var extensionDataRecords: [String: WKWebExtension.DataRecord] = [:] // extensionId -> DataRecord
    // Extension match pattern management
    private var registeredCustomSchemes: Set<String> = []
    internal var windowAdapter: ExtensionWindowAdapter?
    private weak var browserManagerRef: BrowserManager?
    // Whether to auto-resize extension action popovers to content. Disabled per UX preference.
    private let shouldAutoSizeActionPopups: Bool = false

    // No preference for action popups-as-tabs; keep native popovers per Apple docs
    
    let context: ModelContext
    
    // Profile-aware extension storage
    private var profileExtensionStores: [UUID: WKWebsiteDataStore] = [:]
    var currentProfileId: UUID?
    // Storage manager for chrome.storage.local API
    private let storageManager = ExtensionStorageManager()
    
    // DNR manager for declarativeNetRequest API
    private let dnrManager = DeclarativeNetRequestManager()
    
    // Reference to BrowserManager for applying rules to webviews
    private weak var browserManagerRef: BrowserManager?
    
    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable = ExtensionUtils.isExtensionSupportAvailable
        super.init()

        if isExtensionSupportAvailable {
            Task { @MainActor in
                setupExtensionController()
                loadInstalledExtensions()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // Capture state for cleanup before we tear down references
        let contexts = extensionContexts
        let controller = extensionController

        // MEMORY LEAK FIX: Clean up all extension contexts and break circular references
        tabAdapters.removeAll()
        actionAnchors.removeAll()

        // Close all options windows
        for (_, window) in optionsWindows {
            Task { @MainActor in
                window.close()
            }
        }
        optionsWindows.removeAll()

        // Clean up window adapter
        windowAdapter = nil

        // Unload extension controller contexts asynchronously on the main actor
        if let controller {
            Task { @MainActor in
                for (_, context) in contexts {
                    try? controller.unload(context)
                }
            }
        }
        extensionController = nil
        extensionContexts.removeAll()

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
        
        // Use extension-specific configuration with CORS support for the extension controller
        // This ensures background scripts and content scripts can make cross-origin requests
        let sharedWebConfig = BrowserConfiguration.shared.extensionWebViewConfiguration()
        
        // Extensions should use the same data store as the browser to share cookies and sessions
        // This fixes network connectivity issues where extensions can't access browser session data
        let extensionDataStore: WKWebsiteDataStore
        if let pid = currentProfileId {
            // Use the same profile-specific data store that the browser web views use
            extensionDataStore = getProfileDataStore(for: pid)
        } else {
            // Use the same default data store that the browser uses
            extensionDataStore = WKWebsiteDataStore.default()
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

        if currentProfileId != nil {
            print("   ✅ EXTENSIONS SHARE DATA STORE with browser web views for profile \(currentProfileId!.uuidString)")
            print("   This fixes network connectivity - extensions can access browser cookies and sessions")
        } else {
            print("   Extensions use default data store (no active profile)")
        }
        
        print("   Native storage types supported: .local, .session, .synchronized")
        print("   World support (MAIN/ISOLATED): \(ExtensionUtils.isWorldInjectionSupported)")
        
        // Handle macOS 15.4+ ViewBridge issues with delayed delegate assignment
        print("⚠️ Running on macOS 15.4+ - using delayed delegate assignment to avoid ViewBridge issues")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.delegate = self
        }
        
        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject
        if #available(macOS 15.5, *) {
            sharedWebConfig.webExtensionController = controller
            
            sharedWebConfig.defaultWebpagePreferences.allowsContentJavaScript = true
            
            print("ExtensionManager: Configured shared WebView configuration with extension controller")
            print("   ✅ Extension WebView configuration includes CORS support for external API access")
            
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
        let dataStoreDescription = controller.configuration.defaultWebsiteDataStore.map { String(describing: $0) } ?? "nil"
        print("   Data store: \(dataStoreDescription)")
        
        // Setup storage change observer
        setupStorageChangeObserver()
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

    /// Get the SAME data store that browser web views use for a profile
    /// This ensures extensions can share cookies and sessions with the browser
    private func getProfileDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        // Get the profile from browser manager's profile manager
        guard let browserManager = browserManagerRef else {
            print("⚠️ [ExtensionManager] No browser manager available, falling back to default data store")
            return WKWebsiteDataStore.default()
        }

        // Find the profile by ID in the profile manager's profiles array
        if let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile.dataStore
        } else {
            print("⚠️ [ExtensionManager] Profile not found for ID \(profileId), falling back to default data store")
            return WKWebsiteDataStore.default()
        }
    }

    private func getExtensionDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        if let store = profileExtensionStores[profileId] {
            return store
        }
        // Use a persistent store identified by the profile UUID for deterministic mapping when available
        let store = WKWebsiteDataStore(forIdentifier: profileId)
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

    /// Register all existing tabs with the extension controller to prevent "Tab not found" errors
    private func registerAllExistingTabs() {
        guard let bm = browserManagerRef, let controller = extensionController else {
            print("❌ [ExtensionManager] Cannot register tabs - browser manager or controller not available")
            return
        }

        print("🔧 [ExtensionManager] Registering all existing tabs with extension controller...")

        // Register all regular tabs
        for tab in bm.tabManager.tabs {
            let adapter = self.adapter(for: tab, browserManager: bm)
            controller.didOpenTab(adapter)
            print("   ✅ Registered tab: \(tab.name)")
        }

        // Register all pinned tabs
        for tab in bm.tabManager.pinnedTabs {
            let adapter = self.adapter(for: tab, browserManager: bm)
            controller.didOpenTab(adapter)
            print("   ✅ Registered pinned tab: \(tab.name)")
        }

        // Set the active tab if there is one
        if let activeTab = bm.currentTabForActiveWindow() {
            let activeAdapter = self.adapter(for: activeTab, browserManager: bm)
            controller.didActivateTab(activeAdapter, previousActiveTab: nil)
            controller.didSelectTabs([activeAdapter])
            print("   ✅ Set active tab: \(activeTab.name)")
        }

        print("✅ [ExtensionManager] Tab registration complete")
    }

    /// CRITICAL FIX: Register all existing tabs with a SPECIFIC extension context
    /// This ensures newly loaded extensions know about all existing tabs
    private func registerAllExistingTabsForContext(_ extensionContext: WKWebExtensionContext) {
        guard let bm = browserManagerRef, let controller = extensionController else {
            print("❌ [ExtensionManager] Cannot register tabs for context - browser manager or controller not available")
            return
        }

        let extensionId = extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier
        print("🔧 [ExtensionManager] Registering all existing tabs with newly loaded extension: \(extensionId)...")

        // Get all tabs including pinned and regular tabs
        let allTabs = bm.tabManager.pinnedTabs + bm.tabManager.tabs
        var registeredCount = 0

        // Register each tab with this specific extension context
        for tab in allTabs {
            let adapter = self.adapter(for: tab, browserManager: bm)

            // Register the tab with the controller - this will notify the specific extension
            controller.didOpenTab(adapter)
            print("   ✅ Registered tab with extension: \(tab.name)")
            registeredCount += 1
        }

        // Set the active tab for this extension if there is one
        if let activeTab = bm.currentTabForActiveWindow() {
            let activeAdapter = self.adapter(for: activeTab, browserManager: bm)
            controller.didActivateTab(activeAdapter, previousActiveTab: nil)
            controller.didSelectTabs([activeAdapter])
            print("   ✅ Set active tab for extension: \(activeTab.name)")
        }

        print("✅ [ExtensionManager] Registered \(registeredCount) existing tabs with extension: \(extensionId)")
        if registeredCount > 0 {
            print("💡 [ExtensionManager] Extension should now be able to communicate with all existing tabs")
        }
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
                    
                    webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                }
            }
        
        print("✅ Updated \(updatedCount) existing WebViews with extension controller")

        if updatedCount > 0 {
            print("💡 Content script injection should now work on existing tabs")
        }
    }

    /// Handle CORS failures by dynamically granting permissions for external API access
    @available(macOS 15.4, *)
    func handleCORSFailure(for url: URL, extensionContext: WKWebExtensionContext? = nil) {
        print("🚨 [ExtensionManager] Handling CORS failure for URL: \(url)")

        // Create broad permission pattern for the domain
        let scheme = url.scheme ?? "https"
        let host = url.host ?? "*"
        let patternString = "\(scheme)://\(host)/*"

        do {
            let pattern = try WKWebExtension.MatchPattern(string: patternString)

            // Grant permission for all loaded extensions or specific extension
            for (extId, context) in extensionContexts {
                // Grant to all extensions if no specific context provided, or grant to specific extension
                if extensionContext == nil || context === extensionContext {
                    context.setPermissionStatus(.grantedExplicitly, for: pattern)
                    let extName = context.webExtension.displayName ?? extId
                    print("  ✅ [ExtensionManager] Granted CORS permission for \(patternString) to extension: \(extName)")
                }
            }

            // Also grant common subdomain patterns
            let subdomainPatternString = "\(scheme)://*.\(host)/*"
            let subdomainPattern = try WKWebExtension.MatchPattern(string: subdomainPatternString)

            for (extId, context) in extensionContexts {
                if extensionContext == nil || context === extensionContext {
                    context.setPermissionStatus(.grantedExplicitly, for: subdomainPattern)
                    let extName = context.webExtension.displayName ?? extId
                    print("  ✅ [ExtensionManager] Granted subdomain permission for \(subdomainPatternString) to extension: \(extName)")
                }
            }

        } catch {
            print("  ❌ [ExtensionManager] Failed to create permission pattern for \(patternString): \(error)")
        }
    }

    /// Proactively grant common API permissions to prevent CORS failures
    @available(macOS 15.4, *)
    private func grantCommonAPIPermissions(to extensionContext: WKWebExtensionContext) {
        let extName = extensionContext.webExtension.displayName ?? "Unknown"
        print("🔧 [ExtensionManager] Proactively granting common API permissions to: \(extName)")

        // List of common API domains that extensions frequently need
        let commonAPIDomains = [
            "api.sprig.com",
            "api.github.com",
            "api.openai.com",
            "cdn.jsdelivr.net",
            "unpkg.com",
            "cdnjs.cloudflare.com",
            "fonts.googleapis.com",
            "fonts.gstatic.com",
            "ajax.googleapis.com"
        ]

        for domain in commonAPIDomains {
            let patternString = "https://\(domain)/*"
            do {
                let pattern = try WKWebExtension.MatchPattern(string: patternString)
                extensionContext.setPermissionStatus(.grantedExplicitly, for: pattern)
                print("  ✅ Pre-granted API permission: \(patternString)")
            } catch {
                print("  ❌ Failed to grant API permission for \(patternString): \(error)")
            }
        }

        // Also grant localhost for development
        let localhostPatterns = [
            "http://localhost/*",
            "https://localhost/*",
            "http://127.0.0.1/*",
            "https://127.0.0.1/*"
        ]

        for patternString in localhostPatterns {
            do {
                let pattern = try WKWebExtension.MatchPattern(string: patternString)
                extensionContext.setPermissionStatus(.grantedExplicitly, for: pattern)
                print("  ✅ Pre-granted localhost permission: \(patternString)")
            } catch {
                print("  ❌ Failed to grant localhost permission for \(patternString): \(error)")
            }
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

        // CRITICAL: Ensure the extension context has the correct baseURL for resource loading
        // This fixes webkit-extension:// URL resolution issues
        print("✅ [ExtensionManager] Extension context baseURL: \(extensionContext.baseURL.absoluteString)")

        // CRITICAL: Set webViewConfiguration for proper extension page loading
        // This is essential for popups, options pages, and background content to work
        if extensionContext.webViewConfiguration == nil {
            print("⚠️ [ExtensionManager] Extension context webViewConfiguration is nil, setting up...")

            // Create a configuration that uses the same data store as the browser
            let config = WKWebViewConfiguration()

            // Use the same data store as the browser for proper network/cookie sharing
            if let pid = currentProfileId {
                config.websiteDataStore = getProfileDataStore(for: pid)
            } else {
                config.websiteDataStore = WKWebsiteDataStore.default()
            }

            // Set up JavaScript preferences
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences = preferences
            config.preferences.javaScriptCanOpenWindowsAutomatically = true

            // Set the webExtensionController
            config.webExtensionController = extensionController

            // CRITICAL: Ensure the extension controller itself has the proper configuration
            // This is needed for popup resource loading to work correctly
            if let controller = extensionController {
                print("✅ [ExtensionManager] Extension controller available for popup resource loading")
                // Note: controller.configuration is read-only, but the framework should handle this correctly
            } else {
                print("⚠️ [ExtensionManager] Extension controller is nil - this may cause popup resource loading issues")
            }

            // Note: webViewConfiguration is read-only and automatically configured by WebKit
            // The webExtensionController set above enables proper extension page loading
            print("✅ [ExtensionManager] Extension context webExtensionController set up for shared data store")
        } else {
            print("✅ [ExtensionManager] Extension context webViewConfiguration already set")
        }

        // Debug the loaded extension
        print("✅ WKWebExtension created successfully")
        print("   Display name: \(webExtension.displayName ?? "Unknown")")
        print("   Version: \(webExtension.version ?? "Unknown")")
        print("   Unique ID: \(extensionContext.uniqueIdentifier)")
        print("   Resource base URL: \(extensionContext.baseURL.absoluteString)")
        print("   Has webViewConfiguration: \(extensionContext.webViewConfiguration != nil)")

        // CRITICAL: Test webkit-extension:// URL resolution
        let testURL = "webkit-extension://\(extensionContext.uniqueIdentifier)/index.html"
        print("🔍 Testing webkit-extension:// URL resolution:")
        print("   Test URL: \(testURL)")
        print("   Should resolve to: \(extensionContext.baseURL.appendingPathComponent("index.html").absoluteString)")
        
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
        
        // AGGRESSIVELY GRANT all necessary permissions for extension functionality
        // Extensions need broad access to work properly in this environment
        print("   🌐 Aggressively granting permissions for extension functionality")

        // Grant all requested permissions by default
        let requestedPermissions = webExtension.requestedPermissions
        print("   📋 Requested permissions: \(requestedPermissions)")

        for permission in requestedPermissions {
            print("   ✅ Granting permission: \(permission)")
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }

        // Grant all requested permission patterns aggressively
        let requestedMatches = webExtension.requestedPermissionMatchPatterns
        print("   📋 Requested permission patterns: \(requestedMatches.count)")

        for match in requestedMatches {
            print("   ✅ Granting permission pattern: \(match.description)")
            extensionContext.setPermissionStatus(.grantedExplicitly, for: match)
        }

        // Grant all optional permissions too for maximum compatibility
        let optionalPermissions = webExtension.optionalPermissions
        print("   📋 Optional permissions: \(optionalPermissions)")

        for permission in optionalPermissions {
            print("   ✅ Granting optional permission: \(permission)")
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }

        // Grant all optional permission patterns
        let optionalMatches = webExtension.optionalPermissionMatchPatterns
        print("   📋 Optional permission patterns: \(optionalMatches.count)")

        for match in optionalMatches {
            print("   ✅ Granting optional permission pattern: \(match.description)")
            extensionContext.setPermissionStatus(.grantedExplicitly, for: match)
        }

        // Create and grant broad permission patterns for common extension needs
        let broadPatterns = [
            "*://*/*",  // All HTTP/HTTPS
            "ws://*/*", // WebSockets
            "wss://*/*", // Secure WebSockets
            "ftp://*/*", // FTP
            "file:///*/*" // Local files
        ]

        for patternString in broadPatterns {
            do {
                let broadPattern = try WKWebExtension.MatchPattern(string: patternString)
                print("   ✅ Creating broad permission pattern: \(patternString)")
                extensionContext.setPermissionStatus(.grantedExplicitly, for: broadPattern)
            } catch {
                print("   ⚠️ Failed to create pattern \(patternString): \(error)")
            }
        }
        
        // Store context
        extensionContexts[extensionId] = extensionContext

        // Load and register extension commands
        registerExtensionCommands(for: extensionContext, extensionId: extensionId)

        // Load with native controller
        try extensionController?.load(extensionContext)

        // CRITICAL FIX: Register all existing tabs with THIS SPECIFIC extension context
        // This ensures the newly loaded extension knows about all existing tabs
        registerAllExistingTabsForContext(extensionContext)

        // PROACTIVE CORS: Grant common API permissions to prevent repeated CORS failures
        grantCommonAPIPermissions(to: extensionContext)

        // CRITICAL: Load background content if the extension has a background script
        // This is essential for service workers and background extensions
        print("🔧 [ExtensionManager] Loading background content for new extension...")
        print("   Extension has background content: \(webExtension.hasBackgroundContent)")
        print("   Extension identifier: \(extensionContext.uniqueIdentifier)")
        print("   Extension controller: \(String(describing: controller))")
        
        Task { @MainActor in
            do {
                try await extensionContext.loadBackgroundContent()
                print("✅ [ExtensionManager] Background content loaded successfully!")
                print("   Background script should now be running")
                print("   Background can receive runtime.sendMessage calls")
                
                // Give background script time to initialize and register listeners
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                print("   Background script initialization window complete")
            } catch {
                print("❌ [ExtensionManager] Failed to load background content: \(error.localizedDescription)")
                print("   This means runtime.sendMessage will NOT work!")
            }
        }

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
            // Clean up commands and message ports when disabling
            extensionCommands.removeValue(forKey: extensionId)
            disconnectAllMessagePorts(for: extensionId)
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
        extensionCommands.removeValue(forKey: extensionId)
        disconnectAllMessagePorts(for: extensionId)
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

                                // CRITICAL: Ensure the extension context has the correct baseURL for resource loading
                                // This fixes webkit-extension:// URL resolution issues
                                print("✅ [ExtensionManager] Extension context baseURL set automatically (reload): \(extensionContext.baseURL.absoluteString)")

                                // CRITICAL: Set webViewConfiguration for proper extension page loading
                                // This is essential for popups, options pages, and background content to work
                                if extensionContext.webViewConfiguration == nil {
                                    print("⚠️ [ExtensionManager] Extension context webViewConfiguration is nil (reload), setting up...")

                                    // Create a configuration that uses the same data store as the browser
                                    let config = WKWebViewConfiguration()

                                    // Use the same data store as the browser for proper network/cookie sharing
                                    if let pid = currentProfileId {
                                        config.websiteDataStore = getProfileDataStore(for: pid)
                                    } else {
                                        config.websiteDataStore = WKWebsiteDataStore.default()
                                    }

                                    // Set up JavaScript preferences
                                    let preferences = WKWebpagePreferences()
                                    preferences.allowsContentJavaScript = true
                                    config.defaultWebpagePreferences = preferences
                                    config.preferences.javaScriptCanOpenWindowsAutomatically = true

                                    // Set the webExtensionController
                                    config.webExtensionController = extensionController

                                    // CRITICAL: Ensure the extension controller itself has the proper configuration
                                    // This is needed for popup resource loading to work correctly
                                    if let controller = extensionController {
                                        print("✅ [ExtensionManager] Extension controller available for popup resource loading (reload)")
                                        // Note: controller.configuration is read-only, but the framework should handle this correctly
                                    } else {
                                        print("⚠️ [ExtensionManager] Extension controller is nil (reload) - this may cause popup resource loading issues")
                                    }

                                    // Note: webViewConfiguration is read-only and automatically configured by WebKit
                                    // The webExtensionController set above enables proper extension page loading
                                    print("✅ [ExtensionManager] Extension context webExtensionController set up (reload) for shared data store")
                                } else {
                                    print("✅ [ExtensionManager] Extension context webViewConfiguration already set (reload)")
                                }

                                print("✅ Existing extension re-loaded")
                                print("   Display name: \(webExtension.displayName ?? "Unknown")")
                                print("   Version: \(webExtension.version ?? "Unknown")")
                                print("   Unique ID: \(extensionContext.uniqueIdentifier)")
                                print("   Resource base URL: \(extensionContext.baseURL.absoluteString)")
                                print("   Has webViewConfiguration: \(extensionContext.webViewConfiguration != nil)")

                                // CRITICAL: Test webkit-extension:// URL resolution
                                let testURL = "webkit-extension://\(extensionContext.uniqueIdentifier)/index.html"
                                print("🔍 Testing webkit-extension:// URL resolution (reload):")
                                print("   Test URL: \(testURL)")
                                print("   Should resolve to: \(extensionContext.baseURL.appendingPathComponent("index.html").absoluteString)")
                                
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

                                // Load and register extension commands
                                registerExtensionCommands(for: extensionContext, extensionId: entity.id)

                                try extensionController?.load(extensionContext)

                                // CRITICAL: Register all existing tabs with THIS SPECIFIC extension context
                                // This ensures the newly loaded extension knows about all existing tabs
                                registerAllExistingTabsForContext(extensionContext)

                                // PROACTIVE CORS: Grant common API permissions to prevent repeated CORS failures
                                grantCommonAPIPermissions(to: extensionContext)

                                // CRITICAL: Load background content if the extension has a background script
                                // This is essential for service workers and background extensions
                                print("🔧 [ExtensionManager] Loading background content for extension...")
                                Task { @MainActor in
                                    do {
                                        try await extensionContext.loadBackgroundContent()
                                        print("✅ [ExtensionManager] Background content loaded successfully")
                                    } catch {
                                        print("❌ [ExtensionManager] Failed to load background content: \(error.localizedDescription)")
                                    }
                                }

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
    
    // THREADING FIX: Nonisolated access methods for delegate callbacks
    // These methods are thread-safe because tabAdapters access is done via MainActor.assumeIsolated
    // which is acceptable here since we're just doing a dictionary lookup
    @available(macOS 15.4, *)
    nonisolated func getStableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        return MainActor.assumeIsolated {
            self.stableAdapter(for: tab)
        }
    }
    
    @available(macOS 15.4, *)
    nonisolated func getWindowAdapter(for browserManager: BrowserManager) -> ExtensionWindowAdapter? {
        return MainActor.assumeIsolated {
            if self.windowAdapter == nil {
                self.windowAdapter = ExtensionWindowAdapter(browserManager: browserManager)
            }
            return self.windowAdapter
        }
    }

    @available(macOS 15.4, *)
    func notifyTabOpened(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        print("🔔 [ExtensionManager] Notifying controller of tab opened: \(tab.name)")

        // CRITICAL FIX: Ensure the tab's WebView has the extension controller set
        // This fixes "Tab not found" errors when content scripts try to communicate
        if let webView = tab.webView, webView.configuration.webExtensionController !== controller {
            print("  🔧 [ExtensionManager] Fixing missing extension controller in WebView for: \(tab.name)")
            webView.configuration.webExtensionController = controller

            // Ensure JavaScript is enabled for content script injection
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        // Register the tab with all extension contexts
        controller.didOpenTab(a)

        // CRITICAL FIX: Tab registration already handled by controller.didOpenTab(a) above
        // The extension controller automatically handles all extension contexts
    }

    @available(macOS 15.4, *)
    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let newA = adapter(for: newTab, browserManager: bm)
        let oldA = previous.map { adapter(for: $0, browserManager: bm) }
        print("🔔 [ExtensionManager] Notifying controller of tab activated: \(newTab.name) (previous: \(previous?.name ?? "none"))")
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }
    }

    @available(macOS 15.4, *)
    func notifyTabClosed(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        print("🔔 [ExtensionManager] Notifying controller of tab closed: \(tab.name)")
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
        // Present the extension's action popover with enhanced Action API support

        // Ensure critical permissions at popup time (user-invoked -> activeTab should be granted)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .activeTab)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .scripting)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .tabs)

        // CRITICAL: Grant additional permissions needed for popup functionality
        // Many extensions need storage access to load settings and communicate with background scripts
        if extensionContext.webExtension.requestedPermissions.contains(.storage) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: .storage)
            print("   ✅ Granted storage permission for popup functionality")
        }

        // Grant host permissions if requested (needed for loading extension resources)
        for matchPattern in extensionContext.webExtension.requestedPermissionMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: matchPattern)
            print("   ✅ Granted host permission for popup: \(matchPattern)")
        }

        // Enhanced Action API: Log action properties for debugging
        print("✅ DELEGATE: Action popup request received")
        print("   Badge text: \(action.badgeText)")
        print("   Badge background color: default") // action.badgeBackgroundColor not available
        print("   Badge text color: default") // action.badgeTextColor not available
        print("   Is enabled: \(action.isEnabled)")
        print("   Inspection name: \(action.inspectionName ?? "none")")

        // CRITICAL: Debug popup configuration
        if let webView = action.popupWebView {
            print("🔍 [DELEGATE] Popup WebView details:")
            print("   Has webExtensionController: \(webView.configuration.webExtensionController != nil)")
            print("   Website data store: \(webView.configuration.websiteDataStore)")

            if let url = webView.url {
                print("   Current URL: \(url.absoluteString)")
                if url.scheme?.lowercased() == "webkit-extension" {
                    print("   🎯 Popup is loading webkit-extension:// URL!")
                    print("   Host (UUID): \(url.host ?? "nil")")
                    print("   Path: \(url.path)")
                }
            } else {
                print("   Current URL: nil (not loaded yet)")
            }
        }

        guard let popover = action.popupPopover else {
            print("❌ DELEGATE: No popover available on action")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No popover available"]))
            return
        }

        print("✅ DELEGATE: Native popover available - configuring and presenting!")
        
        if let webView = action.popupWebView {

            // Get the active tab so we can associate the popup with it
            guard let windowAdapter = self.windowAdapter,
                  let activeTab = windowAdapter.activeTab(for: extensionContext),
                  let tabAdapter = activeTab as? ExtensionTabAdapter else {
                print("❌ DELEGATE: No active tab available for popup association")
                completionHandler(NSError(domain: "ExtensionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "No active tab available"]))
                return
            }

            // CRITICAL FIX: Ensure popup uses the extension's webViewConfiguration for proper resource loading
            // The framework-provided popup WebView might not have the correct configuration
            let expectedConfig = extensionContext.webViewConfiguration
            print("   🔧 Popup WebView configuration analysis:")
            print("      Has extension context webViewConfiguration: \(expectedConfig != nil)")
            print("      Popup webExtensionController set: \(webView.configuration.webExtensionController != nil)")

            // CRITICAL: Ensure popup WebView has access to the same extension context as the browser tabs
            // This fixes "Tab not found" errors when extensions call runtime.connect() from popups
            if webView.configuration.webExtensionController == nil {
                webView.configuration.webExtensionController = controller
                print("   ✅ Attached extension controller to popup WebView")
            }

            // CRITICAL: Ensure popup WebView uses the same data store as the browser for network connectivity
            if webView.configuration.websiteDataStore !== controller.configuration.defaultWebsiteDataStore {
                // Note: websiteDataStore is also read-only after creation, but this should be handled by the extension framework
                print("   ⚠️  Popup WebView data store differs from browser data store - this may cause network issues")
            }

            // CRITICAL FIX: The popup needs to use the extension's own configuration for proper resource loading
            // The webkit-extension:// URLs need the webExtensionController to be set correctly
            print("   🔧 Popup configuration check:")
            print("      webExtensionController: \(webView.configuration.webExtensionController != nil ? "✅" : "❌")")
            print("      URL: \(webView.url?.absoluteString ?? "nil")")

            // Add extension resource loading fixes (only inject once)
            if let url = webView.url, url.scheme?.lowercased() == "webkit-extension" {
                print("   🎯 Popup loading webkit-extension:// URL - ensuring proper resource access")

                // Check if scripts are already added to avoid duplicates
                let existingScripts = webView.configuration.userContentController.userScripts
                let hasResourceFix = existingScripts.contains { $0.source.contains("Popup Resource Fix") }

                if !hasResourceFix {
                    // Add a simple test script first to verify injection works
                    let simpleTestScript = """
                    console.log('🚀 [Simple Test] SCRIPT INJECTION WORKING!');
                    console.log('🚀 [Simple Test] URL:', window.location.href);
                    console.log('🚀 [Simple Test] Extension APIs:', typeof chrome !== 'undefined' ? 'chrome available' : 'chrome not available');
                    console.log('🚀 [Simple Test] Browser APIs:', typeof browser !== 'undefined' ? 'browser available' : 'browser not available');
                    console.log('🚀 [Simple Test] Runtime ID:', (chrome.runtime || browser.runtime).id);
                    """

                    // Add a comprehensive script to fix extension resource loading
                    let resourceFixScript = """
                    (function(){
                        console.log('🔧 [Popup Resource Fix] Initializing extension resource loading fixes');
                        console.log('🔍 [Popup Resource Test] URL:', window.location.href);
                        console.log('🔍 [Popup Resource Test] Extension ID:', chrome.runtime.id || browser.runtime.id);

                        // Test extension resources that are likely to exist
                        const testResources = [
                            'popup.js',
                            'popup/index.js',
                            'popup/popup.js',
                            'content/popup.js',
                            'index.js',
                            'popup.html'
                        ];

                        let successCount = 0;
                        let testCount = 0;

                        testResources.forEach(resource => {
                            const resourceUrl = (chrome.runtime || browser.runtime).getURL(resource);
                            console.log('🔍 [Popup Resource Test] Testing resource:', resourceUrl);
                            testCount++;

                            fetch(resourceUrl)
                                .then(response => {
                                    if (response.ok) {
                                        console.log('✅ [Popup Resource Test] Successfully loaded:', resource);
                                        successCount++;
                                    } else {
                                        console.log('❌ [Popup Resource Test] Failed to load:', resource, 'Status:', response.status);
                                    }

                                    if (successCount === 0 && testCount === testResources.length) {
                                        console.warn('⚠️ [Popup Resource Test] No extension resources could be loaded');
                                    }
                                })
                                .catch(err => {
                                    console.error('❌ [Popup Resource Test] Fetch error for', resource, ':', err);
                                });
                        });

                        // Test external API access
                        console.log('🌐 [Popup API Test] Testing external API access...');
                        fetch('https://api.sprig.com/sdk/1/visitors/test/events', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ test: true })
                        })
                        .then(response => {
                            console.log('✅ [Popup API Test] External API response:', response.status);
                        })
                        .catch(err => {
                            console.error('❌ [Popup API Test] External API error:', err);
                        });

                    })();
                    """

                    // Inject both scripts at different times for debugging
                    let simpleTestUserScript = WKUserScript(source: simpleTestScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                    let resourceFixUserScript = WKUserScript(source: resourceFixScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

                    webView.configuration.userContentController.addUserScript(simpleTestUserScript)
                    webView.configuration.userContentController.addUserScript(resourceFixUserScript)
                    print("   ✅ Added extension resource loading fixes (simple + comprehensive)")
                } else {
                    print("   ℹ️ Extension resource fixes already applied")
                }
            }

            print("   ✅ Popup WebView configured with browser tab context")

            // CRITICAL: Ensure the extension context knows about the active tab
            // This allows extensions inside popups to call runtime.connect() and find the tab
            controller.didActivateTab(tabAdapter, previousActiveTab: nil)
            controller.didSelectTabs([tabAdapter])

            print("   ✅ Extension context updated with active tab information")

            // Enhanced Action API: Enable inspection with custom inspection name
            webView.isInspectable = true

            // CRITICAL: Add inspection hint for easier debugging
            let inspectionHintScript = """
            (function(){
                // Add visual indicator that the page is inspectable
                try {
                    const hint = document.createElement('div');
                    hint.style.cssText = 'position:fixed;top:5px;right:5px;background:rgba(0,122,255,0.8);color:white;padding:3px 6px;border-radius:3px;font-size:10px;z-index:9999;font-family:sans-serif;';
                    hint.innerHTML = '🔍 INSPECTABLE';
                    hint.title = 'Right-click → Inspect Element to debug this popup';
                    document.body.appendChild(hint);

                    console.log('🔍 [Popup Inspection] This popup is inspectable! Right-click → Inspect Element');

                    // Auto-remove after 5 seconds
                    setTimeout(() => {
                        if (hint.parentNode) {
                            hint.parentNode.removeChild(hint);
                        }
                    }, 5000);
                } catch(e) {
                    console.log('🔍 [Popup Inspection] Could not add inspection hint:', e);
                }
            })();
            """

            let inspectionHintUserScript = WKUserScript(source: inspectionHintScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(inspectionHintUserScript)

            // CRITICAL: Console logging is now handled in the combined script below

            // CRITICAL: Combine all scripts into one injection to prevent multiple execution
            let combinedScript = """
            (function(){
                console.log('📢 [Popup Console Capture] Console logging initialized');

                // Test if Chrome APIs are available
                const hasChrome = typeof chrome !== 'undefined';
                const hasBrowser = typeof browser !== 'undefined';
                const hasRuntime = hasChrome && chrome.runtime || hasBrowser && browser.runtime;

                console.log('🔍 [Popup API Test] chrome available:', hasChrome);
                console.log('🔍 [Popup API Test] browser available:', hasBrowser);
                console.log('🔍 [Popup API Test] runtime available:', !!hasRuntime);
                if (hasRuntime) {
                    const runtimeAPI = hasChrome ? chrome.runtime : browser.runtime;
                    console.log('🔍 [Popup API Test] runtime ID:', runtimeAPI.id);
                    console.log('🔍 [Popup API Test] getURL test:', runtimeAPI.getURL('test.js'));
                    console.log('🔍 [Popup API Test] Testing onMessage listener presence...');

                    // Test sending a message with detailed error handling
                    console.log('📤 [Popup API Test] Attempting runtime.sendMessage...');
                    const testMessage = {
                        type: 'popupTest',
                        timestamp: Date.now(),
                        source: 'popup-diagnostic'
                    };
                    
                    try {
                        const sendStartTime = Date.now();
                        runtimeAPI.sendMessage(testMessage, (response) => {
                            const roundTripTime = Date.now() - sendStartTime;
                            console.log('✅ [Popup API Test] sendMessage SUCCESS! Round trip:', roundTripTime, 'ms');
                            console.log('   Response received:', response);
                            
                            if (chrome.runtime.lastError) {
                                console.error('⚠️  [Popup API Test] lastError despite response:', chrome.runtime.lastError);
                            }
                        });
                        
                        // Timeout check - if no response in 2 seconds, log warning
                        setTimeout(() => {
                            console.warn('⏱️  [Popup API Test] sendMessage timeout - no response after 2 seconds');
                            console.warn('   This likely means background script has no onMessage listener registered');
                            console.warn('   or background script failed to load');
                        }, 2000);
                        
                    } catch(e) {
                        console.error('❌ [Popup API Test] sendMessage exception:', e);
                        console.error('   Stack:', e.stack);
                    }
                }
                }

                // Override console methods to capture output
                const originalConsole = {
                    log: console.log,
                    error: console.error,
                    warn: console.warn,
                    info: console.info
                };

                function sendToNative(level, ...args) {
                    try {
                        const message = args.map(arg => {
                            if (typeof arg === 'object') {
                                try {
                                    return JSON.stringify(arg, null, 2);
                                } catch(e) {
                                    return String(arg);
                                }
                            }
                            return String(arg);
                        }).join(' ');

                        // Send via webkit message handlers
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.PopupConsole) {
                            window.webkit.messageHandlers.PopupConsole.postMessage({
                                level: level,
                                message: message,
                                timestamp: new Date().toISOString()
                            });
                        }
                    } catch(e) {
                        originalConsole.log('Console capture error:', e);
                    }
                }

                // Override console methods
                console.log = function(...args) {
                    originalConsole.log.apply(console, args);
                    sendToNative('log', ...args);
                };

                console.error = function(...args) {
                    originalConsole.error.apply(console, args);
                    sendToNative('error', ...args);
                };

                console.warn = function(...args) {
                    originalConsole.warn.apply(console, args);
                    sendToNative('warn', ...args);
                };

                console.info = function(...args) {
                    originalConsole.info.apply(console, args);
                    sendToNative('info', ...args);
                };
            })();
            """

            let combinedUserScript = WKUserScript(source: combinedScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(combinedUserScript)

            // Add message handler to capture console output (check if already exists)
            let userContentController = webView.configuration.userContentController

            
            // Inject storage API bridge
            let storageAPIScript = getStorageAPIBridge()
            let storageUserScript = WKUserScript(source: storageAPIScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(storageUserScript)
            
            // Inject DNR API bridge
            let dnrAPIScript = getDeclarativeNetRequestAPIBridge()
            let dnrUserScript = WKUserScript(source: dnrAPIScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(dnrUserScript)
            // Remove existing handler if it exists to prevent crashes
            userContentController.removeScriptMessageHandler(forName: "PopupConsole")
            userContentController.add(self, name: "PopupConsole")
            
            // Add storage API message handler
            userContentController.removeScriptMessageHandler(forName: "extensionStorage")
            userContentController.add(self, name: "extensionStorage")
            
            // Add DNR API message handler
            userContentController.removeScriptMessageHandler(forName: "extensionDNR")
            userContentController.add(self, name: "extensionDNR")

            // Enhanced Action API: Setup closePopup handler
            setupClosePopupHandler(for: webView, action: action, completionHandler: completionHandler)

            // Popup console for debugging
            PopupConsole.shared.attach(to: webView)

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

    // MARK: - Extension Command System

    /// Register extension commands and integrate with system keyboard shortcuts
    private func registerExtensionCommands(for extensionContext: WKWebExtensionContext, extensionId: String) {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] Command system requires macOS 15.5+")
            return
        }

        let webExtension = extensionContext.webExtension
        // Note: commands property may not be available in all SDK versions
        let commands: [WKWebExtension.Command] = [] // Placeholder - would be populated from webExtension.commands

        if commands.isEmpty {
            print("📝 [ExtensionManager] No commands found for extension: \(webExtension.displayName ?? "Unknown")")
            return
        }

        print("🔧 [ExtensionManager] Registering \(commands.count) commands for extension: \(webExtension.displayName ?? "Unknown")")

        var commandDict: [String: WKWebExtension.Command] = [:]

        for command in commands {
            commandDict[command.id] = command

            // Log command details
            print("   📋 Command: \(command.id)")
            print("      Activation key: \(command.activationKey ?? "none")")
            print("      Modifier flags: \(command.modifierFlags)")
            print("      Has keyCommand: false") // command.keyCommand not available
            print("      Has menuItem: false") // command.menuItem not available

            // Register the command with the browser's command system
            registerExtensionKeyCommand(command, extensionContext: extensionContext)
        }

        // Store commands for this extension
        extensionCommands[extensionId] = commandDict
        print("✅ [ExtensionManager] Successfully registered \(commands.count) commands")
    }

    /// Register an individual extension key command with the browser
    private func registerExtensionKeyCommand(_ command: WKWebExtension.Command, extensionContext: WKWebExtensionContext) {
        // Note: WKWebExtension.Command.keyCommand is not available
        // We'll use the activationKey and modifierFlags to create our own key handling

        let activationKey = command.activationKey
        let modifierFlags = command.modifierFlags

        // Create a unique command identifier that includes the extension
        let commandIdentifier = "extension_\(extensionContext.webExtension.displayName ?? "unknown")_\(command.id)"

        print("   ⌨️  Registering key command: \(modifierFlags) + \(activationKey ?? "none") -> \(commandIdentifier)")

        // Store command reference for later execution
        // Note: We'll integrate this with the existing keyboard shortcut system
        // For now, we'll store the command information and add delegate methods for execution
    }

    /// Execute an extension command by ID
    func executeExtensionCommand(extensionId: String, commandId: String) {
        guard let commands = extensionCommands[extensionId],
              let command = commands[commandId],
              let extensionContext = extensionContexts[extensionId] else {
            print("❌ [ExtensionManager] Command not found: \(extensionId):\(commandId)")
            return
        }

        print("🎯 [ExtensionManager] Executing command: \(commandId) for extension: \(extensionContext.webExtension.displayName ?? "Unknown")")

        // The command execution should trigger the extension's command handler
        // This will be handled by the WKWebExtension system automatically
        // when we properly integrate with the command delegation
        _ = command // Suppress unused variable warning
    }

    /// Get all registered commands for an extension
    func getExtensionCommands(extensionId: String) -> [WKWebExtension.Command] {
        return extensionCommands[extensionId]?.values.map { $0 } ?? []
    }

    /// Get a specific command for an extension
    func getExtensionCommand(extensionId: String, commandId: String) -> WKWebExtension.Command? {
        return extensionCommands[extensionId]?[commandId]
    }

    // MARK: - Extension Message Port System

    /// Create a message port for communicating with an extension
    func createMessagePort(portName: String, for extensionId: String, extensionContext: WKWebExtensionContext) -> WKWebExtension.MessagePort? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MessagePort system requires macOS 15.5+")
            return nil
        }

        print("🔌 [ExtensionManager] Creating message port: '\(portName)' for extension: \(extensionContext.webExtension.displayName ?? "Unknown")")

        // Create the message port using the proper WKWebExtension API
        // Note: MessagePort is created through the extension's controller
        guard extensionController != nil else {
            print("❌ [ExtensionManager] No extension controller available for message port")
            return nil
        }

        // Create a unique port name for this extension (unused in current implementation)
        _ = "\(extensionContext.uniqueIdentifier).\(portName)"

        // Since WKWebExtension.MessagePort cannot be directly instantiated,
        // we'll create a simple messaging bridge that the extension can use
        // In practice, MessagePorts are created by the extension system itself

        // For now, create a placeholder entry to track the port
        // The actual MessagePort would be provided by the WKWebExtension framework
        // when the extension requests to connect to a native port
        print("🔌 [ExtensionManager] Port '\(portName)' registered for extension: \(extensionContext.webExtension.displayName ?? "Unknown")")

        // Return nil since we can't create MessagePort instances directly
        // In a real scenario, the extension would initiate the port creation
        return nil
    }

    /// Handle incoming messages from extensions
    private func handleMessage(_ message: Any, from portName: String, context: WKWebExtensionContext) {
        // Check if there's a custom handler for this port
        if let handler = messagePortHandlers[portName] {
            handler(message, context)
            return
        }

        // Default message handling based on port name and message content
        if let messageDict = message as? [String: Any] {
            handleStructuredMessage(messageDict, from: portName, context: context)
        } else if let messageString = message as? String {
            handleStringMessage(messageString, from: portName, context: context)
        } else {
            print("📨 [ExtensionManager] Unhandled message type on port '\(portName)': \(type(of: message))")
        }
    }

    /// Handle structured dictionary messages
    private func handleStructuredMessage(_ message: [String: Any], from portName: String, context: WKWebExtensionContext) {
        guard let type = message["type"] as? String else {
            print("⚠️ [ExtensionManager] Message missing 'type' field on port '\(portName)'")
            return
        }

        switch type {
        case "ping":
            sendMessage(["type": "pong", "timestamp": Date().timeIntervalSince1970], to: portName, for: context.uniqueIdentifier)
            print("🏓 [ExtensionManager] Responded to ping on port '\(portName)'")

        case "getTabInfo":
            if let tabId = message["tabId"] as? String {
                // Handle tab info request
                sendTabInfo(for: tabId, to: portName, extensionId: context.uniqueIdentifier)
            }

        case "executeCommand":
            if let commandId = message["commandId"] as? String {
                executeExtensionCommand(extensionId: context.uniqueIdentifier, commandId: commandId)
            }

        case "showNotification":
            // Handle notification display
            if let title = message["title"] as? String, let body = message["body"] as? String {
                showExtensionNotification(title: title, body: body)
            }

        default:
            print("⚠️ [ExtensionManager] Unknown message type '\(type)' on port '\(portName)'")
        }
    }

    /// Handle simple string messages
    private func handleStringMessage(_ message: String, from portName: String, context: WKWebExtensionContext) {
        print("📨 [ExtensionManager] String message on port '\(portName)': \(message)")

        switch message.lowercased() {
        case "ping":
            sendMessage("pong", to: portName, for: context.uniqueIdentifier)

        case "status":
            sendMessage("ready", to: portName, for: context.uniqueIdentifier)

        default:
            print("⚠️ [ExtensionManager] Unhandled string message: '\(message)'")
        }
    }

    /// Send a message to an extension via a message port
    func sendMessage(_ message: Any, to portName: String, for extensionId: String) {
        let fullPortName = "\(extensionId).\(portName)"
        guard let messagePort = extensionMessagePorts[fullPortName] else {
            print("❌ [ExtensionManager] Message port '\(portName)' not found for extension: \(extensionId)")
            return
        }

        if messagePort.isDisconnected {
            print("❌ [ExtensionManager] Cannot send message - port '\(portName)' is disconnected")
            return
        }

        messagePort.sendMessage(message) { error in
            if let error = error {
                print("❌ [ExtensionManager] Failed to send message on port '\(portName)': \(error.localizedDescription)")
            } else {
                print("📤 [ExtensionManager] Message sent successfully on port '\(portName)'")
            }
        }
    }

    /// Register a custom message handler for a specific port
    func registerMessageHandler(for portName: String, handler: @escaping (Any, WKWebExtensionContext) -> Void) {
        messagePortHandlers[portName] = handler
        print("✅ [ExtensionManager] Registered custom handler for port '\(portName)'")
    }

    /// Remove a message port
    private func removeMessagePort(portName: String) {
        if let messagePort = extensionMessagePorts[portName] {
            if !messagePort.isDisconnected {
                messagePort.disconnect()
            }
            extensionMessagePorts.removeValue(forKey: portName)
        }
    }

    /// Disconnect all message ports for an extension
    func disconnectAllMessagePorts(for extensionId: String) {
        print("🔌 [ExtensionManager] Disconnecting all message ports for extension: \(extensionId)")

        // Find and remove all ports for this extension
        let portsToRemove = extensionMessagePorts.filter { $0.key.contains(extensionId) }
        for (portName, messagePort) in portsToRemove {
            if !messagePort.isDisconnected {
                messagePort.disconnect()
            }
            extensionMessagePorts.removeValue(forKey: portName)
        }
    }

    /// Get all active message ports for an extension
    func getMessagePorts(for extensionId: String) -> [String: WKWebExtension.MessagePort] {
        let extensionPorts = extensionMessagePorts.filter { $0.key.contains(extensionId) }
        var result: [String: WKWebExtension.MessagePort] = [:]
        for (key, value) in extensionPorts {
            let portName = key.replacingOccurrences(of: "\(extensionId).", with: "")
            result[portName] = value
        }
        return result
    }

    // MARK: - Message Port Helper Methods

    /// Send tab information to an extension
    private func sendTabInfo(for tabId: String, to portName: String, extensionId: String) {
        guard let browserManager = browserManagerRef else { return }

        // Find the tab by ID (this is a simplified approach)
        let allTabs = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
        if let tab = allTabs.first(where: { $0.id.uuidString == tabId }) {
            let tabInfo: [String: Any] = [
                "id": tab.id.uuidString,
                "title": tab.name,
                "url": tab.url.absoluteString,
                "isLoading": tab.isLoading,
                "isPinned": browserManager.tabManager.pinnedTabs.contains(tab)
            ]
            sendMessage(["type": "tabInfo", "data": tabInfo], to: portName, for: extensionId)
        }
    }

    /// Show a notification from an extension
    private func showExtensionNotification(title: String, body: String) {
        // Use modern UserNotifications framework
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [ExtensionManager] Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - MessagePort Helper Methods

    // MARK: - Extension DataRecord System (Storage API)

    /// Get storage data record for an extension
    func getDataRecord(for extensionId: String) -> WKWebExtension.DataRecord? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] DataRecord system requires macOS 15.5+")
            return nil
        }

        if let cachedRecord = extensionDataRecords[extensionId] {
            return cachedRecord
        }

        // Create a new data record for the extension
        guard let extensionContext = extensionContexts[extensionId] else {
            print("❌ [ExtensionManager] No extension context found for data record: \(extensionId)")
            return nil
        }

        // DataRecord instances are managed by Apple's WKWebExtension framework
        // The framework creates them automatically when extensions use storage APIs
        let dataRecord = createDataRecord(for: extensionContext)
        extensionDataRecords[extensionId] = dataRecord

        return dataRecord
    }

    /// Get the data record for an extension context from the WKWebExtension system
    @available(macOS 15.5, *)
    private func createDataRecord(for extensionContext: WKWebExtensionContext) -> WKWebExtension.DataRecord? {
        print("🗄️ [ExtensionManager] Accessing data record for extension: \(extensionContext.webExtension.displayName ?? "Unknown")")

        // WKWebExtension.DataRecord instances are managed by Apple's framework
        // The framework creates these automatically when extensions use storage APIs
        // We access them through the extension context when needed
        return nil // Framework would provide the actual DataRecord when storage is used
    }

    /// Get storage statistics for an extension
    func getStorageStats(for extensionId: String, completionHandler: @escaping (Int, Set<WKWebExtension.DataType>) -> Void) {
        guard #available(macOS 15.5, *) else {
            completionHandler(0, [])
            return
        }

        guard let dataRecord = getDataRecord(for: extensionId) else {
            completionHandler(0, [])
            return
        }

        let totalSize = dataRecord.totalSizeInBytes
        let dataTypes = dataRecord.containedDataTypes

        print("📊 [ExtensionManager] Storage stats for extension \(extensionId): \(totalSize) bytes, types: \(dataTypes)")
        completionHandler(totalSize, dataTypes)
    }

    /// Clear storage data for an extension
    func clearStorageData(for extensionId: String, dataTypes: Set<WKWebExtension.DataType>? = nil, completionHandler: @escaping (Error?) -> Void) {
        guard #available(macOS 15.5, *) else {
            completionHandler(NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "DataRecord system requires macOS 15.5+"]))
            return
        }

        guard getDataRecord(for: extensionId) != nil else {
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data record found"]))
            return
        }

        print("🗑️ [ExtensionManager] Clearing storage data for extension: \(extensionId)")

        // Note: Actual data clearing would be done through the WKWebExtension system
        // This is a placeholder implementation
        Task { @MainActor in
            // Simulate async clearing operation
            try? await Task.sleep(nanoseconds: 500_000_000)

            // In a real implementation, this would trigger actual data clearing
            print("✅ [ExtensionManager] Storage data cleared for extension: \(extensionId)")
            completionHandler(nil)
        }
    }

    /// Get storage data for specific data types
    func getStorageData(for extensionId: String, dataTypes: Set<WKWebExtension.DataType>, completionHandler: @escaping ([String: Any]?, Error?) -> Void) {
        guard #available(macOS 15.5, *) else {
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "DataRecord system requires macOS 15.5+"]))
            return
        }

        guard getDataRecord(for: extensionId) != nil else {
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data record found"]))
            return
        }

        print("📂 [ExtensionManager] Retrieving storage data for extension: \(extensionId), types: \(dataTypes)")

        // Note: Actual data retrieval would be done through the WKWebExtension system
        // This is a placeholder implementation
        Task { @MainActor in
            // Simulate async data retrieval
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Mock data structure - in reality this would be actual stored data
            let mockData: [String: Any] = [
                "local": [:],
                "session": [:],
                "sync": [:]
            ]

            print("✅ [ExtensionManager] Storage data retrieved for extension: \(extensionId)")
            completionHandler(mockData, nil)
        }
    }

    /// Monitor storage changes for an extension
    func monitorStorageChanges(for extensionId: String, onChange: @escaping (WKWebExtension.DataRecord) -> Void) {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] Storage monitoring requires macOS 15.5+")
            return
        }

        print("👀 [ExtensionManager] Starting storage monitoring for extension: \(extensionId)")

        // Note: Actual storage monitoring would be done through the WKWebExtension system
        // This would typically involve setting up observers on the extension's data store

        // In a real implementation, this would set up actual monitoring
        Task { @MainActor in
            // Simulate periodic storage monitoring
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

                guard let dataRecord = self.getDataRecord(for: extensionId) else { continue }

                // Check if storage has changed (placeholder logic)
                // In reality, this would detect actual changes
                print("📊 [ExtensionManager] Storage change detected for extension: \(extensionId)")
                onChange(dataRecord)
            }
        }
    }

    /// Refresh data record cache for an extension
    func refreshDataRecord(for extensionId: String) {
        // Remove cached record to force recreation on next access
        extensionDataRecords.removeValue(forKey: extensionId)
        print("🔄 [ExtensionManager] Data record cache cleared for extension: \(extensionId)")
    }

    // MARK: - Extension MatchPattern System (URL Pattern Matching)

    /// Create a match pattern from a pattern string
    func createMatchPattern(from patternString: String) -> WKWebExtension.MatchPattern? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return nil
        }

        do {
            let matchPattern = try WKWebExtension.MatchPattern(string: patternString)
            print("✅ [ExtensionManager] Created match pattern: '\(patternString)'")
            return matchPattern
        } catch {
            print("❌ [ExtensionManager] Failed to create match pattern from '\(patternString)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a match pattern from individual components
    func createMatchPattern(scheme: String, host: String, path: String) -> WKWebExtension.MatchPattern? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return nil
        }

        do {
            let matchPattern = try WKWebExtension.MatchPattern(scheme: scheme, host: host, path: path)
            print("✅ [ExtensionManager] Created match pattern: \(scheme)://\(host)\(path)")
            return matchPattern
        } catch {
            print("❌ [ExtensionManager] Failed to create match pattern from components: \(error.localizedDescription)")
            return nil
        }
    }

    /// Create an "all URLs" match pattern
    func createAllURLsMatchPattern() -> WKWebExtension.MatchPattern? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return nil
        }

        let matchPattern = WKWebExtension.MatchPattern.allURLs()
        print("✅ [ExtensionManager] Created 'all URLs' match pattern")
        return matchPattern
    }

    /// Create an "all hosts and schemes" match pattern
    func createAllHostsAndSchemesMatchPattern() -> WKWebExtension.MatchPattern? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return nil
        }

        let matchPattern = WKWebExtension.MatchPattern.allHostsAndSchemes()
        print("✅ [ExtensionManager] Created 'all hosts and schemes' match pattern")
        return matchPattern
    }

    /// Register a custom URL scheme for use in match patterns
    func registerCustomURLScheme(_ scheme: String) {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return
        }

        if registeredCustomSchemes.contains(scheme) {
            print("⚠️ [ExtensionManager] Custom URL scheme '\(scheme)' already registered")
            return
        }

        WKWebExtension.MatchPattern.registerCustomURLScheme(scheme)
        registeredCustomSchemes.insert(scheme)
        print("✅ [ExtensionManager] Registered custom URL scheme: '\(scheme)'")
    }

    /// Test if a URL matches a pattern
    func matchesPattern(_ pattern: WKWebExtension.MatchPattern, url: URL, options: WKWebExtension.MatchPattern.Options? = nil) -> Bool {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return false
        }

        let result: Bool
        if let options = options {
            result = pattern.matches(url, options: options)
        } else {
            result = pattern.matches(url)
        }

        print("🔍 [ExtensionManager] URL '\(url.absoluteString)' \(result ? "matches" : "does not match") pattern")
        return result
    }

    /// Test if a pattern matches another pattern
    func matchesPattern(_ pattern: WKWebExtension.MatchPattern, otherPattern: WKWebExtension.MatchPattern, options: WKWebExtension.MatchPattern.Options? = nil) -> Bool {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return false
        }

        let result: Bool
        if let options = options {
            result = pattern.matches(otherPattern, options: options)
        } else {
            result = pattern.matches(otherPattern)
        }

        print("🔍 [ExtensionManager] Pattern matching result: \(result)")
        return result
    }

    /// Get pattern details for debugging
    func getPatternDetails(_ pattern: WKWebExtension.MatchPattern) -> [String: Any]? {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return nil
        }

        let details: [String: Any] = [
            "scheme": pattern.scheme ?? "nil",
            "host": pattern.host ?? "nil",
            "path": pattern.path ?? "nil",
            "matchesAllHosts": pattern.matchesAllHosts,
            "matchesAllURLs": pattern.matchesAllURLs
        ]

        print("📋 [ExtensionManager] Pattern details: \(details)")
        return details
    }

    /// Create common match patterns used by extensions
    func createCommonMatchPatterns() -> [String: WKWebExtension.MatchPattern] {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return [:]
        }

        var patterns: [String: WKWebExtension.MatchPattern] = [:]

        // HTTP/HTTPS patterns
        if let httpPattern = createMatchPattern(scheme: "http", host: "*", path: "/*") {
            patterns["http"] = httpPattern
        }
        if let httpsPattern = createMatchPattern(scheme: "https", host: "*", path: "/*") {
            patterns["https"] = httpsPattern
        }

        // File extension patterns
        if let filePattern = createMatchPattern(scheme: "file", host: "*", path: "/*") {
            patterns["file"] = filePattern
        }

        // Extension-specific patterns
        if let extensionPattern = createMatchPattern(scheme: "webkit-extension", host: "*", path: "/*") {
            patterns["webkit-extension"] = extensionPattern
        }

        // All URLs pattern
        if let allURLsPattern = createAllURLsMatchPattern() {
            patterns["all-urls"] = allURLsPattern
        }

        print("✅ [ExtensionManager] Created \(patterns.count) common match patterns")
        return patterns
    }

    /// Validate match patterns for an extension
    func validateMatchPatterns(for extensionId: String, patterns: [String]) -> [String: WKWebExtension.MatchPattern] {
        guard #available(macOS 15.5, *) else {
            print("⚠️ [ExtensionManager] MatchPattern system requires macOS 15.5+")
            return [:]
        }

        var validPatterns: [String: WKWebExtension.MatchPattern] = [:]
        var invalidPatterns: [String] = []

        for patternString in patterns {
            if let matchPattern = createMatchPattern(from: patternString) {
                validPatterns[patternString] = matchPattern
            } else {
                invalidPatterns.append(patternString)
            }
        }

        if !invalidPatterns.isEmpty {
            print("⚠️ [ExtensionManager] Invalid match patterns for extension \(extensionId): \(invalidPatterns)")
        }

        print("✅ [ExtensionManager] Validated \(validPatterns.count) match patterns for extension: \(extensionId)")
        return validPatterns
    }

    /// Test URL access for an extension
    func canExtensionAccessURL(_ url: URL, for extensionId: String, matchPatterns: [WKWebExtension.MatchPattern]) -> Bool {
        guard #available(macOS 15.5, *) else {
            return false
        }

        for pattern in matchPatterns {
            if matchesPattern(pattern, url: url) {
                print("✅ [ExtensionManager] Extension \(extensionId) can access URL: \(url.absoluteString)")
                return true
            }
        }

        print("❌ [ExtensionManager] Extension \(extensionId) cannot access URL: \(url.absoluteString)")
        return false
    }

    // MARK: - Enhanced Action API Methods

    /// Setup closePopup handler for extension action popups
    private func setupClosePopupHandler(for webView: WKWebView, action: WKWebExtension.Action, completionHandler: @escaping (Error?) -> Void) {
        // Enhanced Action API: Add script handler for closePopup functionality
        let closePopupScript = """
        (function() {
            try {
                // Add closePopup method to the window object for extensions
                window.closePopup = function() {
                    try {
                        // Send message to native code to close the popup
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.NookExtension) {
                            window.webkit.messageHandlers.NookExtension.postMessage({
                                type: 'closePopup',
                                source: 'extension'
                            });
                        } else {
                            // Fallback: try to close window directly
                            window.close();
                        }
                    } catch (error) {
                        console.error('Failed to close popup:', error);
                    }
                };

                // Log that closePopup is available
                console.log('🔧 Extension closePopup API is available');

            } catch (error) {
                console.error('Failed to setup closePopup API:', error);
            }
        })();
        """

        let userScript = WKUserScript(source: closePopupScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(userScript)

        // Add message handler for closePopup events (remove existing first to avoid duplicates)
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "NookExtension")
        controller.add(self, name: "NookExtension")

        print("   ✅ Enhanced Action API: closePopup handler installed")
    }

    // MARK: - WKScriptMessageHandler (popup bridge)
    @objc func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle popup console capture messages
        if message.name == "PopupConsole" {
            if let messageBody = message.body as? [String: Any],
               let level = messageBody["level"] as? String,
               let consoleMessage = messageBody["message"] as? String,
               let timestamp = messageBody["timestamp"] as? String {

                // Format and display popup console output
                let emoji: String
                switch level {
                case "error": emoji = "❌"
                case "warn": emoji = "⚠️"
                case "info": emoji = "ℹ️"
                default: emoji = "📢"
                }

                print("\(emoji) [POPUP CONSOLE] \(timestamp) \(level.uppercased()): \(consoleMessage)")
            }
            return
        }
        
        // Handle storage API messages
        // Handle storage API messages
        if message.name == "extensionStorage" {
            guard let messageBody = message.body as? [String: Any] else {
                return
            }
            
            Task {
                await handleStorageMessage(message, body: messageBody)
            }
            return
        }
        
        // Handle DNR API messages
        if message.name == "extensionDNR" {
            guard let messageBody = message.body as? [String: Any] else {
                return
            }
            
            Task {
                await handleDNRMessage(message, body: messageBody)
            }
            return
        }

        // Handle existing extension messages (closePopup, etc.)
        guard let messageBody = message.body as? [String: Any],
              let type = messageBody["type"] as? String else {
            return
        }

        switch type {
        case "closePopup":
            print("🔌 Extension requested popup closure via closePopup API")
            // Find and close the popup
            if let window = NSApp.keyWindow,
               let popover = window.contentViewController?.view.subviews.first?.window {
                popover.performClose(nil)
            } else {
                // Fallback: try to find any popover window
                for window in NSApp.windows {
                    if window.className.contains("Popover") {
                        window.performClose(nil)
                        break
                    }
                }
            }

        default:
            print("🔌 Unknown extension message type: \(type)")
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

    // CRITICAL FIX: Handle extension content script communication
    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, sendMessageToContentScript message: [String : Any]?, toTabWithID tabID: String, in extensionContext: WKWebExtensionContext, completionHandler: @escaping (Result<Any?, Error>) -> Void) {
        print("📨 [ExtensionManager] sendMessageToContentScript called for tabID: \(tabID)")

        // Find the target tab by ID
        guard let tabUUID = UUID(uuidString: tabID),
              let browserManager = browserManagerRef else {
            let error = NSError(domain: "ExtensionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tab not found or invalid tab ID: \(tabID)"])
            completionHandler(.failure(error))
            return
        }

        // Find the tab in the browser manager
        let targetTab = browserManager.tabManager.tabs.first { $0.id == tabUUID } ??
                       browserManager.tabManager.pinnedTabs.first { $0.id == tabUUID }

        guard let tab = targetTab, let webView = tab.webView else {
            let error = NSError(domain: "ExtensionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Tab not found or WebView not available for tabID: \(tabID)"])
            completionHandler(.failure(error))
            return
        }

        // Ensure the tab's WebView has the extension controller
        if webView.configuration.webExtensionController !== controller {
            print("  🔧 [ExtensionManager] CRITICAL FIX: Adding missing extension controller for message handling")
            webView.configuration.webExtensionController = controller
        }

        // Execute the message in the content script context
        guard let messageData = message else {
            completionHandler(.success(nil))
            return
        }

        // Create the JavaScript to send the message to content scripts
        do {
            let messageJSON = try JSONSerialization.data(withJSONObject: messageData, options: [])
            let messageString = String(data: messageJSON, encoding: .utf8) ?? "{}"

            let script = """
            if (typeof window.chrome !== 'undefined' && window.chrome.runtime && window.chrome.runtime.onMessage) {
                const message = \(messageString);
                // Simulate the message being received by content scripts
                try {
                    window.postMessage({ type: 'chrome_runtime_message', detail: message }, '*');
                } catch (e) {
                    console.error('Failed to post message:', e);
                }
            }
            """

            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("  ❌ [ExtensionManager] Failed to send message to content script: \(error)")
                    completionHandler(.failure(error))
                } else {
                    print("  ✅ [ExtensionManager] Message sent to content script successfully")
                    completionHandler(.success(result))
                }
            }

        } catch {
            let error = NSError(domain: "ExtensionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize message: \(error.localizedDescription)"])
            completionHandler(.failure(error))
        }
    }

    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, openPortToExtensionContext extensionContext: WKWebExtensionContext, completionHandler: @escaping (Result<Any, Error>) -> Void) {
        print("🔌 [ExtensionManager] openPortToExtensionContext called")

        // Create a simple port object that extensions can use
        let portInfo: [String: Any] = [
            "name": "nook-port",
            "connected": true
        ]

        completionHandler(.success(portInfo))
    }

    // CRITICAL FIX: Handle tab requests for extension contexts
    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, tabWithID tabID: String, in extensionContext: WKWebExtensionContext, completionHandler: @escaping (Result<(any WKWebExtensionTab)?, Error>) -> Void) {
        print("🔍 [ExtensionManager] tabWithID called for tabID: \(tabID)")

        // Find the target tab by ID
        guard let tabUUID = UUID(uuidString: tabID),
              let browserManager = browserManagerRef else {
            let error = NSError(domain: "ExtensionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tab not found or invalid tab ID: \(tabID)"])
            completionHandler(.failure(error))
            return
        }

        // Find the tab in the browser manager
        let targetTab = browserManager.tabManager.tabs.first { $0.id == tabUUID } ??
                       browserManager.tabManager.pinnedTabs.first { $0.id == tabUUID }

        guard let tab = targetTab else {
            let error = NSError(domain: "ExtensionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Tab not found for tabID: \(tabID)"])
            completionHandler(.failure(error))
            return
        }

        // Create and return the tab adapter
        let adapter = self.adapter(for: tab, browserManager: browserManager)
        print("  ✅ [ExtensionManager] Found tab: \(tab.name)")
        completionHandler(.success(adapter))
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

        bm.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "puzzlepiece.extension",
                        title: "Extension Permissions",
                        subtitle: nil
                    )
                },
                content: {
                    ExtensionPermissionView(
                        extensionName: extensionDisplayName,
                        requestedPermissions: reqPerms,
                        optionalPermissions: optPerms,
                        requestedHostPermissions: reqHosts,
                        optionalHostPermissions: optHosts,
                        onGrant: { selectedPerms, selectedHosts in
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
                    )
                },
                footer: { EmptyView() }
            )
        }
    }

    // Delegate entry point for permission requests from extensions at runtime
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
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
                completionHandler(grantedPerms, nil)
            },
            onCancel: {
                for p in permissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                for m in extensionContext.webExtension.requestedPermissionMatchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler([], nil)
            }
        )
    }

    // Note: We can provide implementations for opening new tabs/windows once the
    // exact parameter types are finalized for the targeted SDK. These delegate
    // methods are optional; omitting them avoids type resolution issues across
    // SDK variations while retaining popup and permission handling.

    // MARK: - Opening tabs/windows requested by extensions
    @available(macOS 15.5, *)
    @objc func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        print("🆕 [DELEGATE] openNewTabUsing called!")
        print("   URL: \(configuration.url?.absoluteString ?? "nil")")
        print("   Should be active: \(configuration.shouldBeActive)")
        print("   Should be pinned: \(configuration.shouldBePinned)")

        // CRITICAL: Debug webkit-extension:// URL handling
        if let url = configuration.url,
           url.scheme?.lowercased() == "webkit-extension" {
            print("🔍 [DELEGATE] Processing webkit-extension:// URL:")
            print("   Full URL: \(url.absoluteString)")
            print("   Host (UUID): \(url.host ?? "nil")")
            print("   Path: \(url.path)")

            if let host = url.host {
                print("   Checking if extension context exists for UUID: \(host)")
                if let extContext = controller.extensionContext(for: url) {
                    print("   ✅ Found extension context for UUID")
                    print("   Context unique ID: \(extContext.uniqueIdentifier)")
                    print("   Context base URL: \(extContext.baseURL.absoluteString)")
                } else {
                    print("   ❌ No extension context found for UUID")
                }
            }
        }
        
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

            // CRITICAL: Ensure the configuration has the webExtensionController set
            // This is essential for webkit-extension:// URLs to load properly
            cfg.webExtensionController = controller

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
    @objc func webExtensionController(
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

        // Create a dedicated WebView using extension-specific configuration with CORS support
        // This ensures extensions can make cross-origin requests (like to APIs)
        let config = BrowserConfiguration.shared.extensionWebViewConfiguration()

        // Fall back to extension context config if available, but prefer our CORS-enabled config
        if config.webExtensionController == nil, let contextConfig = extensionContext.webViewConfiguration {
            config.webExtensionController = contextConfig.webExtensionController
        }

        // Ensure the controller is attached for safety
        if config.webExtensionController == nil, let c = extensionController {
            config.webExtensionController = c
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
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
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
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
                completionHandler(grantedMatches, nil)
            },
            onCancel: {
                for m in matchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler([], nil)
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
        // AGGRESSIVELY grant all URL access requests without restrictions
        // Extensions need unrestricted network access to function properly
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        print("🌐 [ExtensionManager] \(displayName) requesting URL access - AGGRESSIVELY GRANTING ALL:")
        for url in urls {
            print("   ✅ GRANTED: \(url.absoluteString)")
        }

        // Also proactively grant any future URLs by setting a broad permission
        let allUrlsPattern = try? WKWebExtension.MatchPattern(string: "*://*/*")
        if let pattern = allUrlsPattern {
            print("   ✅ Setting broad *://*/* permission for future requests")
            extensionContext.setPermissionStatus(.grantedExplicitly, for: pattern)
        }

        print("   ✅ Auto-granting ALL requested URL access - no restrictions")
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

    // MARK: - Additional Missing Delegate Methods

    @available(macOS 15.4, *)
    @objc func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        print("🔧 [ExtensionManager] Extension requesting to connect using message port")

        // Connection established successfully
        completionHandler(nil)
    }

    @available(macOS 15.4, *)
    @objc func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext extensionContext: WKWebExtensionContext
    ) {
        print("🔧 [ExtensionManager] Extension action was updated")
        print("   Badge text: \(action.badgeText)")
        print("   Is enabled: \(action.isEnabled)")

        // Find and update the corresponding extension action view
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .extensionActionUpdated,
                object: nil,
                userInfo: [
                    "extensionDisplayName": extensionContext.webExtension.displayName as Any,
                    "badgeText": action.badgeText,
                    "isEnabled": action.isEnabled
                ]
            )
        }
    }

    // MARK: - DNR Integration Helpers
    
    /// Set BrowserManager reference for DNR rule application
    func setBrowserManager(_ browserManager: BrowserManager) {
        self.browserManagerRef = browserManager
    }
    
    /// Get extension ID from a script message
    private func getExtensionId(for message: WKScriptMessage) -> String? {
        // Try to get from frameInfo URL
        if let url = message.frameInfo.request.url,
           let host = url.host {
            return host
        }
        
        // Fallback: try to extract from webView
        if let webView = message.webView as? WKWebView,
           let url = webView.url,
           let host = url.host {
            return host
        }
        
        // Last resort: return first loaded extension
        return installedExtensions.first?.id
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

// MARK: - Extension Notifications
extension Notification.Name {
    static let extensionActionUpdated = Notification.Name("extensionActionUpdated")
}
