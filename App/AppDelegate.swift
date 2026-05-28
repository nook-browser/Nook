//
//  AppDelegate.swift
//  Nook
//
//  Application lifecycle delegate handling app termination, URL events, and Sparkle updates
//

import AppKit
import OSLog
import Sparkle

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
    // TODO: Replace with direct access to independent managers (TabManager, etc.)
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
            for tab in manager.tabManager.allTabs() {
                tab.webProcessCrashCount = 0
                tab.lastWebProcessCrashDate = .distantPast
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
    /// - **Button 2** (middle click/scroll wheel button): Open command palette
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
                    if let hoveredId = manager.hoveredPinnedTabId,
                       let tab = manager.tabManager.allTabs().first(where: { $0.id == hoveredId }),
                       tab.pinnedURL != nil {
                        tab.resetToPinnedURL()
                    } else {
                        registry.activeWindow?.commandPalette?.open()
                    }
                case 3:  // Back button
                    guard
                        let windowState = registry.activeWindow,
                        let currentTab = manager.currentTab(for: windowState),
                        let webView = manager.getWebView(for: currentTab.id, in: windowState.id)
                    else {
                        return
                    }
                    webView.goBack()
                case 4:  // Forward button
                    guard
                        let windowState = registry.activeWindow,
                        let currentTab = manager.currentTab(for: windowState),
                        let webView = manager.getWebView(for: currentTab.id, in: windowState.id)
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

    /// Handles URLs opened from external sources (e.g., Finder, other apps)
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }

    // MARK: - Application Termination

    /// Initiates async termination process to avoid MainActor deadlocks
    ///
    /// Returns `.terminateLater` immediately, then performs async cleanup:
    /// 1. Phase 1: Atomic snapshot persistence (non-blocking)
    /// 2. Phase 2: SwiftData context save
    /// 3. Phase 3: WKWebView process cleanup
    ///
    /// - Returns: Always returns `.terminateLater` to handle termination asynchronously
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // When "warn before quitting" is disabled, terminate(nil) is called directly
        // from the SwiftUI CommandGroup button action. Returning .terminateLater in that
        // context deadlocks because the async Task can't execute during the termination
        // run loop mode. Since the user opted out of the warning, just quit immediately.
        let askBeforeQuit = userDefaults.bool(forKey: "settings.askBeforeQuit")
        if !askBeforeQuit {
            return .terminateNow
        }

        handleTermination(sender: sender, shouldTerminate: true)
        return .terminateLater
    }

    /// Performs async termination tasks on MainActor
    ///
    /// This method executes the three-phase shutdown process:
    /// - **Phase 1**: Atomic tab snapshot persistence
    /// - **Phase 2**: SwiftData context save
    /// - **Phase 3**: WebView cleanup
    ///
    /// Timing is logged for each phase to monitor performance.
    private func handleTermination(sender: NSApplication, shouldTerminate: Bool) {
        AppDelegate.log.info(
            "applicationShouldTerminate: returning terminateLater and starting async persistence")

        Task { @MainActor in
            guard shouldTerminate else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }

            // Minimal fallback if BrowserManager is unavailable
            guard let manager = browserManager else {
                // Attempt a best-effort save via shared persistence container
                do {
                    let ctx = Persistence.shared.container.mainContext
                    try ctx.save()
                    AppDelegate.log.info("Fallback save without BrowserManager succeeded")
                } catch {
                    AppDelegate.log.error(
                        "Fallback save without BrowserManager failed: \(String(describing: error))"
                    )
                }
                sender.reply(toApplicationShouldTerminate: true)
                return
            }

            let overallStart = CFAbsoluteTimeGetCurrent()
            AppDelegate.log.info("Termination task started on MainActor")

            // Phase 1: Atomic snapshot persistence (non-throwing Bool)
            let persistStart = CFAbsoluteTimeGetCurrent()
            let atomic: Bool = await manager.tabManager.persistSnapshotAwaitingResult()
            let pdt = CFAbsoluteTimeGetCurrent() - persistStart
            AppDelegate.log.info(
                "Atomic persistence \(atomic ? "succeeded" : "did not run; fallback used") in \(String(format: "%.3f", pdt))s"
            )

            // Phase 2: Ensure SwiftData changes are committed
            let contextSaveStart = CFAbsoluteTimeGetCurrent()
            do {
                try manager.modelContext.save()
                let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                AppDelegate.log.info("Context save completed in \(String(format: "%.3f", sdt))s")
            } catch {
                let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                AppDelegate.log.error(
                    "Context save failed in \(String(format: "%.3f", sdt))s: \(String(describing: error))"
                )
            }

            // Phase 3: Graceful cleanup
            manager.cleanupAllTabs()
            AppDelegate.log.info("Cleanup completed; WKWebView processes terminated")

            let total = CFAbsoluteTimeGetCurrent() - overallStart
            AppDelegate.log.info(
                "Termination task finished in \(String(format: "%.3f", total))s; replying to terminate"
            )
            sender.reply(toApplicationShouldTerminate: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Keep minimal to avoid MainActor deadlocks; main work happens in applicationShouldTerminate
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
            AppDelegate.log.info("Queuing URL for deferred open: \(url.absoluteString, privacy: .public)")
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
