import SwiftUI
import AppKit
import WebKit

struct TabCompositorView: NSViewRepresentable {
    let browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update the compositor when tabs change or compositor version changes
        updateCompositor(nsView)
    }
    
    private func updateCompositor(_ containerView: NSView) {
        // Remove all existing webview subviews
        containerView.subviews.forEach { $0.removeFromSuperview() }

        // Only add the current tab's webView to avoid WKWebView conflicts
        guard let currentTabId = windowState.currentTabId,
              let currentTab = browserManager.tabsForDisplay(in: windowState).first(where: { $0.id == currentTabId }),
              !currentTab.isUnloaded else {
            return
        }
        
        // Create a window-specific web view for this tab
        let webView = getOrCreateWebView(for: currentTab, in: windowState.id)
        webView.frame = containerView.bounds
        webView.autoresizingMask = [.width, .height]
        containerView.addSubview(webView)
        webView.isHidden = false
    }
    
    private func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        // Check if we already have a web view for this tab in this window
        if let existingWebView = browserManager.getWebView(for: tab.id, in: windowId) {
            return existingWebView
        }
        
        // Create a new web view for this tab in this window
        return browserManager.createWebView(for: tab.id, in: windowId)
    }
}

// MARK: - Tab Compositor Manager
@MainActor
class TabCompositorManager: ObservableObject {
    private var unloadTimers: [UUID: Timer] = [:]
    private var lastAccessTimes: [UUID: Date] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var appResignObserver: Any?
    private var lastMemoryPressureTime: Date?
    private var budgetRetryTimer: Timer?

