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
import NookBlocker
import NookWeb

@MainActor
final class ExtensionManager: NSObject, ObservableObject,
    WKWebExtensionControllerDelegate, NSPopoverDelegate
{
    /// The default extension set: today's controller, store and folder.
    static let shared = ExtensionManager(setID: nil)
    nonisolated static let logger = Logger(subsystem: "com.nook.browser", category: "Extensions")

    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    @Published var isPopupActive: Bool = false
    @Published var extensionsLoaded: Bool = false
    // Scope: one instance per extension set (`ExtensionSetRegistry`). Each has its own controller,
    // installs and storage; a profile's pages use its set's controller. Private windows run only
    // extensions the person allowed there (`hasAccessToPrivateData`).

    /// The set this instance runs. The default set's id is its controller identifier.
    let setID: UUID
    let isDefaultSet: Bool
    /// The configuration this set's pages copy. The default set's is the shared one.
    let baseWebViewConfiguration: WKWebViewConfiguration

    internal var extensionController: WKWebExtensionController?
    internal var extensionContexts: [String: WKWebExtensionContext] = [:]
    var actionAnchors: [String: [WeakAnchor]] = [:]
    /// The action popover last shown, while WebKit still holds it.
    weak var shownPopover: NSPopover?
    // Keep options windows alive per extension id
    var optionsWindows: [String: NSWindow] = [:]
    /// Stable tab adapters by item id; they resolve the page session on each call.
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    /// Items the controller has been told about via didOpenTab. Other tab events are only
    /// forwarded for these, so never-loaded pages stay invisible to extensions.
    var openedTabIDs: Set<UUID> = []
    /// Each space's tab order for the adapters, kept until the tab model changes.
    let tabOrders = ExtensionTabOrderCache()
    /// One adapter per window, by BrowserWindowState id.
    var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    /// Live `chrome.windows.create({type: "popup"})` windows; each removes itself when closed.
    var extensionPopupWindows: [ExtensionPopupWindow] = []
    weak var browserManagerRef: BrowserManager?
    // UI delegate for popup context menus and navigation
    var popupUIDelegate: PopupUIDelegate?
    // Strong reference to clipboard handler to prevent ARC deallocation
    var popupClipboardHandler: PopupClipboardHandler?

    let context: ModelContext
    /// The install store of a set other than the default, which uses `Persistence.shared`.
    private let setStore: ModelContainer?

    // Native messaging hosts known to be missing (no manifest found for this extension).
    // Prevents repeated manifest lookups and log spam from extensions polling.
    var unavailableNativeHosts: Set<String> = []

    // Strong references to active native messaging port handlers; removed on disconnect.
    var nativeMessagingHandlers: [NativeMessagingHandler] = []

    // Internal native port handlers for Safari extensions that expect the host app
    // to respond on native messaging channels (keyed by applicationIdentifier).
    var internalPortHandlers: [String: any InternalNativePortHandler] = [:]

    /// Extension APIs WebKit lacks, answered natively for the compatibility shim.
    let compatBridge = ExtensionCompatBridge()
    /// Notification observers of this manager, removed when its set is torn down.
    var observers: [NSObjectProtocol] = []
    lazy var compatWebNavigation = ExtensionCompatWebNavigation(bridge: compatBridge)
    lazy var compatManagement = ExtensionCompatManagement(bridge: compatBridge)
    lazy var compatSidePanel = ExtensionCompatSidePanel(set: isDefaultSet ? nil : setID)
    /// The app's one notification delegate. The center holds it weakly.
    var notificationCenter: ExtensionNotificationCenter { .shared }

    /// Last automatic store update check, persisted so relaunches do not re-check.
    var lastUpdateCheckKey: String {
        "Nook.Extensions.LastUpdateCheck" + (isDefaultSet ? "" : ".\(setID.uuidString)")
    }
    static let controllerIdentifierKey = "Nook.WKWebExtensionController.Identifier"
    var isCheckingForUpdates = false
    /// Ids with an install in flight.
    var installingIDs: Set<String> = []

    /// `nil` is the default set. Use `ExtensionSetRegistry` for any other.
    init(setID: UUID?) {
        if let setID {
            self.setID = setID
            self.isDefaultSet = false
            // A context does not keep its container alive, so the instance does.
            let container = Self.setContainer(Self.setDirectory(setID))
            self.setStore = container
            self.context = container.mainContext
            let base = BrowserConfiguration.shared.webViewConfiguration.copy() as! WKWebViewConfiguration
            // Extension pages run in this configuration's store. In a shared store two sets with
            // the same extension have one origin and one service worker, and only one set answers.
            base.websiteDataStore = WKWebsiteDataStore(forIdentifier: setID)
            // A copy shares its user content controller, and two controllers would both add
            // their content scripts to it. No rule lists: extension pages are not ad-blocked.
            let scripts = base.userContentController.userScripts.nookOwned
            base.userContentController = WKUserContentController()
            scripts.forEach(base.userContentController.addUserScript)
            self.baseWebViewConfiguration = base
        } else {
            let defaults = UserDefaults.standard
            let stored = defaults.string(forKey: Self.controllerIdentifierKey).flatMap(UUID.init(uuidString:))
            let id = stored ?? UUID()
            if stored == nil { defaults.set(id.uuidString, forKey: Self.controllerIdentifierKey) }
            self.setID = id
            self.isDefaultSet = true
            self.setStore = nil
            self.context = Persistence.shared.container.mainContext
            self.baseWebViewConfiguration = BrowserConfiguration.shared.webViewConfiguration
        }
        self.isExtensionSupportAvailable =
            ExtensionUtils.isExtensionSupportAvailable
        super.init()

        if isExtensionSupportAvailable {
            setupExtensionController()
            setupCompatBridge()
            loadInstalledExtensions()
            registerInternalNativePortHandlers()
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkForExtensionUpdatesIfDue() }
            })
        }
    }

    // MARK: - Setup

    private func setupExtensionController() {
        // Persistent controller identity: extension storage lives under this identifier.
        let config = WKWebExtensionController.Configuration(identifier: setID)
        // `controller.configuration` returns a copy, so everything is set on `config` before the
        // controller exists.
        config.defaultWebsiteDataStore = WKWebsiteDataStore(forIdentifier: setID)
        // Background pages must share the page webviews' configuration for runtime messaging.
        // Extension pages (background, popup, options) also run in this configuration's store,
        // whatever `defaultWebsiteDataStore` says (measured on macOS 27).
        config.webViewConfiguration = baseWebViewConfiguration

        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        self.extensionController = controller

        // Associate browsing webviews with this controller so content scripts inject.
        baseWebViewConfiguration.webExtensionController = controller

        Self.logger.info("WKWebExtensionController initialized (storage ID \(self.setID.uuidString, privacy: .public), default \(self.isDefaultSet))")
    }

    /// Packages and the install store of a set other than the default.
    static func setDirectory(_ setID: UUID) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("\(SharedSupportFolder.name)/Extensions/Sets/\(setID.uuidString)")
    }

    private static func setContainer(_ directory: URL) -> ModelContainer {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = ModelConfiguration(url: directory.appendingPathComponent("extensions.store"), cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: ExtensionEntity.self, configurations: stored) { return container }
        logger.error("Extension set store at \(directory.path, privacy: .public) failed to open; using memory")
        return try! ModelContainer(for: ExtensionEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
              type(of: handler).extensionIdentifiers.contains(context.uniqueIdentifier),
              !ExtensionStore.isValidExtensionID(context.uniqueIdentifier) || hasStoreVerifiedChromeID(context)
        else { return nil }
        return handler
    }

    /// A Chrome-format ID is only a claim: a sideload gets one by copying a store build's public
    /// manifest `key`. A Web Store or Edge install is what proves it.
    func hasStoreVerifiedChromeID(_ context: WKWebExtensionContext) -> Bool {
        let id = context.uniqueIdentifier
        guard ExtensionStore.isValidExtensionID(id),
              let store = fetchEntity(id: id)?.sourceStore.flatMap(ExtensionStore.init(rawValue:))
        else { return false }
        return store == .chrome || store == .edge
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
        let sessions = browserManager.tabs.sessions.filter {
            !$0.isUnloaded && ExtensionSetRegistry.shared.setID(for: $0) == setID
        }
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

    /// Unloads every extension of a set that is being deleted.
    func tearDown() {
        guard extensionController != nil else { return }
        unloadContexts()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        installedExtensions = []
        extensionController = nil
    }

    /// Unloads every extension and forgets the windows and tabs it knew; the controller stays.
    private func unloadContexts() {
        guard let controller = extensionController else { return }
        for adapter in windowAdapters.values { controller.didCloseWindow(adapter) }
        for context in controller.extensionContexts {
            // Stops the idle monitor and timers an extension left armed, as every other unload does.
            compatBridge.contextUnloaded(context)
            try? controller.unload(context)
        }
        windowAdapters = [:]
        tabAdapters = [:]
        openedTabIDs = []
        extensionContexts = [:]
    }

    /// True while no profile or private window runs this set: its installs stay and none loads.
    /// The default set's manager is a singleton, so it idles where another set is torn down.
    private(set) var isIdle = false

    /// A view body can wake it, so the load runs after the update, which it publishes from.
    func setIdle(_ idle: Bool) {
        guard idle != isIdle, isExtensionSupportAvailable else { return }
        isIdle = idle
        if idle { unloadContexts() } else { Task { @MainActor in self.loadInstalledExtensions() } }
    }

    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        Self.logger.notice("Extension popup closed")
        DispatchQueue.main.async {
            self.isPopupActive = false
        }
    }
}

// MARK: - Weak View Reference Helper
final class WeakAnchor {
    weak var view: NSView?
    init(view: NSView?) { self.view = view }
}

