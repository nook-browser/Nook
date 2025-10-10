import SwiftUI
import AppKit
import WebKit
import OSLog

struct TabCompositorView: NSViewRepresentable {
    let browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "TabCompositorView")
    
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
        Self.log.debug("[update] Refreshing compositor for window=\(windowState.id, privacy: .public)")

        // Only add the current tab's webView to avoid WKWebView conflicts
        guard let currentTabId = windowState.currentTabId,
              let currentTab = browserManager.tabsForDisplay(in: windowState).first(where: { $0.id == currentTabId }) else {
            Self.log.debug("[update] No current tab resolved (currentTabId=\(windowState.currentTabId?.uuidString ?? "nil", privacy: .public))")
            return
        }

        Self.log.debug("[update] Resolved tab \(currentTabId) name=\(currentTab.name, privacy: .public) unloaded=\(currentTab.isUnloaded)")

        if currentTab.isUnloaded {
            Self.log.debug("[update] Tab unloaded; invoking loadWebViewIfNeeded")
            currentTab.loadWebViewIfNeeded()
        }
        
        // Create a window-specific web view for this tab
        let webView = getOrCreateWebView(for: currentTab, in: windowState.id)
        webView.frame = containerView.bounds
        webView.autoresizingMask = [.width, .height]
        containerView.addSubview(webView)
        webView.isHidden = false
        Self.log.debug("[update] Attached webView=\(String(describing: webView), privacy: .public) frame=\(String(describing: webView.frame), privacy: .public)")
    }
    
    private func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        // Check if we already have a web view for this tab in this window
        if let existingWebView = browserManager.getWebView(for: tab.id, in: windowId) {
            Self.log.debug("[webview] Reusing existing webView for tab=\(tab.id, privacy: .public) window=\(windowId, privacy: .public)")
            return existingWebView
        }
        
        Self.log.debug("[webview] Creating new webView for tab=\(tab.id, privacy: .public) window=\(windowId, privacy: .public)")
        // Create a new web view for this tab in this window
        return browserManager.createWebView(for: tab.id, in: windowId)
    }
}

// MARK: - Tab Compositor Manager
@MainActor
class TabCompositorManager: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "TabCompositorManager")
    private var unloadTimers: [UUID: Timer] = [:]
    private var lastAccessTimes: [UUID: Date] = [:]
    
    // Default unload timeout (5 minutes)
    var unloadTimeout: TimeInterval = 300
    
    init() {
        // Listen for timeout changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimeoutChange),
            name: .tabUnloadTimeoutChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleTimeoutChange(_ notification: Notification) {
        if let timeout = notification.userInfo?["timeout"] as? TimeInterval {
            setUnloadTimeout(timeout)
        }
    }
    
    func setUnloadTimeout(_ timeout: TimeInterval) {
        self.unloadTimeout = timeout
        // Restart timers with new timeout
        restartAllTimers()
    }
    
    func markTabAccessed(_ tabId: UUID) {
        lastAccessTimes[tabId] = Date()
        restartTimer(for: tabId)
    }
    
    func unloadTab(_ tab: Tab) {
        Self.log.debug("[unload] Scheduling unload for tab=\(tab.id, privacy: .public) name=\(tab.name, privacy: .public)")
        
        // Stop any existing timer
        unloadTimers[tab.id]?.invalidate()
        unloadTimers.removeValue(forKey: tab.id)
        lastAccessTimes.removeValue(forKey: tab.id)
        
        // Unload the webview
        tab.unloadWebView()
    }
    
    func loadTab(_ tab: Tab) {
        Self.log.debug("[load] Ensuring tab=\(tab.id, privacy: .public) name=\(tab.name, privacy: .public) is ready")
        
        // Mark as accessed
        markTabAccessed(tab.id)
        
        // Load the webview if needed
        tab.loadWebViewIfNeeded()
    }
    
    private func restartTimer(for tabId: UUID) {
        // Cancel existing timer
        unloadTimers[tabId]?.invalidate()
        
        // Create new timer
        let timer = Timer.scheduledTimer(withTimeInterval: unloadTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleTabTimeout(tabId)
            }
        }
        unloadTimers[tabId] = timer
    }
    
    private func restartAllTimers() {
        // Cancel all existing timers
        unloadTimers.values.forEach { $0.invalidate() }
        unloadTimers.removeAll()
        
        // Restart timers for all accessed tabs
        for tabId in lastAccessTimes.keys {
            restartTimer(for: tabId)
        }
    }
    
    private func handleTabTimeout(_ tabId: UUID) {
        guard let tab = findTab(by: tabId) else { return }
        
        // Don't unload if it's the current tab
        if tab.id == tabId && tab.isCurrentTab {
            // Restart timer for current tab
            restartTimer(for: tabId)
            return
        }
        
        // Don't unload if tab has playing media
        if tab.hasPlayingVideo || tab.hasPlayingAudio || tab.hasAudioContent {
            // Restart timer for tabs with media
            restartTimer(for: tabId)
            return
        }
        
        // Unload the tab
        unloadTab(tab)
    }
    
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
        guard let browserManager = browserManager else { return }
        Self.log.debug("[visibility] Global refresh currentTabId=\(currentTabId?.uuidString ?? "nil", privacy: .public)")
        for (windowId, _) in browserManager.compositorContainers() {
            guard let windowState = browserManager.windowStates[windowId] else { continue }
            Self.log.debug("[visibility] Trigger refresh for window=\(windowId, privacy: .public) compositorVersionBefore=\(windowState.compositorVersion)")
            browserManager.refreshCompositor(for: windowState)
        }
    }

    /// Update tab visibility for a specific window
    func updateTabVisibility(for windowState: BrowserWindowState) {
        Self.log.debug("[visibility] Window-specific refresh window=\(windowState.id, privacy: .public) currentTab=\(windowState.currentTabId?.uuidString ?? "nil", privacy: .public)")
        browserManager?.refreshCompositor(for: windowState)
    }
    
    // MARK: - Dependencies
    weak var browserManager: BrowserManager?
}
