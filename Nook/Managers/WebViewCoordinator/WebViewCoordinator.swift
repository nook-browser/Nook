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

        // Create configuration
        let configuration = WKWebViewConfiguration()

        if let originalWebView = tab.webView {
            configuration.websiteDataStore = originalWebView.configuration.websiteDataStore
            configuration.preferences = originalWebView.configuration.preferences
            configuration.defaultWebpagePreferences = originalWebView.configuration.defaultWebpagePreferences
            configuration.mediaTypesRequiringUserActionForPlayback = originalWebView.configuration.mediaTypesRequiringUserActionForPlayback
            configuration.allowsAirPlayForMediaPlayback = originalWebView.configuration.allowsAirPlayForMediaPlayback
            configuration.applicationNameForUserAgent = originalWebView.configuration.applicationNameForUserAgent
            if #available(macOS 15.5, *) {
                configuration.webExtensionController = originalWebView.configuration.webExtensionController
            }
        } else {
            let resolvedProfile = tab.resolveProfile()
            configuration.websiteDataStore = resolvedProfile?.dataStore ?? WKWebsiteDataStore.default()

            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences = preferences

            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.allowsAirPlayForMediaPlayback = true
            configuration.applicationNameForUserAgent = "Version/17.4.1 Safari/605.1.15"
            configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
            configuration.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
            configuration.preferences.setValue(true, forKey: "mediaDevicesEnabled")
            configuration.preferences.isElementFullscreenEnabled = true
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

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

        tab.setupThemeColorObserver(for: newWebView)

        if let url = URL(string: tab.url.absoluteString) {
            newWebView.load(URLRequest(url: url))
        }
        newWebView.isMuted = tab.isAudioMuted

        setWebView(newWebView, for: tabId, in: windowId)

        print("🪟 [WebViewCoordinator] Created new web view for tab \(tab.name) in window \(windowId)")
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
