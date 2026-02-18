//
//  WebViewCoordinator.swift
//  Nook
//
//  Manages WebView instances across multiple windows
//

import Foundation
import AppKit
import WebKit

@MainActor
@Observable
class WebViewCoordinator {
    /// Window-specific web views: tabId -> windowId -> WKWebView
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]

    /// Prevent recursive sync calls
    private var isSyncingTab: Set<UUID> = []

    /// Weak wrapper for NSView references stored per window
    private struct WeakNSView { weak var view: NSView? }

    /// Container views per window so the compositor can manage multiple windows safely
    private var compositorContainerViews: [UUID: WeakNSView] = [:]

    // MARK: - Compositor Container Management

    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        if let view {
            compositorContainerViews[windowId] = WeakNSView(view: view)
        } else {
            compositorContainerViews.removeValue(forKey: windowId)
        }
    }

    func compositorContainerView(for windowId: UUID) -> NSView? {
        if let view = compositorContainerViews[windowId]?.view {
            return view
        }
        compositorContainerViews.removeValue(forKey: windowId)
        return nil
    }

    func removeCompositorContainerView(for windowId: UUID) {
        compositorContainerViews.removeValue(forKey: windowId)
    }

    func compositorContainers() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleIdentifiers: [UUID] = []
        for (windowId, entry) in compositorContainerViews {
            if let view = entry.view {
                result.append((windowId, view))
            } else {
                staleIdentifiers.append(windowId)
            }
        }
        for id in staleIdentifiers {
            compositorContainerViews.removeValue(forKey: id)
        }
        return result
    }

    // MARK: - WebView Pool Management

    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        let webView = webViewsByTabAndWindow[tabId]?[windowId]
        if let wv = webView {
            print("🔍 [MEMDEBUG] WebViewCoordinator.getWebView() FOUND existing - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(wv).toOpaque())")
        } else {
            print("🔍 [MEMDEBUG] WebViewCoordinator.getWebView() NOT FOUND - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8))")
        }
        return webView
    }

    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.values)
    }

    func setWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        if webViewsByTabAndWindow[tabId] == nil {
            webViewsByTabAndWindow[tabId] = [:]
        }
        webViewsByTabAndWindow[tabId]?[windowId] = webView
    }

    // MARK: - Smart WebView Assignment (Memory Optimization)
    
    /// Gets or creates a WebView for the specified tab and window.
    /// Implements smart assignment to prevent duplicate WebViews:
    /// - If no window is displaying this tab yet, creates a "primary" WebView
    /// - If another window is already displaying this tab, creates a "clone" WebView
    /// - Returns existing WebView if this window already has one
    func getOrCreateWebView(for tab: Tab, in windowId: UUID, tabManager: TabManager) -> WKWebView {
        let tabId = tab.id
        
        print("🔍 [MEMDEBUG] WebViewCoordinator.getOrCreateWebView() - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8))")
        
        // Check if this window already has a WebView for this tab
        if let existing = getWebView(for: tabId, in: windowId) {
            print("🔍 [MEMDEBUG]   -> Returning EXISTING WebView for this window: \(Unmanaged.passUnretained(existing).toOpaque())")
            return existing
        }
        
        // Check if another window already has this tab displayed
        let allWindowsForTab = webViewsByTabAndWindow[tabId] ?? [:]
        let otherWindows = allWindowsForTab.filter { $0.key != windowId }
        
        print("🔍 [MEMDEBUG]   Tab currently displayed in \(allWindowsForTab.count) window(s), other windows: \(otherWindows.count)")
        
        if otherWindows.isEmpty {
            // This is the FIRST window to display this tab
            // Create the "primary" WebView and assign it to this tab
            print("🔍 [MEMDEBUG]   -> No other windows, creating PRIMARY WebView")
            let primaryWebView = createPrimaryWebView(for: tab, in: windowId)
            
            // Assign this WebView as the tab's primary
            tab.assignWebViewToWindow(primaryWebView, windowId: windowId)
            
            return primaryWebView
        } else {
            // Another window is already displaying this tab
            // Create a "clone" WebView for this window
            print("🔍 [MEMDEBUG]   -> Other window(s) exist, creating CLONE WebView")
            let cloneWebView = createCloneWebView(for: tab, in: windowId, primaryWindowId: otherWindows.first!.key)
            
            return cloneWebView
        }
    }
    
    /// Creates the "primary" WebView - the first WebView for a tab
    /// This WebView is owned by the tab and is the "source of truth"
    private func createPrimaryWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        let tabId = tab.id
        
        print("🔍 [MEMDEBUG] Creating PRIMARY WebView - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8))")
        
        // Use the standard creation logic but mark it as primary
        let webView = createWebViewInternal(for: tab, in: windowId, isPrimary: true)
        
        print("🔍 [MEMDEBUG]   -> Primary WebView created: \(Unmanaged.passUnretained(webView).toOpaque())")
        return webView
    }
    
    /// Creates a "clone" WebView - additional WebViews for multi-window display
    /// These share the configuration but are separate instances
    private func createCloneWebView(for tab: Tab, in windowId: UUID, primaryWindowId: UUID) -> WKWebView {
        let tabId = tab.id
        
        print("🔍 [MEMDEBUG] Creating CLONE WebView - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), PrimaryWindow: \(primaryWindowId.uuidString.prefix(8))")
        
        // Get the primary WebView to copy configuration
        let primaryWebView = getWebView(for: tabId, in: primaryWindowId)
        
        // Create clone with shared configuration
        let webView = createWebViewInternal(for: tab, in: windowId, isPrimary: false, copyFrom: primaryWebView)
        
        print("🔍 [MEMDEBUG]   -> Clone WebView created: \(Unmanaged.passUnretained(webView).toOpaque())")
        return webView
    }
    
    /// Internal method to create a WebView with proper configuration
    private func createWebViewInternal(for tab: Tab, in windowId: UUID, isPrimary: Bool, copyFrom: WKWebView? = nil) -> WKWebView {
        let tabId = tab.id
        
        // Derive config from shared config or existing webview to preserve
        // process pool + extension controller (fresh configs break content script injection)
        let configuration: WKWebViewConfiguration
        if let sourceWebView = copyFrom ?? tab.existingWebView {
            // .configuration returns a copy — preserves process pool, extension controller, etc.
            configuration = sourceWebView.configuration
        } else {
            let resolvedProfile = tab.resolveProfile()
            if let profile = resolvedProfile {
                configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(for: profile)
            } else {
                configuration = BrowserConfiguration.shared.webViewConfiguration.copy() as! WKWebViewConfiguration
            }
        }
        // Fresh user content controller per webview to avoid cross-tab handler conflicts
        configuration.userContentController = WKUserContentController()
        
        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.setValue(false, forKey: "drawsBackground")
        newWebView.owningTab = tab
        newWebView.contextMenuBridge = WebContextMenuBridge(tab: tab, configuration: configuration)
        
        newWebView.configuration.userContentController.add(tab, name: "linkHover")
        newWebView.configuration.userContentController.add(tab, name: "commandHover")
        newWebView.configuration.userContentController.add(tab, name: "commandClick")
        newWebView.configuration.userContentController.add(tab, name: "pipStateChange")
        newWebView.configuration.userContentController.add(tab, name: "mediaStateChange_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "backgroundColor_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "historyStateDidChange")
        newWebView.configuration.userContentController.add(tab, name: "NookIdentity")
        newWebView.configuration.userContentController.add(tab, name: "nookShortcutDetect")
        
        tab.setupThemeColorObserver(for: newWebView)
        
        // Only load URL if this is the primary or if we're creating a clone
        // For clones, we sync the URL via syncTab later
        if let url = URL(string: tab.url.absoluteString) {
            newWebView.load(URLRequest(url: url))
        }
        newWebView.isMuted = tab.isAudioMuted
        
        setWebView(newWebView, for: tabId, in: windowId)
        
        let typeStr = isPrimary ? "PRIMARY" : "CLONE"
        print("🔍 [MEMDEBUG] WebViewCoordinator CREATED \(typeStr) WebView - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(newWebView).toOpaque()), DataStore: \(configuration.websiteDataStore.identifier?.uuidString.prefix(8) ?? "default")")
        
        // Log all WebViews now tracked for this tab
        let allWebViewsForTab = getAllWebViews(for: tabId)
        print("🔍 [MEMDEBUG]   Total WebViews for tab \(tabId.uuidString.prefix(8)): \(allWebViewsForTab.count)")
        for (index, wv) in allWebViewsForTab.enumerated() {
            print("🔍 [MEMDEBUG]     [\(index)] WebView: \(Unmanaged.passUnretained(wv).toOpaque())")
        }
        
        return newWebView
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        for (windowId, entry) in compositorContainerViews {
            guard let container = entry.view else {
                compositorContainerViews.removeValue(forKey: windowId)
                continue
            }
            for subview in container.subviews where subview === webView {
                subview.removeFromSuperview()
            }
        }
    }

    func removeAllWebViews(for tab: Tab) {
        guard let entries = webViewsByTabAndWindow.removeValue(forKey: tab.id) else { return }
        for (_, webView) in entries {
            tab.cleanupCloneWebView(webView)
            removeWebViewFromContainers(webView)
        }
    }

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let webViewsToCleanup = webViewsByTabAndWindow.compactMap {
            (tabId, windowWebViews) -> (UUID, WKWebView)? in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (tabId, webView)
        }

        print("🧹 [WebViewCoordinator] Cleaning up \(webViewsToCleanup.count) WebViews for window \(windowId)")

        for (tabId, webView) in webViewsToCleanup {
            // Use comprehensive cleanup from Tab class
            if let tab = tabManager.allTabs().first(where: { $0.id == tabId }) {
                tab.cleanupCloneWebView(webView)
            } else {
                // Fallback cleanup if tab is not found
                performFallbackWebViewCleanup(webView, tabId: tabId)
            }

            // Remove from containers
            removeWebViewFromContainers(webView)

            // Remove from tracking
            webViewsByTabAndWindow[tabId]?.removeValue(forKey: windowId)
            if webViewsByTabAndWindow[tabId]?.isEmpty == true {
                webViewsByTabAndWindow.removeValue(forKey: tabId)
            }

            print("✅ [WebViewCoordinator] Cleaned up WebView for tab \(tabId) in window \(windowId)")
        }
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        print("🧹 [WebViewCoordinator] Starting comprehensive cleanup for ALL WebViews")

        let totalWebViews = webViewsByTabAndWindow.values.flatMap { $0.values }.count
        print("🧹 [WebViewCoordinator] Cleaning up \(totalWebViews) WebViews across all windows")

        // Clean up all WebViews for all tabs in all windows
        for (tabId, windowWebViews) in webViewsByTabAndWindow {
            for (windowId, webView) in windowWebViews {
                // Use comprehensive cleanup from Tab class
                if let tab = tabManager.allTabs().first(where: { $0.id == tabId }) {
                    tab.cleanupCloneWebView(webView)
                } else {
                    // Fallback cleanup if tab is not found
                    performFallbackWebViewCleanup(webView, tabId: tabId)
                }

                // Remove from containers
                removeWebViewFromContainers(webView)

                print("✅ [WebViewCoordinator] Cleaned up WebView for tab \(tabId) in window \(windowId)")
            }
        }

        // Clear all tracking
        webViewsByTabAndWindow.removeAll()
        compositorContainerViews.removeAll()

        print("✅ [WebViewCoordinator] Completed comprehensive cleanup for ALL WebViews")
    }

    // MARK: - WebView Creation & Cross-Window Sync

    /// Create a new web view for a specific tab in a specific window
    func createWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        let tabId = tab.id
        
        print("🔍 [MEMDEBUG] WebViewCoordinator.createWebView() START - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), TabName: \(tab.name)")
        print("🔍 [MEMDEBUG]   tab.existingWebView exists: \(tab.existingWebView != nil), tab.webView exists: \(tab.webView != nil)")
        if let tabWebView = tab.existingWebView {
            print("🔍 [MEMDEBUG]   Tab's existingWebView: \(Unmanaged.passUnretained(tabWebView).toOpaque())")
        }

        // Derive config from shared config or existing webview to preserve
        // process pool + extension controller (fresh configs break content script injection)
        let configuration: WKWebViewConfiguration
        if let originalWebView = tab.existingWebView {
            configuration = originalWebView.configuration
        } else {
            let resolvedProfile = tab.resolveProfile()
            if let profile = resolvedProfile {
                configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(for: profile)
            } else {
                configuration = BrowserConfiguration.shared.webViewConfiguration.copy() as! WKWebViewConfiguration
            }
        }
        configuration.userContentController = WKUserContentController()

        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.setValue(true, forKey: "drawsBackground")
        newWebView.owningTab = tab
        newWebView.contextMenuBridge = WebContextMenuBridge(tab: tab, configuration: configuration)

        newWebView.configuration.userContentController.add(tab, name: "linkHover")
        newWebView.configuration.userContentController.add(tab, name: "commandHover")
        newWebView.configuration.userContentController.add(tab, name: "commandClick")
        newWebView.configuration.userContentController.add(tab, name: "pipStateChange")
        newWebView.configuration.userContentController.add(tab, name: "mediaStateChange_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "backgroundColor_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "historyStateDidChange")
        newWebView.configuration.userContentController.add(tab, name: "NookIdentity")

        tab.setupThemeColorObserver(for: newWebView)

        if let url = URL(string: tab.url.absoluteString) {
            newWebView.load(URLRequest(url: url))
        }
        newWebView.isMuted = tab.isAudioMuted

        setWebView(newWebView, for: tabId, in: windowId)

        print("🔍 [MEMDEBUG] WebViewCoordinator CREATED WINDOW-SPECIFIC WebView - Tab: \(tabId.uuidString.prefix(8)), Window: \(windowId.uuidString.prefix(8)), WebView: \(Unmanaged.passUnretained(newWebView).toOpaque()), DataStore: \(configuration.websiteDataStore.identifier?.uuidString.prefix(8) ?? "default")")
        
        // Log all WebViews now tracked for this tab
        let allWebViewsForTab = getAllWebViews(for: tabId)
        print("🔍 [MEMDEBUG]   Total WebViews for tab \(tabId.uuidString.prefix(8)): \(allWebViewsForTab.count)")
        for (index, wv) in allWebViewsForTab.enumerated() {
            print("🔍 [MEMDEBUG]     [\(index)] WebView: \(Unmanaged.passUnretained(wv).toOpaque())")
        }
        
        return newWebView
    }

    // MARK: - Private Helpers

    private func performFallbackWebViewCleanup(_ webView: WKWebView, tabId: UUID) {
        print("🧹 [WebViewCoordinator] Performing fallback WebView cleanup for tab: \(tabId)")

        // Stop loading
        webView.stopLoading()

        // Remove all message handlers
        let controller = webView.configuration.userContentController
        let allMessageHandlers = [
            "linkHover",
            "commandHover",
            "commandClick",
            "pipStateChange",
            "mediaStateChange_\(tabId.uuidString)",
            "backgroundColor_\(tabId.uuidString)",
            "historyStateDidChange",
            "NookIdentity",
            "nookShortcutDetect",
        ]

        for handlerName in allMessageHandlers {
            controller.removeScriptMessageHandler(forName: handlerName)
        }

        // Clear delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // Remove from view hierarchy
        webView.removeFromSuperview()

        print("✅ [WebViewCoordinator] Fallback WebView cleanup completed for tab: \(tabId)")
    }

    // MARK: - Cross-Window Sync

    /// Sync a tab's URL across all windows displaying it
    func syncTab(_ tabId: UUID, to url: URL) {
        // Prevent recursive sync calls
        guard !isSyncingTab.contains(tabId) else {
            print("🪟 [WebViewCoordinator] Skipping recursive sync for tab \(tabId)")
            return
        }

        isSyncingTab.insert(tabId)
        defer { isSyncingTab.remove(tabId) }

        // Get all web views for this tab across all windows
        let allWebViews = getAllWebViews(for: tabId)

        for webView in allWebViews {
            // Sync the URL if it's different
            if webView.url != url {
                print("🔄 [WebViewCoordinator] Syncing tab \(tabId) to URL: \(url)")
                webView.load(URLRequest(url: url))
            }
        }
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tabId: UUID) {
        let allWebViews = getAllWebViews(for: tabId)
        for webView in allWebViews {
            print("🔄 [WebViewCoordinator] Reloading tab \(tabId) across windows")
            webView.reload()
        }
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID, excludingWindow originatingWindowId: UUID?) {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return }

        for (windowId, webView) in windowWebViews {
            // Simple: just set all webviews to the same mute state
            webView.isMuted = muted
            print("🔇 [WebViewCoordinator] Window \(windowId): muted=\(muted)")
        }
    }
}
