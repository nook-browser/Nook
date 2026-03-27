//
//  ExtensionManager.swift
//  Nook
//
//  Simplified ExtensionManager using native WKWebExtension APIs
//

import AppKit
import Foundation
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject,
    WKWebExtensionControllerDelegate, NSPopoverDelegate
{
    static let shared = ExtensionManager()
    nonisolated static let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")

    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    @Published var isPopupActive: Bool = false
    @Published var extensionsLoaded: Bool = false
    // Scope note: Installed/enabled state is global across profiles; extension storage/state
    // (chrome.storage, cookies, etc.) is isolated per-profile via profile-specific data stores.

    internal var extensionController: WKWebExtensionController?
    internal var extensionContexts: [String: WKWebExtensionContext] = [:]
    var actionAnchors: [String: [WeakAnchor]] = [:]
    /// MEMORY LEAK FIX: Store observer tokens so they can be removed when anchors change
    var anchorObserverTokens: [String: [Any]] = [:]
    // Keep options windows alive per extension id
    var optionsWindows: [String: NSWindow] = [:]
    // Stable adapters for tabs/windows used when notifying controller events
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    /// Incremented on any tab change; lets ExtensionWindowAdapter cache query results.
    var tabCacheGeneration: UInt = 0
    internal var windowAdapter: ExtensionWindowAdapter?
    weak var browserManagerRef: BrowserManager?
    // Whether to auto-resize extension action popovers to content. Disabled per UX preference.
    // UI delegate for popup context menus and navigation
    var popupUIDelegate: PopupUIDelegate?
    // Strong reference to clipboard handler to prevent ARC deallocation
    var popupClipboardHandler: PopupClipboardHandler?
    // No preference for action popups-as-tabs; keep native popovers per Apple docs

    let context: ModelContext

    // Cache of native messaging hosts known to be unavailable (no manifest found).
    // Prevents repeated manifest lookups and log spam from extensions polling.
    var unavailableNativeHosts: Set<String> = []

    // Strong references to active native messaging handlers to prevent premature deallocation.
    var nativeMessagingHandlers: [NativeMessagingHandler] = []

    // Internal native port handlers for Safari extensions that expect the host app
    // to respond on native messaging channels (keyed by applicationIdentifier).
    var internalPortHandlers: [String: any InternalNativePortHandler] = [:]

    // Profile-aware extension storage
    private var profileExtensionStores: [UUID: WKWebsiteDataStore] = [:]
    var currentProfileId: UUID?

    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable =
            ExtensionUtils.isExtensionSupportAvailable
        super.init()

        if isExtensionSupportAvailable {
            setupExtensionController()
            loadInstalledExtensions()
            registerInternalNativePortHandlers()
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

        // MEMORY LEAK FIX: Remove all stored notification observer tokens
        for (_, tokens) in anchorObserverTokens {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
        anchorObserverTokens.removeAll()

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

        Self.logger.info("Cleaned up all extension resources")
    }

    // MARK: - Setup

    private func setupExtensionController() {
        // Use persistent controller configuration with stable identifier
        let config: WKWebExtensionController.Configuration
        if let idString = UserDefaults.standard.string(
            forKey: "Nook.WKWebExtensionController.Identifier"
        ),
            let uuid = UUID(uuidString: idString)
        {
            config = WKWebExtensionController.Configuration(identifier: uuid)
        } else {
            let uuid = UUID()
            UserDefaults.standard.set(
                uuid.uuidString,
                forKey: "Nook.WKWebExtensionController.Identifier"
            )
            config = WKWebExtensionController.Configuration(identifier: uuid)
        }

        let sharedWebConfig = BrowserConfiguration.shared.webViewConfiguration

        // Create or select a persistent data store for extensions.
        let extensionDataStore: WKWebsiteDataStore
        if let pid = currentProfileId {
            extensionDataStore = getExtensionDataStore(for: pid)
        } else {
            extensionDataStore = WKWebsiteDataStore(
                forIdentifier: config.identifier!
            )
        }

        if !extensionDataStore.isPersistent {
            Self.logger.error("Extension data store is not persistent - this may cause storage issues")
        }

        // CRITICAL: Set webViewConfiguration and defaultWebsiteDataStore on the config BEFORE
        // creating the controller. WKWebExtensionController.configuration returns a COPY (like
        // WKWebView.configuration), so setting properties on it after init modifies a temporary
        // copy that gets discarded. The background worker needs the shared webViewConfiguration
        // to share the same process pool as page webviews for chrome.runtime messaging to work.
        config.defaultWebsiteDataStore = extensionDataStore
        config.webViewConfiguration = sharedWebConfig

        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        self.extensionController = controller

        Self.logger.debug("Controller configured with storage ID: \(config.identifier?.uuidString ?? "none", privacy: .public), persistent: \(extensionDataStore.isPersistent)")

        // Handle macOS 15.4+ ViewBridge issues with delayed delegate assignment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            controller.delegate = self
        }

        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject
        if #available(macOS 15.5, *) {
            sharedWebConfig.webExtensionController = controller

            sharedWebConfig.defaultWebpagePreferences.allowsContentJavaScript =
                true

            Self.logger.debug("Configured shared WebView configuration with extension controller")

            // Update existing WebViews with controller
            updateExistingWebViewsWithController(controller)
        }

        // Verify storage is working after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.verifyExtensionStorage(self.currentProfileId)
        }

        Self.logger.info("Native WKWebExtensionController initialized and configured")
    }

    /// Register internal native port handlers for Safari extensions that expect
    /// the host app to handle native messaging (e.g. biometric unlock).
    private func registerInternalNativePortHandlers() {
        if #available(macOS 15.5, *) {
            let bitwarden = BitwardenBiometricHandler()
            for appId in BitwardenBiometricHandler.applicationIdentifiers {
                internalPortHandlers[appId] = bitwarden
            }
            Self.logger.debug("Registered \(self.internalPortHandlers.count) internal native port handlers")
        }
    }

    /// Lookup an internal handler for a native messaging application identifier.
    func internalHandler(for applicationId: String) -> (any InternalNativePortHandler)? {
        return internalPortHandlers[applicationId]
    }

    /// Verify extension storage is working properly
    private func verifyExtensionStorage(_ profileId: UUID? = nil) {
        guard let controller = extensionController else { return }

        guard let dataStore = controller.configuration.defaultWebsiteDataStore
        else {
            Self.logger.error("Extension storage verification failed: no data store available")
            return
        }
        Self.logger.debug("Verifying extension storage (profile=\(profileId?.uuidString ?? "default", privacy: .public), persistent=\(dataStore.isPersistent))")

        // Test storage accessibility
        dataStore.fetchDataRecords(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
        ) { records in
            DispatchQueue.main.async {
                Self.logger.debug("Extension storage records available: \(records.count)")
            }
        }
    }

    // MARK: - Profile-aware Data Store Management
    private func getExtensionDataStore(for profileId: UUID)
        -> WKWebsiteDataStore
    {
        if let store = profileExtensionStores[profileId] {
            return store
        }
        // Use a persistent store identified by the profile UUID for deterministic mapping when available
        let store = WKWebsiteDataStore(forIdentifier: profileId)
        profileExtensionStores[profileId] = store
        Self.logger.debug("Created extension data store for profile=\(profileId.uuidString, privacy: .public), persistent=\(store.isPersistent)")
        return store
    }

    func switchProfile(_ profileId: UUID) {
        guard let controller = extensionController else { return }
        let previousProfileId = currentProfileId
        let store = getExtensionDataStore(for: profileId)
        controller.configuration.defaultWebsiteDataStore = store
        currentProfileId = profileId

        // Invalidate any in-memory cached extension data from the previous profile.
        // Tab adapters may hold stale references to the previous profile's webviews.
        let cachedAdapterCount = tabAdapters.count
        tabAdapters.removeAll()
        Self.logger.info("Cleared \(cachedAdapterCount) cached tab adapters on profile switch")

        Self.logger.info("Switched extension data store from profile=\(previousProfileId?.uuidString ?? "default", privacy: .public) to profile=\(profileId.uuidString, privacy: .public)")

        // Post notification so other subsystems can react to the profile switch
        NotificationCenter.default.post(
            name: NSNotification.Name("ExtensionManagerDidSwitchProfile"),
            object: self,
            userInfo: [
                "previousProfileId": previousProfileId as Any,
                "newProfileId": profileId
            ]
        )

        // Verify storage on the new profile
        verifyExtensionStorage(profileId)
    }

    // MARK: - Extension Context Identity

    /// Keep a deterministic extension origin across app relaunches.
    /// This prevents extension local storage/session state from moving
    /// to a fresh namespace when WebKit generates a new default context ID.
    func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        extensionContext.uniqueIdentifier = extensionId

        // Use a host-safe, deterministic base URL derived from the persisted ID.
        // Keep the built-in `webkit-extension` scheme to avoid custom-scheme assertions.
        let host = "ext-" + extensionId.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(string: "webkit-extension://\(host)") {
            extensionContext.baseURL = baseURL
            Self.logger.debug("Configured context identity id=\(extensionId, privacy: .public), baseURL=\(baseURL.absoluteString, privacy: .public)")
        } else {
            Self.logger.error("Failed to configure base URL for extension id=\(extensionId, privacy: .public)")
        }
    }

    func clearExtensionData(for profileId: UUID) {
        let store = getExtensionDataStore(for: profileId)
        store.fetchDataRecords(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
        ) { records in
            Task { @MainActor in
                Self.logger.info("Clearing \(records.count) extension data records for profile=\(profileId.uuidString, privacy: .public)")
                await store.removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    for: records
                )
            }
        }
    }

    // MARK: - WebView Extension Controller Association

    /// Update existing WebViews to use the extension controller
    /// This fixes content script injection issues for tabs created before extension setup
    @available(macOS 15.5, *)
    private func updateExistingWebViewsWithController(
        _ controller: WKWebExtensionController
    ) {
        guard let bm = browserManagerRef else { return }

        let allTabs = bm.tabManager.pinnedTabs + bm.tabManager.tabs
        var updatedCount = 0

        for tab in allTabs {
            // Use assignedWebView to avoid triggering lazy initialization
            // Only update WebViews that have been assigned to a window
            guard let webView = tab.assignedWebView else { continue }

            if webView.configuration.webExtensionController !== controller {
                webView.configuration.webExtensionController = controller
                updatedCount += 1

                webView.configuration.defaultWebpagePreferences
                    .allowsContentJavaScript = true
            }
        }

        Self.logger.debug("Updated \(updatedCount) existing WebViews with extension controller")
    }

    // MARK: - Native Extension Access

    /// Get the native WKWebExtensionContext for an extension
    func getExtensionContext(for extensionId: String) -> WKWebExtensionContext?
    {
        return extensionContexts[extensionId]
    }

    /// Get the native WKWebExtensionController
    var nativeController: WKWebExtensionController? {
        return extensionController
    }

    /// IDs of all loaded extension contexts (for diagnostics).
    var loadedContextIDs: [String] {
        return Array(extensionContexts.keys)
    }

    // Action popups remain popovers; options page behavior adjusted below

    /// Connect the browser manager so we can expose tabs/windows and present UI.
    func attach(browserManager: BrowserManager) {
        self.browserManagerRef = browserManager
        // Ensure a stable window adapter and notify controller about the window
        if #available(macOS 15.5, *), let controller = extensionController {
            let adapter =
                self.windowAdapter
                ?? ExtensionWindowAdapter(browserManager: browserManager)
            self.windowAdapter = adapter

            // Important: Notify about window FIRST
            controller.didOpenWindow(adapter)
            controller.didFocusWindow(adapter)

            // Only notify about tabs that already have webviews.
            // Tabs without webviews (deferred for extension loading) will
            // self-register via notifyTabOpened() when their webview is created.
            // Registering tabs with nil webviews causes the controller to cache
            // stale state, breaking chrome.runtime messaging.
            let allTabs =
                browserManager.tabManager.pinnedTabs
                + browserManager.tabManager.tabs
            for tab in allTabs where !tab.isUnloaded {
                let tabAdapter = self.adapter(
                    for: tab,
                    browserManager: browserManager
                )
                controller.didOpenTab(tabAdapter)
            }

            // Notify about current active tab only if it has a webview
            if let currentTab = browserManager.currentTabForActiveWindow(),
               !currentTab.isUnloaded {
                let tabAdapter = self.adapter(
                    for: currentTab,
                    browserManager: browserManager
                )
                controller.didActivateTab(tabAdapter, previousActiveTab: nil)
                controller.didSelectTabs([tabAdapter])
            }

            Self.logger.info("Attached to browser manager with \(allTabs.count) tabs")

        }
    }

    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isPopupActive = false
            Self.logger.debug("🔒 [ExtensionManager] Popup closed, isPopupActive = false")
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

