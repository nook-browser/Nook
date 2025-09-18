import SwiftUI
import AppKit
import WebKit

struct TabCompositorView: NSViewRepresentable {
    let browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    
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
        print("🔄 [Compositor] Unloading tab: \(tab.name)")
        
        // Stop any existing timer
        unloadTimers[tab.id]?.invalidate()
        unloadTimers.removeValue(forKey: tab.id)
        lastAccessTimes.removeValue(forKey: tab.id)
        
        // Unload the webview
        tab.unloadWebView()
    }
    
    func loadTab(_ tab: Tab) {
        print("🔄 [Compositor] Loading tab: \(tab.name)")
        
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
        let currentSpacePinned: [Tab] = {
            if let space = browserManager.tabManager.currentSpace {
                return browserManager.tabManager.spacePinnedTabs(for: space.id)
            } else { return [] }
        }()
        let allTabs = browserManager.tabManager.essentialTabs + currentSpacePinned + browserManager.tabManager.tabs
        return allTabs.first { $0.id == id }
    }
    
    private func findTabByWebView(_ webView: WKWebView) -> Tab? {
        guard let browserManager = browserManager else { return nil }
        let currentSpacePinned: [Tab] = {
            if let space = browserManager.tabManager.currentSpace {
                return browserManager.tabManager.spacePinnedTabs(for: space.id)
            } else { return [] }
        }()
        let allTabs = browserManager.tabManager.essentialTabs + currentSpacePinned + browserManager.tabManager.tabs
        return allTabs.first { $0.webView === webView }
    }
    
    // MARK: - Public Interface
    func updateTabVisibility(currentTabId: UUID?) {
        guard let browserManager = browserManager else { return }
        for (windowId, _) in browserManager.compositorContainers() {
            guard let windowState = browserManager.windowStates[windowId] else { continue }
            browserManager.refreshCompositor(for: windowState)
        }
    }
    
    /// Update tab visibility for a specific window
    func updateTabVisibility(for windowState: BrowserWindowState) {
        browserManager?.refreshCompositor(for: windowState)
    }
    
    // MARK: - Dependencies
    weak var browserManager: BrowserManager?
}
