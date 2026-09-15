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
        return webViewsByTabAndWindow[tabId]?[windowId]
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

        // Check if this window already has a WebView for this tab
        if let existing = getWebView(for: tabId, in: windowId) {
            return existing
        }

        // Check if another window already has this tab displayed
        let allWindowsForTab = webViewsByTabAndWindow[tabId] ?? [:]
        let otherWindows = allWindowsForTab.filter { $0.key != windowId }

        if otherWindows.isEmpty {
            // This is the FIRST window to display this tab
            // Create the "primary" WebView and assign it to this tab
            let primaryWebView = createPrimaryWebView(for: tab, in: windowId)

            // Assign this WebView as the tab's primary
            tab.assignWebViewToWindow(primaryWebView, windowId: windowId)

            return primaryWebView
        } else {
            // Another window is already displaying this tab
            // Create a "clone" WebView for this window
            let cloneWebView = createCloneWebView(for: tab, in: windowId, primaryWindowId: otherWindows.first!.key)

            return cloneWebView
        }
    }
    
    /// Creates the "primary" WebView - the first WebView for a tab
    /// This WebView is owned by the tab and is the "source of truth"
    private func createPrimaryWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        // Adopt the tab's fully configured view, including restored navigation and popup state.
        // Selection may already have created it; never start a second navigation for assignment.
        tab.loadWebViewIfNeeded()
        let webView = tab.existingWebView
            ?? createWebViewInternal(for: tab, in: windowId, isPrimary: true)
        setWebView(webView, for: tab.id, in: windowId)
        return webView
    }
    
    /// Creates a "clone" WebView - additional WebViews for multi-window display
    /// These share the configuration but are separate instances
    private func createCloneWebView(for tab: Tab, in windowId: UUID, primaryWindowId: UUID) -> WKWebView {
        let tabId = tab.id

        // Get the primary WebView to copy configuration
        let primaryWebView = getWebView(for: tabId, in: primaryWindowId)

        // Create clone with shared configuration
        return createWebViewInternal(for: tab, in: windowId, isPrimary: false, copyFrom: primaryWebView)
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
                configuration = BrowserConfiguration.shared.webViewConfiguration(for: profile)
            } else {
                configuration = BrowserConfiguration.shared.webViewConfiguration.copy() as! WKWebViewConfiguration
            }
        }
        // Fresh user content controller per webview to avoid cross-tab handler conflicts
        // (preserves shared scripts like extension bridge polyfills)
        configuration.userContentController = BrowserConfiguration.shared.freshUserContentController()

        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.owningTab = tab
        newWebView.contextMenuBridge = WebContextMenuBridge(tab: tab, configuration: configuration)
        // Same handlers, user agent and preferences as the primary: a clone is promoted
        // to primary when its window outlives the primary's window.
        tab.configureTabWebView(newWebView)

        tab.setupThemeColorObserver(for: newWebView)
        tab.setupNavigationStateObservers(for: newWebView)

        Tab.loadPage(tab.url, in: newWebView)
        newWebView.isMuted = tab.isAudioMuted
        
        setWebView(newWebView, for: tabId, in: windowId)

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

        // Build a lookup dictionary once instead of calling allTabs().first(where:) per webview.
        // Tolerate a tab listed in two containers rather than trapping on window close.
        let allTabsMap = Dictionary(tabManager.allTabs().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (tabId, webView) in webViewsToCleanup {
            webViewsByTabAndWindow[tabId]?.removeValue(forKey: windowId)
            if webViewsByTabAndWindow[tabId]?.isEmpty == true {
                webViewsByTabAndWindow.removeValue(forKey: tabId)
            }
            if let tab = allTabsMap[tabId] {
                if tab.existingWebView === webView {
                    if let replacement = webViewsByTabAndWindow[tabId]?.first {
                        tab.assignWebViewToWindow(replacement.value, windowId: replacement.key)
                        tab.cleanupCloneWebView(webView)
                    } else {
                        tab.unloadWebView()
                    }
                } else {
                    tab.cleanupCloneWebView(webView)
                }
            } else {
                performFallbackWebViewCleanup(webView, tabId: tabId)
            }
            removeWebViewFromContainers(webView)
        }
        removeCompositorContainerView(for: windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        let allTabsMap = Dictionary(tabManager.allTabs().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = webViewsByTabAndWindow
        webViewsByTabAndWindow.removeAll()
        for (tabId, windowWebViews) in entries {
            for webView in windowWebViews.values {
                if let tab = allTabsMap[tabId] {
                    tab.cleanupCloneWebView(webView)
                } else {
                    performFallbackWebViewCleanup(webView, tabId: tabId)
                }
            }
        }
        for tab in allTabsMap.values { tab.unloadWebView() }
        compositorContainerViews.removeAll()
    }

    // MARK: - WebView Creation & Cross-Window Sync

    /// Create a new web view for a specific tab in a specific window
    func createWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        if let existing = getWebView(for: tab.id, in: windowId) { return existing }
        if let otherWindow = webViewsByTabAndWindow[tab.id]?.keys.first {
            return createCloneWebView(for: tab, in: windowId, primaryWindowId: otherWindow)
        }
        let primary = createPrimaryWebView(for: tab, in: windowId)
        tab.assignWebViewToWindow(primary, windowId: windowId)
        return primary
    }

    // MARK: - Private Helpers

    private func performFallbackWebViewCleanup(_ webView: WKWebView, tabId: UUID) {
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

        // MEMORY LEAK FIX: Detach contextMenuBridge
        if let focusableWebView = webView as? FocusableWKWebView {
            focusableWebView.contextMenuBridge?.detach()
            focusableWebView.contextMenuBridge = nil
        }

        // Clear delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // Remove from view hierarchy
        webView.removeFromSuperview()
    }

    // MARK: - Cross-Window Sync

    /// Sync a tab's URL across all windows displaying it
    func syncTab(_ tabId: UUID, to url: URL) {
        // Prevent recursive sync calls
        guard !isSyncingTab.contains(tabId) else {
            return
        }

        isSyncingTab.insert(tabId)
        defer { isSyncingTab.remove(tabId) }

        // Get all web views for this tab across all windows
        let allWebViews = getAllWebViews(for: tabId)

        for webView in allWebViews {
            // Sync the URL if it's different. WebKit canonicalizes the URL it reports
            // (a bare host gains "/"), so compare canonical forms: a raw mismatch would
            // start a second navigation in the view that is already loading it.
            if Self.canonical(webView.url) != Self.canonical(url) {
                Tab.loadPage(url, in: webView)
            }
        }
    }

    /// Lowercased scheme and host, "/" for an empty path, default port dropped.
    private static func canonical(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url?.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.isEmpty, components.host != nil { components.path = "/" }
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }
        return components.string ?? url.absoluteString
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tabId: UUID) {
        let allWebViews = getAllWebViews(for: tabId)
        for webView in allWebViews {
            webView.reload()
        }
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID, excludingWindow originatingWindowId: UUID?) {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return }

        for (_, webView) in windowWebViews {
            // Simple: just set all webviews to the same mute state
            webView.isMuted = muted
        }
    }
}
