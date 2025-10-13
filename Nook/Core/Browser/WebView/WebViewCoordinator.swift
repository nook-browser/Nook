//
//  WebViewCoordinator.swift
//  Nook
//
//  Extracted from BrowserManager.swift
//  Manages WebView lifecycle and synchronization across windows
//

import SwiftUI
import WebKit

@MainActor
final class WebViewCoordinator {
    /// Window-specific web views: tabId -> windowId -> WKWebView
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]

    /// Prevent recursive sync calls
    private var isSyncingTab: Set<UUID> = []

    // MARK: - WebView Registry

    /// Get WebView for a specific tab in a specific window
    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        return webViewsByTabAndWindow[tabId]?[windowId]
    }

    /// Get all WebViews for a specific tab across all windows
    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        return webViewsByTabAndWindow[tabId]?.values.map { $0 } ?? []
    }

    /// Store a WebView for a tab in a specific window
    func storeWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        if webViewsByTabAndWindow[tabId] == nil {
            webViewsByTabAndWindow[tabId] = [:]
        }
        webViewsByTabAndWindow[tabId]?[windowId] = webView
        print("🪟 [WebViewCoordinator] Stored WebView for tab \(tabId) in window \(windowId)")
    }

    /// Remove WebView for a specific tab in a specific window
    func removeWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        let webView = webViewsByTabAndWindow[tabId]?[windowId]
        webViewsByTabAndWindow[tabId]?.removeValue(forKey: windowId)

        // Clean up empty entries
        if webViewsByTabAndWindow[tabId]?.isEmpty == true {
            webViewsByTabAndWindow.removeValue(forKey: tabId)
        }

        return webView
    }

    /// Remove all WebViews for a specific tab
    func removeAllWebViews(for tabId: UUID) -> [UUID: WKWebView] {
        return webViewsByTabAndWindow.removeValue(forKey: tabId) ?? [:]
    }

    /// Get all WebViews for a specific window
    func getWebViewsForWindow(_ windowId: UUID) -> [(tabId: UUID, webView: WKWebView)] {
        return webViewsByTabAndWindow.compactMap { (tabId, windowWebViews) in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (tabId, webView)
        }
    }

    // MARK: - Sync State Management

    /// Check if a tab is currently being synced (to prevent recursion)
    func isSyncing(_ tabId: UUID) -> Bool {
        return isSyncingTab.contains(tabId)
    }

    /// Begin sync for a tab
    func beginSync(_ tabId: UUID) {
        isSyncingTab.insert(tabId)
    }

    /// End sync for a tab
    func endSync(_ tabId: UUID) {
        isSyncingTab.remove(tabId)
    }

    // MARK: - Cleanup

    /// Clear all WebViews (for app shutdown)
    func clearAll() {
        webViewsByTabAndWindow.removeAll()
        isSyncingTab.removeAll()
    }

    /// Get count of tracked WebViews
    func getTotalWebViewCount() -> Int {
        return webViewsByTabAndWindow.values.flatMap { $0.values }.count
    }

    /// Get all tab IDs with WebViews
    func getAllTrackedTabIds() -> [UUID] {
        return Array(webViewsByTabAndWindow.keys)
    }
}
