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
    private static let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")

    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    @Published var isPopupActive: Bool = false
    @Published var extensionsLoaded: Bool = false
    // Scope note: Installed/enabled state is global across profiles; extension storage/state
    // (chrome.storage, cookies, etc.) is isolated per-profile via profile-specific data stores.

    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private var actionAnchors: [String: [WeakAnchor]] = [:]
    // Keep options windows alive per extension id
    private var optionsWindows: [String: NSWindow] = [:]
    // Stable adapters for tabs/windows used when notifying controller events
    private var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    internal var windowAdapter: ExtensionWindowAdapter?
    private weak var browserManagerRef: BrowserManager?
    // Whether to auto-resize extension action popovers to content. Disabled per UX preference.
    // UI delegate for popup context menus
    private var popupUIDelegate: PopupUIDelegate?
    // Track whether externally_connectable bridge scripts have been added to shared config
    private var externallyConnectableBridgeInstalled = false

    // No preference for action popups-as-tabs; keep native popovers per Apple docs

    let context: ModelContext

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.verifyExtensionStorage(self.currentProfileId)
        }

        Self.logger.info("Native WKWebExtensionController initialized and configured")
    }

    // MARK: - Externally Connectable Bridge

    /// Set up the externally_connectable bridge for an extension.
    ///
    /// Problem: Web pages (like account.proton.me) call browser.runtime.sendMessage(SAFARI_EXT_ID, msg)
    /// to communicate with the extension. The Safari extension ID doesn't match our WKWebExtension
    /// uniqueIdentifier, so the call fails and the page shows an error.
    ///
    /// Fix: Inject a user script into matching pages that wraps browser.runtime.sendMessage.
    /// When called with an external extensionId, it strips the ID and forwards as a regular
    /// content-script-to-background message (which the background handles — this is the same
    /// path Firefox uses via its postMessage fallback).
    @available(macOS 15.4, *)
    private func setupExternallyConnectableBridge(
        for extensionContext: WKWebExtensionContext,
        extensionId: String,
        packagePath: String
    ) {
        let manifestURL = URL(fileURLWithPath: packagePath).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ec = manifest["externally_connectable"] as? [String: Any],
              let matchPatterns = ec["matches"] as? [String], !matchPatterns.isEmpty
        else { return }

        guard !externallyConnectableBridgeInstalled else { return }
        externallyConnectableBridgeInstalled = true

        // Extract hostnames from match patterns
        var hostnames: [String] = []
        for pattern in matchPatterns {
            guard let schemeEnd = pattern.range(of: "://") else { continue }
            let afterScheme = pattern[schemeEnd.upperBound...]
            guard let slashIndex = afterScheme.firstIndex(of: "/") else { continue }
            let host = String(afterScheme[afterScheme.startIndex..<slashIndex])
            if host != "*" {
                hostnames.append(host.replacingOccurrences(of: "*.", with: ""))
            }
        }
        guard !hostnames.isEmpty else { return }

        Self.logger.info("Installing page-world externally_connectable polyfill for: \(hostnames.joined(separator: ", "), privacy: .public)")

        let hostnamesJSON = hostnames.map { "\"\($0)\"" }.joined(separator: ",")

        // PAGE-world polyfill: makes browser.runtime.sendMessage available to web pages.
        // Uses window.postMessage to bridge to nook_bridge.js (extension content script
        // in ISOLATED world with real browser.runtime access).
        let polyfillJS = """
        (function() {
            var _hosts = [\(hostnamesJSON)];
            var h = location.hostname;
            if (!_hosts.some(function(p) { return h === p || h.endsWith('.' + p); })) return;

            console.log('[NOOK-EC] Installing externally_connectable polyfill on ' + location.href);

            function sendMessagePolyfill(extensionId, message) {
                return new Promise(function(resolve, reject) {
                    var callbackId = 'nook_ec_' + Math.random().toString(36).substr(2, 9);

                    function handler(event) {
                        if (event.source !== window) return;
                        if (!event.data || event.data.type !== 'nook_ec_response') return;
                        if (event.data.callbackId !== callbackId) return;
                        window.removeEventListener('message', handler);
                        if (event.data.error) {
                            reject(new Error(event.data.error));
                        } else {
                            resolve(event.data.response);
                        }
                    }
                    window.addEventListener('message', handler);

                    window.postMessage({
                        type: 'nook_ec_request',
                        extensionId: extensionId,
                        message: message,
                        callbackId: callbackId
                    }, '*');

                    setTimeout(function() {
                        window.removeEventListener('message', handler);
                        reject(new Error('Extension communication timeout'));
                    }, 30000);
                });
            }

            // Polyfill browser.runtime.sendMessage for matching web pages
            if (!window.browser) window.browser = {};
            if (!window.browser.runtime) window.browser.runtime = {};
            if (typeof window.browser.runtime.sendMessage !== 'function') {
                window.browser.runtime.sendMessage = sendMessagePolyfill;
            }

            // Also polyfill chrome.runtime.sendMessage
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.runtime) window.chrome.runtime = {};
            if (typeof window.chrome.runtime.sendMessage !== 'function') {
                window.chrome.runtime.sendMessage = sendMessagePolyfill;
            }

            console.log('[NOOK-EC] Polyfill ready — browser.runtime.sendMessage available');
        })();
        """

        let sharedConfig = BrowserConfiguration.shared.webViewConfiguration
        let pageScript = WKUserScript(
            source: polyfillJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        sharedConfig.userContentController.addUserScript(pageScript)
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
        let store = getExtensionDataStore(for: profileId)
        controller.configuration.defaultWebsiteDataStore = store
        currentProfileId = profileId
        Self.logger.info("Switched controller data store to profile=\(profileId.uuidString, privacy: .public)")
        // Verify storage on the new profile
        verifyExtensionStorage(profileId)
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

    // MARK: - MV3 Support Methods

    // Note: commonPermissions array removed - now using minimalSafePermissions for better security

    /// Grant all requested permissions at install time (matches Chrome behavior).
    /// Chrome auto-grants everything in the manifest `permissions` array on install.
    /// Only `optional_permissions` require a runtime `chrome.permissions.request()` call.
    private func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        for permission in webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        Self.logger.debug("Granted requested permissions: \(webExtension.requestedPermissions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")
    }

    /// Backward-compatible alias used by the loadInstalledExtensions path.
    private func grantCommonPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        isExisting: Bool = false
    ) {
        grantRequestedPermissions(to: extensionContext, webExtension: webExtension)
    }

    /// Validate MV3-specific requirements
    private func validateMV3Requirements(manifest: [String: Any], baseURL: URL)
        throws
    {
        // Check for service worker
        if let background = manifest["background"] as? [String: Any] {
            if let serviceWorker = background["service_worker"] as? String {
                let serviceWorkerPath = baseURL.appendingPathComponent(
                    serviceWorker
                )
                if !FileManager.default.fileExists(
                    atPath: serviceWorkerPath.path
                ) {
                    throw ExtensionError.installationFailed(
                        "MV3 service worker not found: \(serviceWorker)"
                    )
                }
                Self.logger.debug("MV3 service worker found: \(serviceWorker, privacy: .public)")
            }
        }

        // Validate content scripts with world parameter
        if let contentScripts = manifest["content_scripts"] as? [[String: Any]]
        {
            for script in contentScripts {
                if let world = script["world"] as? String, world == "MAIN" {
                    Self.logger.debug("MAIN world content script detected - requires macOS 15.5+ for full support")
                }
            }
        }

        // Validate host_permissions vs permissions
        if let hostPermissions = manifest["host_permissions"] as? [String] {
            Self.logger.debug("MV3 host_permissions: \(hostPermissions, privacy: .public)")
        }
    }

    /// Patch manifest.json so domain-specific content scripts run in MAIN world.
    ///
    /// In Chrome MV3, content script fetch() uses the page's origin. In WebKit's
    /// ISOLATED world, fetch() uses the extension's origin (webkit-extension://)
    /// which causes CORS failures and prevents cookies from being sent. This
    /// particularly breaks SSO/auth flows like Proton Pass's fork session handoff
    /// where a content script needs to make authenticated requests to the page's API.
    ///
    /// The fix: content scripts that target a small set of specific domains (not
    /// wildcard all-sites patterns) and don't already specify a world are patched
    /// to run in MAIN world, where fetch() uses the page's origin and cookies.
    private func patchManifestForWebKit(at manifestURL: URL) {
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        var changed = false

        // --- Revert any previous MAIN-world patches on domain-specific content scripts ---
        // (Earlier code incorrectly patched domain-specific scripts to MAIN world,
        // but MAIN world content scripts lose browser.runtime access in WKWebExtension.)
        if var contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for i in contentScripts.indices {
                guard let world = contentScripts[i]["world"] as? String, world == "MAIN" else { continue }
                guard let matches = contentScripts[i]["matches"] as? [String] else { continue }
                let jsFiles = contentScripts[i]["js"] as? [String] ?? []

                // Don't touch our own bridge entry
                if jsFiles.contains("nook_bridge.js") { continue }

                // If ALL matches are domain-specific (no wildcard hosts), this was likely our patch
                let allDomainSpecific = matches.allSatisfy { pattern in
                    guard let schemeEnd = pattern.range(of: "://") else { return false }
                    let afterScheme = pattern[schemeEnd.upperBound...]
                    guard let slashIndex = afterScheme.firstIndex(of: "/") else { return false }
                    let host = String(afterScheme[afterScheme.startIndex..<slashIndex])
                    return host != "*" && !host.hasPrefix("*.")
                }

                if allDomainSpecific {
                    contentScripts[i].removeValue(forKey: "world")
                    Self.logger.info("Reverted MAIN world on [\(jsFiles.joined(separator: ", "), privacy: .public)] — restoring to ISOLATED")
                    changed = true
                }
            }
            manifest["content_scripts"] = contentScripts
        }

        // --- Add externally_connectable bridge content script ---
        if let ec = manifest["externally_connectable"] as? [String: Any],
           let matchPatterns = ec["matches"] as? [String], !matchPatterns.isEmpty {

            var contentScripts = manifest["content_scripts"] as? [[String: Any]] ?? []

            let alreadyHasBridge = contentScripts.contains { entry in
                (entry["js"] as? [String])?.contains("nook_bridge.js") == true
            }

            if !alreadyHasBridge {
                // Add bridge content script entry — runs in ISOLATED world (has browser.runtime)
                let bridgeEntry: [String: Any] = [
                    "all_frames": false,
                    "js": ["nook_bridge.js"],
                    "matches": matchPatterns,
                    "run_at": "document_start"
                ]
                contentScripts.append(bridgeEntry)
                manifest["content_scripts"] = contentScripts

                // Create the nook_bridge.js relay file
                let bridgeDir = manifestURL.deletingLastPathComponent()
                let bridgeFileURL = bridgeDir.appendingPathComponent("nook_bridge.js")
                let bridgeJS = """
                // Nook: externally_connectable bridge relay
                // Runs as extension content script (ISOLATED world) with browser.runtime access.
                // Listens for postMessage from page-world polyfill and forwards to background.
                (function() {
                    window.addEventListener('message', function(event) {
                        if (event.source !== window) return;
                        if (!event.data || event.data.type !== 'nook_ec_request') return;

                        var callbackId = event.data.callbackId;
                        var message = event.data.message;

                        if (message && typeof message === 'object') {
                            message = Object.assign({}, message, { sender: 'contentscript' });
                        }

                        browser.runtime.sendMessage(message).then(function(response) {
                            window.postMessage({
                                type: 'nook_ec_response',
                                callbackId: callbackId,
                                response: response
                            }, '*');
                        }).catch(function(error) {
                            window.postMessage({
                                type: 'nook_ec_response',
                                callbackId: callbackId,
                                error: error.message || String(error)
                            }, '*');
                        });
                    });
                })();
                """
                try? bridgeJS.write(to: bridgeFileURL, atomically: true, encoding: .utf8)
                Self.logger.info("Created nook_bridge.js and registered in manifest for externally_connectable bridge")
                changed = true
            }
        }

        if changed {
            if let updatedData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
                try? updatedData.write(to: manifestURL)
            }
        }
    }

    /// Configure MV3-specific extension features
    private func configureMV3Extension(
        webExtension: WKWebExtension,
        context: WKWebExtensionContext,
        manifest: [String: Any]
    ) async throws {
        // MV3: Service worker background handling
        if webExtension.hasBackgroundContent {
            Self.logger.debug("MV3 service worker background detected")
        }

        // MV3: Enhanced content script injection support
        if webExtension.hasInjectedContent {
            Self.logger.debug("MV3 content scripts detected - ensuring MAIN/ISOLATED world support")
        }

        // MV3: Action popup validation
        if let action = manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String {
                Self.logger.debug("MV3 action popup: \(popup, privacy: .public)")
            }
        }
    }

    // MARK: - Extension Installation

    func installExtension(
        from url: URL,
        completionHandler:
            @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }
        
        Task {
            do {
                let installedExtension = try await performInstallation(
                    from: url
                )
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
                    completionHandler(
                        .failure(
                            .installationFailed(error.localizedDescription)
                        )
                    )
                }
            }
        }
    }

    private func performInstallation(from sourceURL: URL) async throws
        -> InstalledExtension
    {
        let extensionsDir = getExtensionsDirectory()
        try FileManager.default.createDirectory(
            at: extensionsDir,
            withIntermediateDirectories: true
        )

        // STEP 1: Extract to temporary location first
        let tempId = UUID().uuidString
        let tempDir = extensionsDir.appendingPathComponent("temp_\(tempId)")

        let ext = sourceURL.pathExtension.lowercased()
        if ext == "zip" {
            try await extractZip(from: sourceURL, to: tempDir)
        } else if ext == "appex" || ext == "app" {
            // Safari Web Extension bundle — resolve and copy web resources
            let resourcesDir = try resolveSafariExtensionResources(at: sourceURL)
            try FileManager.default.copyItem(at: resourcesDir, to: tempDir)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: tempDir)
        }

        // Validate manifest exists
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)

        // MV3 Validation: Ensure proper manifest version support
        if let manifestVersion = manifest["manifest_version"] as? Int {
            Self.logger.info("Installing MV\(manifestVersion) extension")
            if manifestVersion == 3 {
                try validateMV3Requirements(
                    manifest: manifest,
                    baseURL: tempDir
                )
            }
        }

        // Patch domain-specific content scripts to MAIN world for WebKit fetch compatibility
        patchManifestForWebKit(at: manifestURL)

        // STEP 2: Create a temporary WKWebExtension just to get the uniqueIdentifier
        Self.logger.debug("Initializing WKWebExtension from \(tempDir.path, privacy: .public)")

        let tempExtension = try await WKWebExtension(resourceBaseURL: tempDir)
        let tempContext = WKWebExtensionContext(for: tempExtension)
        let extensionId = tempContext.uniqueIdentifier
        let finalDestinationDir = extensionsDir.appendingPathComponent(extensionId)

        Self.logger.info("Extension ID: \(extensionId, privacy: .public), name: \(tempExtension.displayName ?? "Unknown", privacy: .public)")

        // STEP 3: Move files to final directory named after the extension ID
        if FileManager.default.fileExists(atPath: finalDestinationDir.path) {
            try FileManager.default.removeItem(at: finalDestinationDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: finalDestinationDir)

        // STEP 4: Re-create WKWebExtension from the FINAL location so the
        // resource base URL points to where the files actually live. This is
        // critical — the service worker, popup HTML, and all resources are
        // loaded from this path at runtime.
        let webExtension = try await WKWebExtension(resourceBaseURL: finalDestinationDir)
        let extensionContext = WKWebExtensionContext(for: webExtension)

        Self.logger.info("WKWebExtension created from final path: \(finalDestinationDir.path, privacy: .public)")
        Self.logger.debug("Requested permissions: \(webExtension.requestedPermissions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")

        // Grant ALL permissions and match patterns at install time (Chrome behavior).
        // allRequestedMatchPatterns includes content_scripts patterns, not just host_permissions.
        for p in webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        for m in webExtension.allRequestedMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }

        // Enable Web Inspector for extension pages (background, popup)
        extensionContext.isInspectable = true

        // Store context and load into controller
        extensionContexts[extensionId] = extensionContext

        // Set up externally_connectable bridge BEFORE loading background
        setupExternallyConnectableBridge(
            for: extensionContext,
            extensionId: extensionId,
            packagePath: finalDestinationDir.path
        )

        try extensionController?.load(extensionContext)

        // Start the background service worker so it can handle
        // messages from popup and content scripts.
        extensionContext.loadBackgroundContent { [weak self] error in
            if let error {
                Self.logger.error("Background load failed for new extension: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.logger.info("Background content loaded for new extension")
                self?.probeBackgroundHealth(for: extensionContext, name: "new extension")
            }
        }

        func getLocaleText(key: String) -> String? {
            guard let manifestValue = manifest[key] as? String else {
                return nil
            }

            if manifestValue.hasPrefix("__MSG_") {
                let localesDirectory = finalDestinationDir.appending(
                    path: "_locales"
                )
                guard
                    FileManager.default.fileExists(
                        atPath: localesDirectory.path(percentEncoded: false)
                    )
                else {
                    return nil
                }

                var pathToDirectory: URL? = nil

                do {
                    let items = try FileManager.default.contentsOfDirectory(
                        at: localesDirectory,
                        includingPropertiesForKeys: nil
                    )

                    // Build a priority list from the user's current locale
                    var localeCandidates: [String] = []
                    let current = Locale.current
                    if let langCode = current.language.languageCode?.identifier {
                        if let regionCode = current.language.region?.identifier {
                            // Full locale with underscore and hyphen variants (e.g. pt_BR, pt-BR)
                            localeCandidates.append("\(langCode)_\(regionCode)")
                            localeCandidates.append("\(langCode)-\(regionCode)")
                        }
                        // Language-only (e.g. pt)
                        localeCandidates.append(langCode)
                    }
                    // Always fall back to English
                    localeCandidates.append("en")

                    // Case-insensitive matching against available locale directories
                    for candidate in localeCandidates {
                        if let match = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame }) {
                            pathToDirectory = match
                            break
                        }
                    }
                } catch {
                    return nil
                }

                guard let pathToDirectory = pathToDirectory else {
                    return nil
                }

                let messagesPath = pathToDirectory.appending(
                    path: "messages.json"
                )
                guard
                    FileManager.default.fileExists(
                        atPath: messagesPath.path(percentEncoded: false)
                    )
                else {
                    return nil
                }

                do {
                    let data = try Data(contentsOf: messagesPath)
                    guard
                        let manifest = try JSONSerialization.jsonObject(
                            with: data
                        ) as? [String: [String: String]]
                    else {
                        throw ExtensionError.invalidManifest(
                            "Invalid JSON structure"
                        )
                    }

                    // Remove the __MSG_ from the start and the __ at the end
                    let formattedManifestValue = String(
                        manifestValue.dropFirst(6).dropLast(2)
                    )

                    guard
                        let messageText = manifest[formattedManifestValue]?[
                            "message"
                        ] as? String
                    else {
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
            name: getLocaleText(key: "name") ?? manifest["name"] as? String ?? "Unknown Extension",
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            extensionDescription: getLocaleText(key: "description") ?? "",
            isEnabled: true,
            packagePath: finalDestinationDir.path,
            iconPath: findExtensionIcon(in: finalDestinationDir, manifest: manifest)
        )

        // Save to database
        self.context.insert(entity)
        try self.context.save()

        let installedExtension = InstalledExtension(
            from: entity,
            manifest: manifest
        )
        Self.logger.info("Successfully installed extension '\(installedExtension.name, privacy: .public)'")

        // All requested permissions and host patterns were already granted above
        // (matching Chrome behavior — install = consent). Optional permissions will
        // be handled at runtime via chrome.permissions.request() and the
        // promptForPermissions delegate.

        return installedExtension
    }

    private func extractZip(from zipURL: URL, to destinationURL: URL)
        async throws
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-q", zipURL.path, "-d", destinationURL.path]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw ExtensionError.installationFailed(
                "Failed to extract ZIP file"
            )
        }
    }

    /// Resolve the web extension resources directory from a Safari .appex or .app bundle.
    /// - .appex: look for `Contents/Resources/manifest.json`
    /// - .app: find the first `.appex` inside `Contents/PlugIns/` that contains web extension resources
    private func resolveSafariExtensionResources(at bundleURL: URL) throws -> URL {
        let ext = bundleURL.pathExtension.lowercased()

        if ext == "appex" {
            let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
            let manifest = resourcesDir.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                Self.logger.info("Found Safari extension resources at \(resourcesDir.path, privacy: .public)")
                return resourcesDir
            }
            throw ExtensionError.installationFailed(
                "No manifest.json found in .appex bundle at Contents/Resources"
            )
        }

        if ext == "app" {
            // Search PlugIns directory for .appex bundles containing web extension resources
            let plugInsDir = bundleURL.appendingPathComponent("Contents/PlugIns")
            if let items = try? FileManager.default.contentsOfDirectory(
                at: plugInsDir, includingPropertiesForKeys: nil
            ) {
                for item in items where item.pathExtension.lowercased() == "appex" {
                    let resourcesDir = item.appendingPathComponent("Contents/Resources")
                    let manifest = resourcesDir.appendingPathComponent("manifest.json")
                    if FileManager.default.fileExists(atPath: manifest.path) {
                        Self.logger.info("Found Safari extension in \(item.lastPathComponent): \(resourcesDir.path, privacy: .public)")
                        return resourcesDir
                    }
                }
            }
            throw ExtensionError.installationFailed(
                "No Safari Web Extension found in app bundle. Check Contents/PlugIns/ for .appex with manifest.json"
            )
        }

        throw ExtensionError.installationFailed("Unsupported bundle format: .\(ext)")
    }

    private func findExtensionIcon(in directory: URL, manifest: [String: Any])
        -> String?
    {
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

        let commonIconNames = [
            "icon.png", "logo.png", "icon128.png", "icon64.png",
        ]
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

            // Start the background service worker
            context.loadBackgroundContent { error in
                if let error {
                    Self.logger.error("Background load failed on enable: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Self.logger.error("Failed to enable extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }

        do {
            try extensionController?.unload(context)
            updateExtensionEnabled(extensionId, enabled: false)
        } catch {
            Self.logger.error("Failed to disable extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Disable all extensions (used when experimental extension support is disabled)
    func disableAllExtensions() {
        let enabledExtensions = installedExtensions.filter { $0.isEnabled }

        for ext in enabledExtensions {
            disableExtension(ext.id)
        }

        Self.logger.info("Disabled \(enabledExtensions.count) extensions")
    }

    /// Enable all previously enabled extensions (used when experimental extension support is re-enabled)
    func enableAllExtensions() {
        let disabledExtensions = installedExtensions.filter { !$0.isEnabled }

        for ext in disabledExtensions {
            // Only enable extensions that were previously enabled (check database)
            do {
                let id = ext.id
                let predicate = #Predicate<ExtensionEntity> { $0.id == id }
                let entities = try self.context.fetch(
                    FetchDescriptor<ExtensionEntity>(predicate: predicate)
                )

                if let entity = entities.first, entity.isEnabled {
                    enableExtension(ext.id)
                }
            } catch {
                Self.logger.error("Failed to check extension \(ext.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        Self.logger.info("Re-enabled extensions complete")
    }

    func uninstallExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId] {
            do {
                try extensionController?.unload(context)
            } catch {
                Self.logger.error("Failed to unload extension context: \(error.localizedDescription, privacy: .public)")
            }
            extensionContexts.removeValue(forKey: extensionId)
        }

        // Remove from database and filesystem
        do {
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
            let entities = try self.context.fetch(
                FetchDescriptor<ExtensionEntity>(predicate: predicate)
            )

            for entity in entities {
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                try? FileManager.default.removeItem(at: packageURL)
                self.context.delete(entity)
            }

            try self.context.save()

            installedExtensions.removeAll { $0.id == extensionId }
        } catch {
            Self.logger.error("Failed to uninstall extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateExtensionEnabled(_ extensionId: String, enabled: Bool) {
        do {
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
            let entities = try self.context.fetch(
                FetchDescriptor<ExtensionEntity>(predicate: predicate)
            )

            if let entity = entities.first {
                entity.isEnabled = enabled
                try self.context.save()

                // Update UI
                if let index = installedExtensions.firstIndex(where: {
                    $0.id == extensionId
                }) {
                    let updatedExtension = InstalledExtension(
                        from: entity,
                        manifest: installedExtensions[index].manifest
                    )
                    installedExtensions[index] = updatedExtension
                }
            }
        } catch {
            Self.logger.error("Failed to update extension enabled state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Safari Extension Discovery

    /// A Safari Web Extension found on the system
    struct SafariExtensionInfo: Identifiable {
        let id: String           // bundle identifier
        let name: String         // display name
        let appPath: URL         // path to the parent .app
        let appexPath: URL       // path to the .appex bundle
        let resourcesPath: URL   // path to Contents/Resources with manifest.json
    }

    /// Discover Safari Web Extensions installed on this Mac by scanning application
    /// bundles for .appex plugins that contain a manifest.json (web extension resources).
    func discoverSafariExtensions() async -> [SafariExtensionInfo] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [SafariExtensionInfo] = []
                let fm = FileManager.default

                // Scan both system and user Applications directories
                let searchDirs: [URL] = [
                    URL(fileURLWithPath: "/Applications"),
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                ]

                for searchDir in searchDirs {
                    guard let apps = try? fm.contentsOfDirectory(
                        at: searchDir,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for appURL in apps where appURL.pathExtension == "app" {
                        let plugInsDir = appURL.appendingPathComponent("Contents/PlugIns")
                        guard let plugins = try? fm.contentsOfDirectory(
                            at: plugInsDir,
                            includingPropertiesForKeys: nil
                        ) else { continue }

                        for pluginURL in plugins where pluginURL.pathExtension == "appex" {
                            // Check if this appex is a Safari web extension by looking for
                            // both the extension point identifier and a manifest.json
                            let infoPlist = pluginURL.appendingPathComponent("Contents/Info.plist")
                            if let plistData = try? Data(contentsOf: infoPlist),
                               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                               let nsExt = plist["NSExtension"] as? [String: Any],
                               let pointId = nsExt["NSExtensionPointIdentifier"] as? String,
                               pointId == "com.apple.Safari.web-extension" {
                                // Confirmed Safari web extension — check for manifest.json
                            } else {
                                continue
                            }

                            let resourcesDir = pluginURL.appendingPathComponent("Contents/Resources")
                            let manifestPath = resourcesDir.appendingPathComponent("manifest.json")
                            guard fm.fileExists(atPath: manifestPath.path) else { continue }

                            // Read extension name from manifest
                            var extName = appURL.deletingPathExtension().lastPathComponent
                            if let data = try? Data(contentsOf: manifestPath),
                               let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let name = manifest["name"] as? String,
                               !name.hasPrefix("__MSG_") {
                                extName = name
                            }

                            // Get bundle identifier from Info.plist
                            let bundleId = Bundle(url: pluginURL)?.bundleIdentifier ?? pluginURL.lastPathComponent

                            results.append(SafariExtensionInfo(
                                id: bundleId,
                                name: extName,
                                appPath: appURL,
                                appexPath: pluginURL,
                                resourcesPath: resourcesDir
                            ))
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    /// Install a discovered Safari extension by its resources path
    func installSafariExtension(_ info: SafariExtensionInfo, completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void) {
        installExtension(from: info.appexPath, completionHandler: completionHandler)
    }

    // MARK: - File Picker

    func showExtensionInstallDialog() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Install Extension"
        openPanel.message = "Select an extension folder, ZIP file, or Safari extension (.app/.appex)"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [
            .zip,
            .directory,
            .application,
            .applicationExtension,
        ]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url) { result in
                switch result {
                case .success(let ext):
                    Self.logger.info("Successfully installed extension: \(ext.name, privacy: .public)")
                case .failure(let error):
                    Self.logger.error("Failed to install extension: \(error.localizedDescription, privacy: .public)")
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
        let entities: [ExtensionEntity]
        do {
            entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>())
        } catch {
            Self.logger.error("Failed to fetch extensions: \(error.localizedDescription, privacy: .public)")
            self.extensionsLoaded = true
            return
        }

        var loadedExtensions: [InstalledExtension] = []
        var enabledEntities: [(ExtensionEntity, [String: Any])] = []

        for entity in entities {
            let manifestURL = URL(fileURLWithPath: entity.packagePath)
                .appendingPathComponent("manifest.json")
            do {
                // Patch domain-specific content scripts to MAIN world on each load
                // (idempotent — skips entries that already have a world set)
                patchManifestForWebKit(at: manifestURL)
                let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                loadedExtensions.append(InstalledExtension(from: entity, manifest: manifest))
                if entity.isEnabled {
                    enabledEntities.append((entity, manifest))
                }
            } catch {
                Self.logger.error("Failed to load manifest for '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        self.installedExtensions = loadedExtensions

        // No enabled extensions — mark loaded immediately
        if enabledEntities.isEmpty {
            Self.logger.info("No enabled extensions to load")
            self.extensionsLoaded = true
            return
        }

        // Load enabled extensions — parse manifests in parallel, then register sequentially
        Task { @MainActor in
            // Phase 1: Parse all extensions in parallel (I/O-bound)
            let parsed: [(ExtensionEntity, WKWebExtension)] = await withTaskGroup(
                of: (ExtensionEntity, WKWebExtension)?.self
            ) { group in
                for (entity, _) in enabledEntities {
                    group.addTask {
                        let resourceURL = URL(fileURLWithPath: entity.packagePath)
                        do {
                            let ext = try await WKWebExtension(resourceBaseURL: resourceURL)
                            return (entity, ext)
                        } catch {
                            Self.logger.error("Failed to load extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                            return nil
                        }
                    }
                }
                var results: [(ExtensionEntity, WKWebExtension)] = []
                for await result in group {
                    if let r = result { results.append(r) }
                }
                return results
            }

            // Phase 2: Register contexts sequentially (must be on MainActor)
            for (entity, webExtension) in parsed {
                let extensionContext = WKWebExtensionContext(for: webExtension)

                Self.logger.info("Loading '\(webExtension.displayName ?? entity.name, privacy: .public)' MV\(webExtension.manifestVersion) hasBackground=\(webExtension.hasBackgroundContent)")

                // Grant all permissions
                for p in webExtension.requestedPermissions {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
                }
                for p in webExtension.optionalPermissions {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
                }
                for m in webExtension.allRequestedMatchPatterns {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
                }
                for m in webExtension.optionalPermissionMatchPatterns {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
                }

                extensionContext.isInspectable = true

                let correctExtensionId = extensionContext.uniqueIdentifier

                // Update DB if ID changed
                if entity.id != correctExtensionId {
                    let oldId = entity.id
                    entity.id = correctExtensionId
                    try? self.context.save()
                    if let index = self.installedExtensions.firstIndex(where: { $0.id == oldId }) {
                        self.installedExtensions[index] = InstalledExtension(from: entity, manifest: self.installedExtensions[index].manifest)
                    }
                }

                self.extensionContexts[correctExtensionId] = extensionContext

                // Set up externally_connectable bridge BEFORE loading background
                self.setupExternallyConnectableBridge(
                    for: extensionContext,
                    extensionId: correctExtensionId,
                    packagePath: entity.packagePath
                )

                do {
                    try self.extensionController?.load(extensionContext)
                } catch {
                    Self.logger.error("Failed to register extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    continue
                }

                // Start background service worker if the extension has one
                if webExtension.hasBackgroundContent {
                    extensionContext.loadBackgroundContent(completionHandler: { [weak self] error in
                        if let error {
                            Self.logger.error("Background content failed for '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                        } else {
                            Self.logger.info("Background content started for '\(entity.name, privacy: .public)'")
                            // Probe background webview for JS errors after a short delay
                            self?.probeBackgroundHealth(for: extensionContext, name: entity.name)
                        }
                    })
                }

                Self.logger.info("Loaded '\(entity.name, privacy: .public)' — contexts: \(self.extensionController?.extensionContexts.count ?? 0, privacy: .public)")
            }

            Self.logger.info("All extensions loaded — signaling ready")
            self.extensionsLoaded = true
        }
    }

    private func getExtensionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Nook").appendingPathComponent(
            "Extensions"
        )
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

    // MARK: - Controller event notifications for tabs

    @available(macOS 15.5, *)
    private func adapter(for tab: Tab, browserManager: BrowserManager)
        -> ExtensionTabAdapter
    {
        if let existing = tabAdapters[tab.id] {
            return existing
        }
        let created = ExtensionTabAdapter(
            tab: tab,
            browserManager: browserManager
        )
        tabAdapters[tab.id] = created
        Self.logger.debug("Created tab adapter for '\(tab.name, privacy: .public)'")
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
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didOpenTab(a)
    }

    /// Grant all extension contexts explicit access to a URL.
    /// WKWebExtensionController uses Safari's per-URL permission model where even
    /// granted match patterns don't give implicit URL access. Without this, content
    /// scripts won't inject and messaging fails. Call before navigation starts.
    @available(macOS 15.4, *)
    func grantExtensionAccessToURL(_ url: URL) {
        for (_, ctx) in extensionContexts {
            ctx.setPermissionStatus(.grantedExplicitly, for: url)
        }
    }

    @available(macOS 15.4, *)
    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let newA = adapter(for: newTab, browserManager: bm)
        let oldA = previous.map { adapter(for: $0, browserManager: bm) }
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }
    }

    @available(macOS 15.4, *)
    func notifyTabClosed(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didCloseTab(a, windowIsClosing: false)
        tabAdapters[tab.id] = nil
    }

    @available(macOS 15.4, *)
    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didChangeTabProperties(properties, for: a)
    }

    /// Register a UI anchor view for an extension action button to position popovers.
    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        Self.logger.debug("setActionAnchor called for extension ID: \(extensionId, privacy: .public)")
        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        if actionAnchors[extensionId] == nil { actionAnchors[extensionId] = [] }
        // Remove stale anchors
        actionAnchors[extensionId]?.removeAll { $0.view == nil }
        if let idx = actionAnchors[extensionId]?.firstIndex(where: {
            $0.view === anchorView
        }) {
            actionAnchors[extensionId]?[idx] = anchor
        } else {
            actionAnchors[extensionId]?.append(anchor)
        }
        Self.logger.debug("Total anchors for extension \(extensionId, privacy: .public): \(self.actionAnchors[extensionId]?.count ?? 0)")

        // Update anchor if view moves to a different window
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self] _ in
            if let idx = self?.actionAnchors[extensionId]?.firstIndex(
                where: { $0.view === anchorView }
            ) {
                let updated = WeakAnchor(
                    view: anchorView,
                    window: anchorView.window
                )
                self?.actionAnchors[extensionId]?[idx] = updated
            }
        }
    }

    // MARK: - WKWebExtensionControllerDelegate

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let extName = extensionContext.webExtension.displayName ?? "?"
        Self.logger.info("presentActionPopup delegate called for '\(extName, privacy: .public)'")

        // Grant ALL the extension's requested + optional permissions so the popup
        // can use chrome.tabs, chrome.runtime, etc. without hanging.
        // allRequestedMatchPatterns includes content_scripts patterns, not just host_permissions.
        for p in extensionContext.webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        for p in extensionContext.webExtension.optionalPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        for m in extensionContext.webExtension.allRequestedMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }
        for m in extensionContext.webExtension.optionalPermissionMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }

        Self.logger.debug("Granted permissions: \(extensionContext.currentPermissions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")

        // Ensure background service worker is alive before showing the popup.
        // MV3 workers auto-terminate after ~5 min of inactivity; if the popup
        // tries chrome.runtime.sendMessage and the worker is dead, it hangs forever.
        if extensionContext.webExtension.hasBackgroundContent {
            extensionContext.loadBackgroundContent { error in
                if let error {
                    Self.logger.error("Failed to wake background worker for '\(extName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                } else {
                    Self.logger.debug("Background worker alive for '\(extName, privacy: .public)'")
                }
            }
        }

        guard let popover = action.popupPopover else {
            Self.logger.error("No popover available on action")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No popover available"
                    ]
                )
            )
            return
        }

        popover.behavior = .transient

        if let webView = action.popupWebView {
            webView.isInspectable = true
        }

        // Present the popover on main thread
        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
            
            popover.behavior = .transient
            popover.delegate = self
            self.isPopupActive = true
            
            // Keep popover size fixed; no autosizing bookkeeping

            // Try to use registered anchor for this extension
            if let extId = self.extensionContexts.first(where: {
                $0.value === extensionContext
            })?.key,
                var anchors = self.actionAnchors[extId]
            {
                Self.logger.debug("   📌 Registered anchors for this extension: \(anchors.count)")
                
                // Clean up stale anchors (no view OR no window)
                anchors.removeAll { $0.view == nil || $0.view?.window == nil }
                self.actionAnchors[extId] = anchors
                Self.logger.debug("   📌 After cleanup: \(anchors.count) anchors")

                // Find anchor in current window
                if let win = targetWindow,
                    let match = anchors.first(where: { $0.window === win }),
                    let view = match.view,
                    view.window != nil  // Double-check view is still in window
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    completionHandler(nil)
                    return
                }

                // Use first available anchor that's still in a window
                if let validAnchor = anchors.first(where: { $0.view?.window != nil }),
                   let view = validAnchor.view
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    completionHandler(nil)
                    return
                }
                
                Self.logger.debug("   ⚠️  No valid anchors found (all were removed from windows)")
            }

            // Fallback to center of window
            if let window = targetWindow, let contentView = window.contentView {
                let rect = CGRect(
                    x: contentView.bounds.midX - 10,
                    y: contentView.bounds.maxY - 50,
                    width: 20,
                    height: 20
                )
                popover.show(
                    relativeTo: rect,
                    of: contentView,
                    preferredEdge: .minY
                )
                completionHandler(nil)
                return
            }

            Self.logger.error("DELEGATE: No anchor or contentView available")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available"]
                )
            )
        }
    }

    // MARK: - WKScriptMessageHandler (popup bridge)
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // No custom message handling
    }

    // MARK: - WKNavigationDelegate (popup diagnostics)
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didStartProvisionalNavigation: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Started loading: \(urlString)")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didCommit: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Committed: \(urlString)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.debug("[Popup] didFinish: \"\(urlString)\"")
        PopupConsole.shared.log("[Navigation] Finished: \(urlString)")

        // Get document title
        webView.evaluateJavaScript("document.title") { value, _ in
            let title = (value as? String) ?? "(unknown)"
            Self.logger.debug("[Popup] document.title: \"\(title)\"")
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
                Self.logger.error("[Popup] comprehensive probe error: \(error.localizedDescription)")
                PopupConsole.shared.log(
                    "[Error] Probe failed: \(error.localizedDescription)"
                )
            } else if let dict = value as? [String: Any] {
                Self.logger.debug("[Popup] comprehensive probe: \(dict)")
                PopupConsole.shared.log("[Probe] APIs: \(dict)")
            } else {
                Self.logger.debug("[Popup] comprehensive probe: unexpected result type")
                PopupConsole.shared.log(
                    "[Warning] Probe returned unexpected result"
                )
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
            if let err = err {
                Self.logger.error("[Popup] safeScriptingPatch error: \(err.localizedDescription)")
            }
        }

        // Note: Skipping automatic tabs.query test to avoid potential recursion issues
        // Extensions will call tabs.query naturally, and we can debug through console
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.error("[Popup] didFail: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log(
            "[Error] Navigation failed: \(error.localizedDescription)"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        Self.logger.error("[Popup] didFailProvisional: \(error.localizedDescription) - URL: \(urlString)")
        PopupConsole.shared.log(
            "[Error] Provisional navigation failed: \(error.localizedDescription)"
        )
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Self.logger.debug("[Popup] content process terminated")
        PopupConsole.shared.log("[Critical] WebView process terminated")
    }

    // MARK: - Windows exposure (tabs/windows APIs)

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let bm = browserManagerRef else {
            return nil
        }
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        return windowAdapter
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
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
        onDecision:
            @escaping (
                _ grantedPermissions: Set<WKWebExtension.Permission>,
                _ grantedMatches: Set<WKWebExtension.MatchPattern>
            ) -> Void,
        onCancel: @escaping () -> Void,
        extensionLogo: NSImage
    ) {
        guard let bm = browserManagerRef else {
            onCancel()
            return
        }

        // Convert enums to readable strings for UI
        let reqPerms = requestedPermissions.map { String(describing: $0) }
            .sorted()
        let optPerms = optionalPermissions.map { String(describing: $0) }
            .sorted()
        let reqHosts = requestedMatches.map { String(describing: $0) }.sorted()
        let optHosts = optionalMatches.map { String(describing: $0) }.sorted()

        bm.showDialog {
            StandardDialog(
                header: {
                    EmptyView()
                },
                content: {
                    ExtensionPermissionView(
                        extensionName: extensionDisplayName,
                        requestedPermissions: reqPerms,
                        optionalPermissions: optPerms,
                        requestedHostPermissions: reqHosts,
                        optionalHostPermissions: optHosts,
                        onGrant: {
                            let allPerms = requestedPermissions.union(
                                optionalPermissions
                            )
                            let allHosts = requestedMatches.union(
                                optionalMatches
                            )
                            bm.closeDialog()
                            onDecision(allPerms, allHosts)
                        },
                        onDeny: {
                            bm.closeDialog()
                            onCancel()
                        },
                        extensionLogo: extensionLogo
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
        completionHandler:
            @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: permissions,
            optionalPermissions: extensionContext.webExtension
                .optionalPermissions,
            requestedMatches: extensionContext.webExtension
                .requestedPermissionMatchPatterns,
            optionalMatches: extensionContext.webExtension
                .optionalPermissionMatchPatterns,
            extensionDisplayName: displayName,
            onDecision: { grantedPerms, grantedMatches in
                for p in permissions.union(
                    extensionContext.webExtension.optionalPermissions
                ) {
                    extensionContext.setPermissionStatus(
                        grantedPerms.contains(p)
                            ? .grantedExplicitly : .deniedExplicitly,
                        for: p
                    )
                }
                for m in extensionContext.webExtension
                    .requestedPermissionMatchPatterns.union(
                        extensionContext.webExtension
                            .optionalPermissionMatchPatterns
                    )
                {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m)
                            ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(grantedPerms, nil)
            },
            onCancel: {
                for p in permissions {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: p
                    )
                }
                for m in extensionContext.webExtension
                    .requestedPermissionMatchPatterns
                {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler([], nil)
            },
            extensionLogo: extensionContext.webExtension.icon(
                for: .init(width: 64, height: 64)
            ) ?? NSImage()
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
        completionHandler:
            @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        Self.logger.debug("   URL: \(configuration.url?.absoluteString ?? "nil")")
        Self.logger.debug("   Should be active: \(configuration.shouldBeActive)")
        Self.logger.debug("   Should be pinned: \(configuration.shouldBePinned)")

        guard let bm = browserManagerRef else {
            Self.logger.error("Browser manager reference is nil")
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Browser manager not available"
                    ]
                )
            )
            return
        }

        // Special handling for extension page URLs (options, popup, etc.): use the extension's configuration
        if let url = configuration.url,
            url.scheme?.lowercased() == "safari-web-extension"
                || url.scheme?.lowercased() == "webkit-extension",
            let controller = extensionController,
            let resolvedContext = controller.extensionContext(for: url)
        {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(
                url: url.absoluteString,
                in: space
            )
            let cfg =
                resolvedContext.webViewConfiguration
                ?? BrowserConfiguration.shared.webViewConfiguration
            newTab.applyWebViewConfigurationOverride(cfg)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive {
                bm.tabManager.setActiveTab(newTab)
            }
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
            return
        }

        let targetURL = configuration.url
        if let url = targetURL {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(
                url: url.absoluteString,
                in: space
            )
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive {
                bm.tabManager.setActiveTab(newTab)
            }
            Self.logger.info("Created new tab: \(newTab.name)")

            // Return the created tab adapter to the extension
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
            return
        }
        // No URL specified — create a blank tab
        Self.logger.debug("⚠️ No URL specified, creating blank tab")
        let space = bm.tabManager.currentSpace
        let newTab = bm.tabManager.createNewTab(in: space)
        if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
        Self.logger.info("Created blank tab: \(newTab.name)")

        // Return the created tab adapter to the extension
        let tabAdapter = self.stableAdapter(for: newTab)
        completionHandler(tabAdapter, nil)
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        Self.logger.debug("   Tab URLs: \(configuration.tabURLs.map { $0.absoluteString })")

        guard let bm = browserManagerRef else {
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Browser manager not available"
                    ]
                )
            )
            return
        }

        // OAuth flows from extensions should open in tabs to share the same data store
        // Miniwindows use separate data stores which breaks OAuth flows
        if let firstURL = configuration.tabURLs.first,
            OAuthDetector.isLikelyOAuthPopupURL(firstURL)
        {
            Self.logger.debug(
                "🔐 [DELEGATE] Extension OAuth window detected, opening in new tab: \(firstURL.absoluteString)"
            )
            // Create a new tab in the current space with the same profile/data store
            let newTab = bm.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: bm.tabManager.currentSpace
            )
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
            _ = bm.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: newSpace
            )
        } else {
            _ = bm.tabManager.createNewTab(in: newSpace)
        }
        bm.tabManager.setActiveSpace(newSpace)

        // Return the window adapter
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        Self.logger.info("Created new window (space): \(newSpace.name)")
        completionHandler(windowAdapter, nil)
    }

    // MARK: - Native Messaging Support

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        to applicationId: String,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        
        // Single-shot message handling
        let handler = NativeMessagingHandler(applicationId: applicationId)
        handler.sendMessage(message) { response, error in
            replyHandler(response, error)
        }
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsingMessagePort port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext
    ) {
        guard let applicationId = port.applicationIdentifier else {
            Self.logger.error("[NativeMessaging] Port connection missing application identifier")
            return
        }
        
        
        let handler = NativeMessagingHandler(applicationId: applicationId)
        handler.connect(port: port)
        
        // Keep a strong reference to the handler if needed, but usually the port delegate handles lifecycle
        // For now, we rely on the port retaining the delegate or the handler retaining itself via the port relationship
        // (Note: In a production app, we might need to manage these references in a set)
    }


    // Open the extension's options page (inside a browser tab)
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        Self.logger.debug("   Extension: \(displayName)")

        // Resolve the options page URL. Prefer the SDK property when available.
        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = self.computeOptionsPageURL(for: extensionContext)
        let kvcURL =
            (extensionContext as AnyObject).value(forKey: "optionsPageURL")
            as? URL
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
            Self.logger.error("No options page URL found for extension")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "No options page URL found for extension"
                    ]
                )
            )
            return
        }

        Self.logger.info("Opening options page: \(optionsURL.absoluteString)")

        // Create a dedicated WebView using the extension's webViewConfiguration so
        // the WebExtensions environment (browser/chrome APIs) is available.
        let config =
            extensionContext.webViewConfiguration
            ?? BrowserConfiguration.shared.webViewConfiguration
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
        let aliasScript = WKUserScript(
            source: aliasJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(aliasScript)

        // SECURITY FIX: Load the options page with restricted file access
        if optionsURL.isFileURL {
            // SECURITY FIX: Only allow access to the specific extension directory, not the entire package
            guard
                let extId = extensionContexts.first(where: {
                    $0.value === extensionContext
                })?.key,
                let inst = installedExtensions.first(where: { $0.id == extId })
            else {
                Self.logger.error("Could not resolve extension for secure file access")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not resolve extension for secure file access"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Validate that the options URL is within the extension directory
            let extensionRoot = URL(
                fileURLWithPath: inst.packagePath,
                isDirectory: true
            )

            // SECURITY FIX: Normalize paths to prevent path traversal attacks
            let normalizedExtensionRoot = extensionRoot.standardizedFileURL
            let normalizedOptionsURL = optionsURL.standardizedFileURL

            // Check if options URL is within the extension directory (prevent path traversal)
            if !normalizedOptionsURL.path.hasPrefix(
                normalizedExtensionRoot.path
            ) {
                Self.logger.debug("   Extension root: \(normalizedExtensionRoot.path)")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Options URL outside extension directory"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Additional validation - ensure no path traversal attempts
            let relativePath = String(
                normalizedOptionsURL.path.dropFirst(
                    normalizedExtensionRoot.path.count
                )
            )
            if relativePath.contains("..") || relativePath.hasPrefix("/") {
                Self.logger.error("SECURITY: Path traversal attempt detected: \(relativePath)")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Path traversal attempt detected"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Only grant access to the extension's specific directory, not parent directories
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
            webView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Keep window alive keyed by extension id
        if let extId = extensionContexts.first(where: {
            $0.value === extensionContext
        })?.key {
            optionsWindows[extId] = window
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    // Resolve options page URL from manifest as a fallback for SDKs that don't expose optionsPageURL
    @available(macOS 15.5, *)
    private func computeOptionsPageURL(for context: WKWebExtensionContext)
        -> URL?
    {
        Self.logger.debug("   Extension: \(context.webExtension.displayName ?? "Unknown")")
        Self.logger.debug("   Unique ID: \(context.uniqueIdentifier)")

        // Try to map the context back to our InstalledExtension via dictionary identity
        if let extId = extensionContexts.first(where: { $0.value === context })?
            .key,
            let inst = installedExtensions.first(where: { $0.id == extId })
        {
            Self.logger.info("Found installed extension: \(inst.name)")

            // MV3/MV2: options_ui.page; MV2 legacy: options_page
            var pagePath: String?
            if let options = inst.manifest["options_ui"] as? [String: Any],
                let p = options["page"] as? String, !p.isEmpty
            {
                pagePath = p
                Self.logger.debug("   Found options_ui.page: \(p)")
            } else if let p = inst.manifest["options_page"] as? String,
                !p.isEmpty
            {
                pagePath = p
                Self.logger.debug("   Found options_page: \(p)")
            } else {

                // Fallback: Check for common options page paths
                let commonPaths = [
                    "ui/options/index.html",
                    "options/index.html",
                    "options.html",
                    "settings.html",
                ]

                for path in commonPaths {
                    let fullFilePath = URL(fileURLWithPath: inst.packagePath)
                        .appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: fullFilePath.path)
                    {
                        pagePath = path
                        Self.logger.info("Found options page at: \(path)")
                        break
                    }
                }
            }

            if let page = pagePath {
                // Build an extension-scheme URL using the context baseURL
                let extBase = context.baseURL
                let optionsURL = extBase.appendingPathComponent(page)
                Self.logger.info("Generated options extension URL: \(optionsURL.absoluteString)")
                return optionsURL
            } else {
                Self.logger.error("No options page found in manifest or common paths")
                Self.logger.debug("   Manifest keys: \(inst.manifest.keys.sorted())")
            }
        } else {
            Self.logger.error("Could not find installed extension for context")
        }
        return nil
    }
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<
            WKWebExtension.MatchPattern
        >,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: [],
            optionalPermissions: [],
            requestedMatches: matchPatterns,
            optionalMatches: [],
            extensionDisplayName: displayName,
            onDecision: { _, grantedMatches in
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m)
                            ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(grantedMatches, nil)
            },
            onCancel: {
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler([], nil)
            },
            extensionLogo: extensionContext.webExtension.icon(
                for: .init(width: 64, height: 64)
            ) ?? NSImage()
        )
    }

    // URL-specific access prompts (used for cross-origin network requests from extension contexts)
    // Auto-grant URLs that fall within the extension's already-granted host permissions.
    // Only prompt for URLs the extension has no declared permission for.
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        // Check each URL against the extension's granted permissions
        var granted = Set<URL>()
        var needsPrompt = Set<URL>()

        for url in urls {
            let status = extensionContext.permissionStatus(for: url)
            if status == .grantedExplicitly || status == .grantedImplicitly {
                granted.insert(url)
            } else {
                needsPrompt.insert(url)
            }
        }

        // If all URLs are already covered by granted permissions, auto-approve
        if needsPrompt.isEmpty {
            completionHandler(granted, nil)
            return
        }

        // Prompt only for URLs not covered by existing permissions
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"

        guard let bm = browserManagerRef else {
            // No UI available — grant what we can, deny the rest
            completionHandler(granted, nil)
            return
        }

        let urlStrings = needsPrompt.map { $0.absoluteString }.sorted()

        bm.showDialog {
            StandardDialog(
                header: { EmptyView() },
                content: {
                    ExtensionPermissionView(
                        extensionName: displayName,
                        requestedPermissions: [],
                        optionalPermissions: [],
                        requestedHostPermissions: urlStrings,
                        optionalHostPermissions: [],
                        onGrant: {
                            bm.closeDialog()
                            completionHandler(urls, nil)
                        },
                        onDeny: {
                            bm.closeDialog()
                            completionHandler(granted, nil)
                        },
                        extensionLogo: extensionContext.webExtension.icon(
                            for: .init(width: 64, height: 64)
                        ) ?? NSImage()
                    )
                },
                footer: { EmptyView() }
            )
        }
    }

    // MARK: - URL Conversion Helpers

    /// Convert extension URL (webkit-extension:// or safari-web-extension://) to file URL
    @available(macOS 15.5, *)
    private func convertExtensionURLToFileURL(
        _ urlString: String,
        for context: WKWebExtensionContext
    ) -> URL? {
        Self.logger.debug("🔄 [convertExtensionURLToFileURL] Converting: \(urlString)")

        // Extract the path from the extension URL
        guard let url = URL(string: urlString) else {
            Self.logger.error("Invalid URL string")
            return nil
        }

        let path = url.path

        // Find the corresponding installed extension
        if let extId = extensionContexts.first(where: { $0.value === context })?
            .key,
            let inst = installedExtensions.first(where: { $0.id == extId })
        {
            Self.logger.debug("   📦 Found extension: \(inst.name)")

            // Build file URL from extension package path
            let extensionURL = URL(fileURLWithPath: inst.packagePath)
            let fileURL = extensionURL.appendingPathComponent(
                path.hasPrefix("/") ? String(path.dropFirst()) : path
            )

            // Verify the file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                Self.logger.info("File exists at: \(fileURL.path)")
                return fileURL
            } else {
                Self.logger.error("File not found at: \(fileURL.path)")
            }
        } else {
            Self.logger.error("Could not find installed extension for context")
        }

        return nil
    }

    // MARK: - Extension Diagnostics

    /// Probe the background webview after load to check for JS-level errors.
    /// Output goes to Xcode debug console via NSLog for easy visibility.
    @available(macOS 15.4, *)
    private func probeBackgroundHealth(for context: WKWebExtensionContext, name: String) {
        // First probe at 3s, second at 8s (gives boot saga time to complete/fail)
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let bgWV = (context as AnyObject).value(forKey: "_backgroundWebView") as? WKWebView else {
                    NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s: No background webview found")
                    return
                }

                bgWV.evaluateJavaScript("""
                    (function() {
                        var b = typeof browser !== 'undefined' ? browser : (typeof chrome !== 'undefined' ? chrome : null);
                        if (!b) return JSON.stringify({error: 'No browser/chrome API available'});

                        var result = {
                            url: location.href,
                            apiNamespace: typeof browser !== 'undefined' ? 'browser' : 'chrome',
                            runtime: !!b.runtime,
                            runtimeId: b.runtime ? b.runtime.id : null,
                            alarms: !!b.alarms,
                            storage: !!b.storage,
                            storageLocal: !!(b.storage && b.storage.local),
                            storageSession: !!(b.storage && b.storage.session),
                            storageSync: !!(b.storage && b.storage.sync),
                            tabs: !!b.tabs,
                            scripting: !!b.scripting,
                            webNavigation: !!b.webNavigation,
                            permissions: !!b.permissions,
                            action: !!b.action,
                            notifications: !!b.notifications,
                            webRequest: !!b.webRequest,
                            declarativeNetRequest: !!b.declarativeNetRequest,
                            contextMenus: !!b.contextMenus,
                            commands: !!b.commands,
                            i18n: !!b.i18n,
                            windows: !!b.windows,
                        };

                        // Try to detect if there were uncaught errors
                        try {
                            if (b.runtime && b.runtime.lastError) {
                                result.lastError = b.runtime.lastError.message || String(b.runtime.lastError);
                            }
                        } catch(e) {}

                        return JSON.stringify(result, null, 2);
                    })()
                """) { result, error in
                    if let json = result as? String {
                        NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s background APIs:\\n\(json)")
                    } else if let error = error {
                        NSLog("[EXT-HEALTH] [\(name)] +\(Int(delay))s probe FAILED: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Comprehensive diagnostic for extension content script + messaging state
    @available(macOS 15.5, *)
    func diagnoseExtensionState(for webView: WKWebView, url: URL) {
        guard let controller = extensionController else {
            Self.logger.debug("No extension controller")
            return
        }

        let host = url.host ?? "?"
        let ctxCount = controller.extensionContexts.count
        let configCtrl = webView.configuration.webExtensionController
        let sameCtrl = configCtrl === controller

        Self.logger.debug("\(host): contexts=\(ctxCount), webviewHasCtrl=\(configCtrl != nil), sameCtrl=\(sameCtrl)")

        for (extId, ctx) in extensionContexts {
            let name = ctx.webExtension.displayName ?? extId
            let hasBackground = ctx.webExtension.hasBackgroundContent
            let hasInjected = ctx.webExtension.hasInjectedContent
            let baseURL = ctx.baseURL
            let perms = ctx.currentPermissions.map { String(describing: $0) }.joined(separator: ", ")
            let matchPatterns = ctx.grantedPermissionMatchPatterns.map { String(describing: $0) }.joined(separator: ", ")
            let urlAccess = ctx.permissionStatus(for: url)

            Self.logger.debug("'\(name)': hasBackground=\(hasBackground), hasInjected=\(hasInjected), baseURL=\(baseURL), urlAccess=\(urlAccess.rawValue)")
            Self.logger.debug("'\(name)' perms: \(perms)")
            Self.logger.debug("'\(name)' matchPatterns: \(matchPatterns)")

            // Try to reach background webview via KVC
            let bgWV = (ctx as AnyObject).value(forKey: "_backgroundWebView") as? WKWebView
            Self.logger.debug("'\(name)' bgWebView via KVC: \(bgWV != nil ? bgWV!.url?.absoluteString ?? "no-url" : "nil")")

            if let bgWV = bgWV {
                bgWV.evaluateJavaScript("""
                    JSON.stringify({
                        url: location.href,
                        hasRuntime: typeof chrome !== 'undefined' && typeof chrome.runtime !== 'undefined',
                        runtimeId: (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime.id : null,
                        listeners: {
                            onConnect: typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.onConnect ? chrome.runtime.onConnect.hasListeners() : false,
                            onMessage: typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.onMessage ? chrome.runtime.onMessage.hasListeners() : false
                        }
                    })
                """) { result, error in
                    let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
                    if let json = result as? String {
                        logger.debug("'\(name)' background: \(json)")
                    } else if let error = error {
                        logger.debug("'\(name)' background eval error: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Check page-side: Dark Reader styles
        webView.evaluateJavaScript("""
            JSON.stringify({
                drCount: document.querySelectorAll('style.darkreader, style[class*="darkreader"]').length,
                allStyles: document.querySelectorAll('style').length,
                scripts: document.querySelectorAll('script').length
            })
        """) { result, _ in
            let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
            if let json = result as? String {
                logger.debug("\(host) page: \(json)")
            }
        }

        // Check again after 3s to see if content scripts ran and then cleaned up
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            webView.evaluateJavaScript(
                "'drCount=' + document.querySelectorAll('style[class*=\"darkreader\"]').length"
            ) { result, _ in
                let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")
                logger.debug("\(host) +3s: \(String(describing: result ?? "nil"))")
            }
        }
    }

    // MARK: - Extension Resource Testing

    /// List all installed extensions with their UUIDs for easy testing
    func listInstalledExtensionsForTesting() {
        Self.logger.info("Installed Extensions ===")

        if installedExtensions.isEmpty {
            Self.logger.error("No extensions installed")
            return
        }

        for (index, ext) in installedExtensions.enumerated() {
            Self.logger.debug("\(index + 1). \(ext.name)")
            Self.logger.debug("   UUID: \(ext.id)")
            Self.logger.debug("   Version: \(ext.version)")
            Self.logger.debug("   Manifest Version: \(ext.manifestVersion)")
            Self.logger.info("Enabled: \(ext.isEnabled)")
            Self.logger.debug("")
        }
    }

    // MARK: - Chrome Web Store Integration

    /// Install extension from Chrome Web Store by extension ID
    func installFromWebStore(
        extensionId: String,
        completionHandler:
            @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        WebStoreDownloader.downloadExtension(extensionId: extensionId) {
            [weak self] result in
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
                completionHandler(
                    .failure(.installationFailed(error.localizedDescription))
                )
            }
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

// MARK: - Popup UI Delegate for Context Menu

@available(macOS 15.4, *)
class PopupUIDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionPopup")
    weak var webView: WKWebView?
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }
    
    #if os(macOS)
    func webView(
        _ webView: WKWebView,
        contextMenu: NSMenu
    ) -> NSMenu {
        // Add reload menu item at the top
        let reloadItem = NSMenuItem(
            title: "Reload Extension Popup",
            action: #selector(reloadPopup),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        
        let menu = NSMenu()
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        
        // Add original menu items
        for item in contextMenu.items {
            menu.addItem(item.copy() as! NSMenuItem)
        }
        
        return menu
    }
    #endif
    
    @objc private func reloadPopup() {
        Self.logger.debug("🔄 Reloading extension popup...")
        webView?.reload()
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Self.logger.info("[POPUP] Navigation finished")
        Self.logger.debug("   Final URL: \(webView.url?.absoluteString ?? "nil")")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("[POPUP] Navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("[POPUP] Provisional navigation failed: \(error.localizedDescription)")
        Self.logger.debug("   URL: \(webView.url?.absoluteString ?? "nil")")
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

// MARK: - Native Messaging Handler

@available(macOS 15.4, *)
// MARK: - Native Messaging Handler

class NativeMessagingHandler: NSObject {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "NativeMessaging")
    let applicationId: String
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private weak var port: WKWebExtension.MessagePort?
    private var outputBuffer = Data()
    
    init(applicationId: String) {
        self.applicationId = applicationId
        super.init()
    }
    
    func sendMessage(_ message: Any, completion: @escaping (Any?, Error?) -> Void) {
        // Single-shot message: Launch, write, read response, terminate
        launchProcess { [weak self] success in
            guard success, let self = self else {
                completion(nil, NSError(domain: "NativeMessaging", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch host"]))
                return
            }

            do {
                // Disable the readabilityHandler to avoid conflict with long-lived port mode
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil

                try self.writeMessage(message)

                // Read the response synchronously with a 5-second timeout
                let readHandle = self.outputPipe?.fileHandleForReading
                var responseData: Any?
                var readError: Error?
                let semaphore = DispatchSemaphore(value: 0)

                DispatchQueue.global(qos: .userInitiated).async {
                    defer { semaphore.signal() }
                    guard let handle = readHandle else {
                        readError = NSError(domain: "NativeMessaging", code: 3, userInfo: [NSLocalizedDescriptionKey: "No output pipe"])
                        return
                    }

                    // Read 4-byte length prefix
                    let lengthData = handle.readData(ofLength: 4)
                    guard lengthData.count == 4 else {
                        readError = NSError(domain: "NativeMessaging", code: 4, userInfo: [NSLocalizedDescriptionKey: "Host closed without response"])
                        return
                    }

                    let length: UInt32 = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
                    let jsonData = handle.readData(ofLength: Int(length))

                    if let json = try? JSONSerialization.jsonObject(with: jsonData) {
                        responseData = json
                    } else {
                        readError = NSError(domain: "NativeMessaging", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse host response"])
                    }
                }

                let result = semaphore.wait(timeout: .now() + 5)
                self.terminateProcess()

                if result == .timedOut {
                    completion(nil, NSError(domain: "NativeMessaging", code: 6, userInfo: [NSLocalizedDescriptionKey: "Host response timed out"]))
                } else if let error = readError {
                    completion(nil, error)
                } else {
                    completion(responseData, nil)
                }
            } catch {
                self.terminateProcess()
                completion(nil, error)
            }
        }
    }
    
    func connect(port: WKWebExtension.MessagePort) {
        self.port = port
        
        // Use closure-based handlers since delegate is not available
        port.messageHandler = { [weak self] (port, message) in
            do {
                try self?.writeMessage(message)
            } catch {
                Self.logger.error("[NativeMessaging] Failed to write to host: \(error)")
            }
        }
        
        port.disconnectHandler = { [weak self] port in
            self?.terminateProcess()
        }
        
        launchProcess { [weak self] success in
            guard let self = self else { return }
            if !success {
                Self.logger.error("[NativeMessaging] Failed to launch host for \(self.applicationId)")
                port.disconnect()
            }
        }
    }
    
    // MARK: - Process Management
    
    private func launchProcess(completion: @escaping (Bool) -> Void) {
        // Find the native host manifest and binary
        // This is a simplified implementation. In a real browser, we'd search:
        // ~/Library/Application Support/Google/Chrome/NativeMessagingHosts
        // /Library/Application Support/Google/Chrome/NativeMessagingHosts
        // etc.
        
        // For iCloud Passwords specifically (com.apple.passwordmanager), it's a system service.
        // However, standard Native Messaging expects a binary path in a manifest.
        
        // TODO: Implement full manifest lookup. 
        // For now, we'll log the attempt. If the user has a specific host in mind, we'd need its path.
        
        Self.logger.debug("Launching host for \(self.applicationId)...")
        
        // MOCK: Since we can't easily launch arbitrary binaries from sandbox without entitlements/manifests,
        // we will simulate a successful connection for known hosts to prevent extension errors,
        // or fail gracefully.
        
        // If it's iCloud Passwords, we might need to do more.
        // But for "infrastructure", providing the hooks is step 1.
        
        // We'll return false for now to indicate "host not found" rather than hanging,
        // unless we find a valid manifest.
        
        // If we want to support it, we need to find the manifest.
        // Let's try to look in standard paths.
        
        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let manifestName = "\(self.applicationId).json"
            let browserDirs = [
                // Nook-specific (highest priority)
                "Library/Application Support/Nook/NativeMessagingHosts",
                // Chrome
                "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                // Chromium
                "Library/Application Support/Chromium/NativeMessagingHosts",
                // Microsoft Edge
                "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
                // Brave
                "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
                // Firefox / Mozilla
                "Library/Application Support/Mozilla/NativeMessagingHosts",
            ]
            var paths: [URL] = []
            for dir in browserDirs {
                // User-level
                paths.append(home.appendingPathComponent(dir).appendingPathComponent(manifestName))
                // System-level
                paths.append(URL(fileURLWithPath: "/\(dir)").appendingPathComponent(manifestName))
            }
            
            for path in paths {
                if let data = try? Data(contentsOf: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let binaryPath = json["path"] as? String {
                    
                    Self.logger.info("Found manifest at \(path.path)")
                    
                    // Launch it
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: binaryPath)
                    
                    let input = Pipe()
                    let output = Pipe()
                    let error = Pipe()
                    
                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = error
                    
                    self.inputPipe = input
                    self.outputPipe = output
                    self.errorPipe = error
                    self.process = process
                    
                    // Handle stdout (messages from host)
                    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            self?.handleOutput(data)
                        }
                    }
                    
                    do {
                        try process.run()
                        Self.logger.debug("   🚀 Process launched!")
                        completion(true)
                        return
                    } catch {
                        Self.logger.error("Failed to launch process: \(error)")
                    }
                }
            }
            
            Self.logger.debug("   ⚠️ No manifest found for \(self.applicationId)")
            completion(false)
        }
    }
    
    private func terminateProcess() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }
    
    private func writeMessage(_ message: Any) throws {
        guard let input = inputPipe else {
            throw NSError(domain: "NativeMessaging", code: 2, userInfo: [NSLocalizedDescriptionKey: "No input pipe available — host process not running"])
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
        var length = UInt32(jsonData.count)
        
        // Native messaging protocol: 4 bytes length (native byte order) + JSON
        let lengthData = Data(bytes: &length, count: 4)
        
        try input.fileHandleForWriting.write(contentsOf: lengthData)
        try input.fileHandleForWriting.write(contentsOf: jsonData)
    }
    
    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        // Process all complete messages in the buffer
        while outputBuffer.count >= 4 {
            // Read 4-byte length prefix (native byte order)
            let length: UInt32 = outputBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }
            let totalNeeded = 4 + Int(length)

            guard outputBuffer.count >= totalNeeded else {
                // Wait for more data
                break
            }

            let jsonData = outputBuffer.subdata(in: 4..<totalNeeded)
            outputBuffer.removeSubrange(0..<totalNeeded)

            if let json = try? JSONSerialization.jsonObject(with: jsonData) {
                Self.logger.debug("Received from host: \(String(describing: json))")
                port?.sendMessage(json) { _ in }
            } else {
                Self.logger.error("Failed to parse JSON from host (\(jsonData.count) bytes)")
            }
        }
    }
}
