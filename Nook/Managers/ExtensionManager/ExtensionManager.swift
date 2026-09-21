// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager.swift
//  Nook
//
//  ExtensionManager: WKWebExtensionController owner and extension registry
//

import AppKit
import Foundation
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import NookWeb

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
    // Scope: extensions are global. One controller, one install/enabled state, and one
    // storage namespace shared by every space. Private (ephemeral) tabs get no controller.

    internal var extensionController: WKWebExtensionController?
    internal var extensionContexts: [String: WKWebExtensionContext] = [:]
    var actionAnchors: [String: [WeakAnchor]] = [:]
    /// Observer tokens per extension so anchor observers can be removed when anchors change
    var anchorObserverTokens: [String: [Any]] = [:]
    // Keep options windows alive per extension id
    var optionsWindows: [String: NSWindow] = [:]
    /// Stable tab adapters by item id; they resolve the page session on each call.
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    /// Items the controller has been told about via didOpenTab. Other tab events are only
    /// forwarded for these, so private and never-loaded pages stay invisible to extensions.
    var openedTabIDs: Set<UUID> = []
    /// One adapter per regular window, by BrowserWindowState id.
    var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    /// Live `chrome.windows.create({type: "popup"})` windows; each removes itself when closed.
    var extensionPopupWindows: [ExtensionPopupWindow] = []
    weak var browserManagerRef: BrowserManager?
    // UI delegate for popup context menus and navigation
    var popupUIDelegate: PopupUIDelegate?
    // Strong reference to clipboard handler to prevent ARC deallocation
    var popupClipboardHandler: PopupClipboardHandler?

    let context: ModelContext

    // Native messaging hosts known to be missing (no manifest found for this extension).
    // Prevents repeated manifest lookups and log spam from extensions polling.
    var unavailableNativeHosts: Set<String> = []

    // Strong references to active native messaging port handlers; removed on disconnect.
    var nativeMessagingHandlers: [NativeMessagingHandler] = []

    // Internal native port handlers for Safari extensions that expect the host app
    // to respond on native messaging channels (keyed by applicationIdentifier).
    var internalPortHandlers: [String: any InternalNativePortHandler] = [:]

    /// Last automatic store update check, persisted so relaunches do not re-check.
    static let lastUpdateCheckKey = "Nook.Extensions.LastUpdateCheck"
    var isCheckingForUpdates = false

    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable =
            ExtensionUtils.isExtensionSupportAvailable
        super.init()

        if isExtensionSupportAvailable {
            setupExtensionController()
            loadInstalledExtensions()
            registerInternalNativePortHandlers()
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkForExtensionUpdatesIfDue() }
            }
        }
    }

    // MARK: - Setup

    private func setupExtensionController() {
        // Persistent controller identity: extension storage lives under this identifier.
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

        // Extension pages (background, popup, options) use one persistent store keyed by the
        // controller identifier. `controller.configuration` returns a copy, so this cannot be
        // changed after init; everything must be set on `config` before creating the controller.
        config.defaultWebsiteDataStore = WKWebsiteDataStore(forIdentifier: config.identifier!)
        // Background pages must share the page webviews' configuration for runtime messaging.
        config.webViewConfiguration = sharedWebConfig

        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        self.extensionController = controller

        // Associate browsing webviews with this controller so content scripts inject.
        sharedWebConfig.webExtensionController = controller

        Self.logger.info("WKWebExtensionController initialized (storage ID \(config.identifier?.uuidString ?? "none", privacy: .public))")
    }

    /// Register internal native port handlers for Safari extensions that expect
    /// the host app to handle native messaging (e.g. biometric unlock).
    private func registerInternalNativePortHandlers() {
        let bitwarden = BitwardenBiometricHandler()
        for appId in BitwardenBiometricHandler.applicationIdentifiers {
            internalPortHandlers[appId] = bitwarden
        }
        Self.logger.debug("Registered \(self.internalPortHandlers.count) internal native port handlers")
    }

    /// Lookup an internal handler for a native messaging application identifier. Only the
    /// extension the handler was written for gets it: any extension can name any application.
    func internalHandler(
        for applicationId: String, context: WKWebExtensionContext
    ) -> (any InternalNativePortHandler)? {
        guard let handler = internalPortHandlers[applicationId],
              type(of: handler).extensionIdentifiers.contains(context.uniqueIdentifier)
        else { return nil }
        return handler
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

    /// Connect the browser manager so we can expose tabs/windows and present UI.
    func attach(browserManager: BrowserManager) {
        let isFirstAttach = browserManagerRef == nil
        self.browserManagerRef = browserManager
        guard let controller = extensionController else { return }
        if isFirstAttach { observeWindowEvents() }

        // Windows first, then only pages that already have web views. Pages without one
        // report themselves through notifyTabOpened when their view is created; registering
        // a tab with a nil web view caches stale state and breaks chrome.runtime messaging.
        let windows = openWindowAdapters
        let sessions = browserManager.tabs.sessions.filter { !$0.isPrivate && !$0.isUnloaded }
        for session in sessions { notifyTabOpened(session) }

        if let focused = browserManager.windowRegistry?.activeWindow,
           let adapter = windowAdapter(for: focused) {
            controller.didFocusWindow(adapter)
            if let session = browserManager.tabs.selectedSession(in: focused), !session.isUnloaded {
                notifyTabActivated(new: session, previous: nil)
            }
        }

        Self.logger.info("Attached to browser manager with \(windows.count) windows, \(sessions.count) open pages")
    }

    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isPopupActive = false
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

