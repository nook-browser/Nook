// Licensed under GPL-3.0. See LICENSE.
//
//  AppDelegate.swift
//  Nook
//
//  Application lifecycle delegate handling app termination, URL events, and Sparkle updates
//

import AppKit
import OSLog
import Sparkle
import WebKit
import NookWeb

/// Handles application-level lifecycle events and coordinates app termination
///
/// Key responsibilities:
/// - **URL Handling**: Opens external URLs (e.g., from other apps, custom URL schemes)
/// - **Mouse Button Events**: Maps mouse buttons 2/3/4 to command palette, back, and forward
/// - **App Termination**: Coordinates graceful shutdown with data persistence
/// - **Sparkle Updates**: Integrates with Sparkle framework for auto-updates
///
/// The termination flow uses async persistence to avoid MainActor deadlocks:
/// 1. Returns `.terminateLater` immediately
/// 2. Persists tab snapshots atomically
/// 3. Saves SwiftData context
/// 4. Cleans up WKWebView processes
/// 5. Replies with terminate approval
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AppTermination")

    // TEMPORARY: Reference to BrowserManager for coordinating browser operations
    // TODO: Replace with direct access to independent managers (TabsController, etc.)
    weak var browserManager: BrowserManager?

    // Window registry for accessing active window state
    weak var windowRegistry: WindowRegistry?

    // MCP Manager reference for cleanup on termination
    var mcpManager: MCPManager?

    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)
    private var mouseEventMonitor: Any?
    private var wakeObserver: Any?
    private let userDefaults = UserDefaults.standard
    private var pendingURLs: [URL] = []
    


    // MARK: - Sparkle Updates

    /// Sparkle updater controller for automatic app updates
    lazy var updaterController: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupURLEventHandling()
        setupMouseButtonHandling()
        setupSleepWakeHandling()
        let didFinishOnboarding = userDefaults.bool(forKey: "settings.didFinishOnboarding")

        if let window = NSApplication.shared.windows.first {
            // Always hide titlebar text immediately to prevent flash during transitions
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar?.isVisible = false

            if !didFinishOnboarding {
                window.setContentSize(NSSize(width: 1200, height: 720))
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.hideOtherApplications(nil)
            }
        }
    }

    /// Observes system wake notifications and resets crash counters on all tabs.
    ///
    /// When the system wakes from sleep, launchservicesd and other XPC services need
    /// a few seconds to fully restart. During this window, new WebContent processes crash
    /// immediately with XPC_ERROR_CONNECTION_INVALID. We reset crash counters on wake so
    /// the exponential backoff in webViewWebContentProcessDidTerminate starts fresh and
    /// the delayed reload eventually succeeds once XPC services are stable.
    private func setupSleepWakeHandling() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
    }

    private func handleSystemWake() {
        AppDelegate.log.info("System woke from sleep — resetting web process crash counters")
        // Reset crash counters so tabs get fresh backoff windows after wake.
        // Tabs that were mid-crash-loop before sleep will retry with a clean slate.
        // Called on the main queue (per NSWorkspace notification delivery), so MainActor access is safe.
        MainActor.assumeIsolated {
            guard let manager = browserManager else { return }
            for session in manager.tabs.sessions {
                session.webProcessCrashCount = 0
                session.lastWebProcessCrashDate = .distantPast
            }
        }
    }

    /// Registers handler for external URL events (e.g., clicking links from other apps)
    private func setupURLEventHandling() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: urlEventClass,
            andEventID: urlEventID
        )
    }

    /// Sets up global mouse button event monitoring for extra physical mouse buttons
    ///
    /// Many mice have extra buttons beyond left/right click. This maps them to browser actions:
    /// - **Button 2** (middle click/scroll wheel button): resets a hovered pinned tab to its
    ///   URL, closes a hovered sidebar tab, is left to the page when it lands on web content,
    ///   and otherwise opens the command palette
    /// - **Button 3** (typically a side button labeled "Back"): Navigate back in history
    /// - **Button 4** (typically a side button labeled "Forward"): Navigate forward in history
    ///
    /// This is common in browsers - side buttons on gaming/office mice are often used for navigation.
    private func setupMouseButtonHandling() {
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) {
            [weak self] event in
            guard let self = self,
                  let manager = self.browserManager,
                  let registry = self.windowRegistry else { return event }

            // Mouse events are delivered on the main thread, so we can safely assume main actor isolation
            MainActor.assumeIsolated {
                switch event.buttonNumber {
                case 2:  // Middle mouse button
                    if let hoveredId = manager.hoveredPinnedTabId, manager.tabs.item(hoveredId)?.url != nil {
                        manager.tabs.resetToHome(hoveredId)
                    } else if let hoveredId = registry.windows.values
                        .first(where: { $0.window === event.window })?.hoveredItemID {
                        // Middle click closes a sidebar tab, the same way Cmd+W does: a
                        // pinned tab or favorite keeps its place, a regular tab goes to
                        // the reopen history.
                        manager.tabs.close(hoveredId)
                    } else if Self.isOverWebContent(event) {
                        // The page's own auxclick handler opens the link, if there is one.
                        // Claiming the click here would open the palette on top of it.
                        break
                    } else {
                        registry.activeWindow?.commandPalette?.open()
                    }
                case 3:  // Back button
                    guard
                        let windowState = registry.activeWindow,
                        let itemID = windowState.selectedItemID,
                        let webView = manager.getWebView(for: itemID, in: windowState.id)
                    else {
                        return
                    }
                    webView.goBack()
                case 4:  // Forward button
                    guard
                        let windowState = registry.activeWindow,
                        let itemID = windowState.selectedItemID,
                        let webView = manager.getWebView(for: itemID, in: windowState.id)
                    else {
                        return
                    }
                    webView.goForward()
                default:
                    break
                }
            }
            return event
        }
    }

    /// Whether a mouse event landed inside page content rather than Nook's own chrome.
    /// Used to leave middle clicks over a page to the page's link handler.
    private static func isOverWebContent(_ event: NSEvent) -> Bool {
        guard let contentView = event.window?.contentView else { return false }
        var view = contentView.hitTest(event.locationInWindow)
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }

    /// Handles URLs opened from external sources (e.g., Finder, other apps)
    func application(_ application: NSApplication, open urls: [URL]) {
        // Same guard as handleGetURLEvent, plus file: for documents opened from Finder.
        urls.filter { ["http", "https", "file"].contains($0.scheme?.lowercased() ?? "") }
            .forEach { handleIncoming(url: $0) }
    }

    // MARK: - Application Termination

    /// Saves tab state and SwiftData synchronously, then lets the app quit.
    ///
    /// Every quit path (Cmd+Q with or without the warning, Dock, logout, restart) comes
    /// through here, so this is the one place that guarantees the final save. Pages are not
    /// closed first: the WebContent processes exit with the app anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let start = CFAbsoluteTimeGetCurrent()
        if let manager = browserManager {
            manager.tabs.flushSync()
            do {
                try manager.modelContext.save()
            } catch {
                AppDelegate.log.error("Context save at quit failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            do {
                try Persistence.shared.container.mainContext.save()
            } catch {
                AppDelegate.log.error("Fallback save without BrowserManager failed: \(String(describing: error), privacy: .public)")
            }
        }
        AppDelegate.log.info("Quit save finished in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start))s")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Saving happens in applicationShouldTerminate; this only stops child processes.
        AppDelegate.log.info("applicationWillTerminate called")

        // Stop MCP child processes synchronously (blocking up to 5 seconds)
        mcpManager?.stopAllSync()
    }

    // MARK: - External URL Handling

    /// Handles URL events from AppleScript/AppleEvents
    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let stringValue = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: stringValue)
        else {
            return
        }

        // Security: Only allow http/https URLs from external automation
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        handleIncoming(url: url)
    }

    /// Routes incoming external URLs to the browser manager
    ///
    /// If the browser manager isn't ready yet (cold launch via URL click),
    /// queues the URL and drains it once `browserManager` is set.
    private func handleIncoming(url: URL) {
        guard let manager = browserManager else {
            AppDelegate.log.info("Queuing URL for deferred open: \(url.host ?? "", privacy: .public)")
            pendingURLs.append(url)
            return
        }
        Task { @MainActor in
            // Air Traffic Control — route to designated space if a rule matches
            if manager.siteRoutingManager.applyRoute(url: url, from: nil) {
                return
            }
            manager.presentExternalURL(url)
        }
    }

    /// Opens any URLs that arrived before browserManager was available
    func drainPendingURLs() {
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach { handleIncoming(url: $0) }
    }
}

// MARK: - Sparkle Delegate

extension AppDelegate {
    /// Called when Sparkle finds a valid update
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            browserManager?.handleUpdaterFoundValidUpdate(item)
        }
    }

    /// Called when Sparkle finishes downloading an update
    func updater(_ updater: SPUUpdater, didFinishDownloadingUpdate item: SUAppcastItem) {
        Task { @MainActor in
            browserManager?.handleUpdaterFinishedDownloading(item)
        }
    }

    /// Called when no update is found
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            browserManager?.handleUpdaterDidNotFindUpdate()
        }
    }

    /// Called when user cancels the update download
    func userDidCancelDownload(_ updater: SPUUpdater) {
        Task { @MainActor in
            browserManager?.handleUpdaterAbortedUpdate()
        }
    }

    /// Called when update process encounters an error
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            browserManager?.handleUpdaterAbortedUpdate()
        }
    }

    /// Called when update is ready to install on quit
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationInvocation: @escaping () -> Void
    ) {
        Task { @MainActor in
            browserManager?.handleUpdaterWillInstallOnQuit(item)
        }
    }
}