    var allowsBackgroundWarming: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled
            && (lastMemoryPressureTime.map { Date().timeIntervalSince($0) >= 60 } ?? true)
    }

    private(set) var mode: TabManagementMode = .standard

    init() {
        setupMemoryPressureMonitoring()
    }

    deinit {
        memoryPressureSource?.cancel()
        budgetRetryTimer?.invalidate()
        unloadTimers.values.forEach { $0.invalidate() }
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Mode Configuration

    func setMode(_ newMode: TabManagementMode) {
        self.mode = newMode

        // Restart timers with new timeout
        restartAllTimers()

        // Set up or tear down background monitoring
        if newMode.unloadsOnBackground {
            setupBackgroundMonitoring()
        } else {
            teardownBackgroundMonitoring()
        }

        // Enforce max loaded tabs if switching to a mode with a limit
        enforceMaxLoadedTabs()
    }

    // MARK: - Tab Access & Loading

    func markTabAccessed(_ tabId: UUID) {
        lastAccessTimes[tabId] = Date()
        // The compositor marks the current tab on every SwiftUI update (hover, resize).
        // A timer rescheduled within the last minute is close enough; handleTabTimeout
        // re-arms for any remaining time.
        if let timer = unloadTimers[tabId], timer.isValid,
           timer.fireDate.timeIntervalSinceNow > mode.unloadTimeout - 60 {
            return
        }
        restartTimer(for: tabId)
    }

    func unloadTab(_ tab: Tab) {
        unloadTimers[tab.id]?.invalidate()
        unloadTimers.removeValue(forKey: tab.id)
        lastAccessTimes.removeValue(forKey: tab.id)

        tab.unloadWebView()
    }

    func loadTab(_ tab: Tab) {
        markTabAccessed(tab.id)
        tab.loadWebViewIfNeeded()

        // After loading, enforce max loaded tabs for power saving mode
        if mode.maxLoadedTabs != nil {
            enforceMaxLoadedTabs()
        }
    }

    // MARK: - Timer Management

    private func restartTimer(for tabId: UUID, after interval: TimeInterval? = nil) {
        unloadTimers[tabId]?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: interval ?? mode.unloadTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleTabTimeout(tabId)
            }
        }
        unloadTimers[tabId] = timer
    }

    private func restartAllTimers() {
        unloadTimers.values.forEach { $0.invalidate() }
        unloadTimers.removeAll()

        for tabId in lastAccessTimes.keys {
            restartTimer(for: tabId)
        }
    }

    private func handleTabTimeout(_ tabId: UUID) {
        unloadTimers.removeValue(forKey: tabId)
        // Closed or already unloaded: nothing to time out until the tab is accessed again.
        guard let tab = findTab(by: tabId), !tab.isUnloaded else {
            lastAccessTimes.removeValue(forKey: tabId)
            return
        }
        // Pinned tabs are never unloaded automatically, so re-arming would only wake the app.
        if tab.isPinned || tab.isSpacePinned { return }

        if let lastAccess = lastAccessTimes[tabId] {
            let remaining = mode.unloadTimeout - Date().timeIntervalSince(lastAccess)
            if remaining > 1 {
                restartTimer(for: tabId, after: remaining)
                return
            }
        }

        if !canUnloadInactiveTab(tab) {
            restartTimer(for: tabId)
            return
        }

        // Route through TabManager to preserve pinned-tab guard
        browserManager?.tabManager.unloadTab(tab)
    }

    // MARK: - Tab Importance & Exemptions

    /// Shared eligibility for automatic eviction and bulk inactive-tab unloading.
    /// Explicitly unloading an individual tab deliberately bypasses this policy.
    func canUnloadInactiveTab(_ tab: Tab) -> Bool {
        if tab.isUnloaded || isCurrentTabInAnyWindow(tab) { return false }
        if tab.hasPiPActive || tab.hasPlayingVideo || tab.hasPlayingAudio || tab.hasAudioContent { return false }
        var views = browserManager?.webViewCoordinator?.getAllWebViews(for: tab.id) ?? []
        if let primary = tab.existingWebView { views.append(primary) }
        if views.contains(where: { $0.cameraCaptureState != .none || $0.microphoneCaptureState != .none }) {
            return false
        }
        if tab.isPinned || tab.isSpacePinned { return false }
        return true
    }

    private func isCurrentTabInAnyWindow(_ tab: Tab) -> Bool {
        guard let registry = browserManager?.windowRegistry, !registry.allWindows.isEmpty else {
            return tab.isCurrentTab
        }
        return registry.allWindows.contains { window in
            if window.currentTabId == tab.id { return true }
            guard let split = browserManager?.splitManager.getSplitState(for: window.id),
                  split.isSplit,
                  window.currentTabId == split.leftTabId || window.currentTabId == split.rightTabId else {
                return false
            }
            return tab.id == split.leftTabId || tab.id == split.rightTabId
        }
    }

    /// Scores tab importance for deciding unload order. Higher = more important to keep.
    private func tabImportanceScore(_ tab: Tab) -> Int {
        var score = 0
        if isCurrentTabInAnyWindow(tab) { score += 1000 }
        if tab.hasPlayingVideo || tab.hasPlayingAudio || tab.hasAudioContent { score += 500 }
        if tab.isPinned || tab.isSpacePinned { score += 200 }
        // Recency bonus: up to 100 points for recently accessed tabs
        if let lastAccess = lastAccessTimes[tab.id] {
            let minutesAgo = Date().timeIntervalSince(lastAccess) / 60
            score += max(0, 100 - Int(minutesAgo))
        }
        return score
    }

    // MARK: - Memory Pressure Monitoring

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {
        // Throttle: don't act on memory pressure more than once per 30 seconds
        let now = Date()
        if let lastTime = lastMemoryPressureTime, now.timeIntervalSince(lastTime) < 30 {
            return
        }
        lastMemoryPressureTime = now

        guard let browserManager = browserManager else { return }

        let allTabs = browserManager.tabManager.allTabs()
        let loadedNonExempt = allTabs.filter { canUnloadInactiveTab($0) }

        guard !loadedNonExempt.isEmpty else { return }

        // Sort by importance ascending (least important first)
        let sorted = loadedNonExempt.sorted { tabImportanceScore($0) < tabImportanceScore($1) }

        let tabsToUnload: ArraySlice<Tab>
        if let keepCount = mode.memoryPressureKeepCount {
            // Power Saving: unload all but current + keepCount MRU
            let totalLoaded = allTabs.filter { !$0.isUnloaded }.count
            let countToUnload = max(0, totalLoaded - 1 - keepCount) // -1 for current tab
            tabsToUnload = sorted.prefix(countToUnload)
        } else {
            // Standard/Performance: unload a fraction of loaded tabs
            let countToUnload = Int(ceil(Double(sorted.count) * mode.memoryPressureUnloadFraction))
            tabsToUnload = sorted.prefix(countToUnload)
        }

        for tab in tabsToUnload {
            browserManager.tabManager.unloadTab(tab)
        }
    }

    // MARK: - Background Unloading

    private func setupBackgroundMonitoring() {
        teardownBackgroundMonitoring()

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidResignActive()
            }
        }
    }

    private func teardownBackgroundMonitoring() {
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }

    private func handleAppDidResignActive() {
        guard mode.unloadsOnBackground, let browserManager = browserManager else { return }

        for tab in browserManager.tabManager.allTabs() where canUnloadInactiveTab(tab) {
            browserManager.tabManager.unloadTab(tab)
        }
    }

    // MARK: - Max Loaded Tab Enforcement

    private func enforceMaxLoadedTabs() {
        budgetRetryTimer?.invalidate()
        budgetRetryTimer = nil
        guard let maxTabs = mode.maxLoadedTabs, let browserManager = browserManager else { return }

        let allTabs = browserManager.tabManager.allTabs()
        let loadedNonExempt = allTabs.filter { canUnloadInactiveTab($0) }

        // Don't count pinned tabs toward the limit
        let loadedRegular = loadedNonExempt.filter { !$0.isPinned && !$0.isSpacePinned }

        guard loadedRegular.count > maxTabs else { return }

        // Grace period: don't unload tabs accessed within last 30 seconds
        let gracePeriod: TimeInterval = 30
        let now = Date()
        let eligible = loadedRegular.filter { tab in
            guard let lastAccess = lastAccessTimes[tab.id] else { return true }
            return now.timeIntervalSince(lastAccess) > gracePeriod
        }

        // Sort by importance ascending (least important first)
        let sorted = eligible.sorted { tabImportanceScore($0) < tabImportanceScore($1) }
        let countToUnload = loadedRegular.count - maxTabs
        let tabsToUnload = sorted.prefix(max(0, countToUnload))

        for tab in tabsToUnload {
            browserManager.tabManager.unloadTab(tab)
        }

        // A burst can exceed the budget while every tab is inside its grace period.
        // Retry once at the next expiry, rather than waiting for another user action.
        if loadedRegular.count - tabsToUnload.count > maxTabs,
           let nextExpiry = loadedRegular.compactMap({ tab -> Date? in
               guard let accessed = lastAccessTimes[tab.id] else { return nil }
               let expiry = accessed.addingTimeInterval(gracePeriod)
               return expiry > now ? expiry : nil
           }).min() {
            budgetRetryTimer = Timer.scheduledTimer(
                withTimeInterval: max(0.05, nextExpiry.timeIntervalSinceNow), repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.enforceMaxLoadedTabs() }
            }
        }
    }

    // MARK: - Tab Lookup

    private func findTab(by id: UUID) -> Tab? {
        guard let browserManager = browserManager else { return nil }
        return browserManager.tabManager.allTabs().first { $0.id == id }
    }

    private func findTabByWebView(_ webView: WKWebView) -> Tab? {
        guard let browserManager = browserManager else { return nil }
        return browserManager.tabManager.allTabs().first { $0.webView === webView }
    }

    // MARK: - Public Interface

    func updateTabVisibility(currentTabId: UUID?) {
        guard let browserManager = browserManager,
              let coordinator = browserManager.webViewCoordinator else { return }
        for (windowId, _) in coordinator.compositorContainers() {
            guard let windowState = browserManager.windowRegistry?.windows[windowId] else { continue }
            browserManager.refreshCompositor(for: windowState)
        }
    }

    func updateTabVisibility(for windowState: BrowserWindowState) {
        browserManager?.refreshCompositor(for: windowState)
    }

    // MARK: - Dependencies
    weak var browserManager: BrowserManager?
}
