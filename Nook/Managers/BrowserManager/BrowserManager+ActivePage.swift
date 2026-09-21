// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+ActivePage.swift
//  Nook
//

import AppKit
import SwiftUI
import WebKit

extension BrowserManager {
    // MARK: - Cookie Management Methods

    func clearCurrentPageCookies() {
        guard let currentTab = tabs.activeWindowSession,
            let host = currentTab.url.host
        else { return }

        Task {
            await cookieManager.deleteCookiesForDomain(host)
        }
    }

    func clearAllCookies() {
        Task {
            await cookieManager.deleteAllCookies()
        }
    }

    func clearExpiredCookies() {
        Task {
            await cookieManager.deleteExpiredCookies()
        }
    }

    // MARK: - Cache Management

    func clearCurrentPageCache() {
        guard let currentTab = tabs.activeWindowSession,
            let host = currentTab.url.host
        else { return }

        Task {
            await cacheManager.clearCacheForDomain(host)
        }
    }

    /// Clears site cache for current page excluding cookies, then reloads from origin.
    func hardReloadCurrentPage() {
        guard let currentTab = tabs.activeWindowSession,
            let host = currentTab.url.host,
            let activeWindowId = windowRegistry?.activeWindow?.id
        else { return }
        Task { @MainActor in
            await cacheManager.clearCacheForDomainExcludingCookies(host)
            // Use the WebView that's actually visible in the current window
            if let webView = getWebView(for: currentTab.itemID, in: activeWindowId) {
                webView.reloadFromOrigin()
            } else {
                // Fallback to the tab's default webView
                currentTab.webView?.reloadFromOrigin()
            }
        }
    }

    func clearStaleCache() {
        Task {
            await cacheManager.clearStaleCache()
        }
    }

    func clearDiskCache() {
        Task {
            await cacheManager.clearDiskCache()
        }
    }

    func clearMemoryCache() {
        Task {
            await cacheManager.clearMemoryCache()
        }
    }

    func clearAllCache() {
        Task {
            await cacheManager.clearAllCache()
        }
    }

    // MARK: - Window-Aware Tab Operations for Commands

    /// Refresh the current tab in the active window
    func refreshCurrentTabInActiveWindow() {
        tabs.activeWindowSession?.refresh()
    }

    /// Toggle mute for the current tab in the active window
    func toggleMuteCurrentTabInActiveWindow() {
        tabs.activeWindowSession?.toggleMute()
    }

    /// Request picture-in-picture for the current tab in the active window
    func requestPiPForCurrentTabInActiveWindow() {
        tabs.activeWindowSession?.requestPictureInPicture()
    }

    /// Check if the current tab in the active window has video content
    func currentTabHasVideoContent() -> Bool {
        return tabs.activeWindowSession?.hasVideoContent ?? false
    }

    /// Check if the current tab in the active window has PiP active
    func currentTabHasPiPActive() -> Bool {
        return tabs.activeWindowSession?.hasPiPActive ?? false
    }

    /// Check if the current tab in the active window is muted
    func currentTabIsMuted() -> Bool {
        return tabs.activeWindowSession?.isAudioMuted ?? false
    }

    /// Check if the current tab in the active window has audio content
    func currentTabHasAudioContent() -> Bool {
        return tabs.activeWindowSession?.hasAudioContent ?? false
    }

    // MARK: - URL Utilities
    func copyCurrentURL() {
        if let url = tabs.activeWindowSession?.url.absoluteString {
            #if DEBUG
            print("Attempting to copy URL: \(url)")
            #endif

            NSPasteboard.general.clearContents()
            let success = NSPasteboard.general.setString(url, forType: .string)
            let e = NSHapticFeedbackManager.defaultPerformer
            e.perform(.generic, performanceTime: .drawCompleted)
            #if DEBUG
            print("Clipboard operation success: \(success)")
            #endif

            // Show toast on active window
            if let windowState = windowRegistry?.activeWindow {
                windowState.isShowingCopyURLToast = true

                Task { [weak windowState] in
                    try? await Task.sleep(for: .seconds(2))
                    windowState?.isShowingCopyURLToast = false
                }
            }
        } else {
            #if DEBUG
            print("No URL found to copy")
            #endif
        }
    }

    // MARK: - Web Inspector
    func openWebInspector() {
        guard let currentTab = tabs.activeWindowSession else {
            #if DEBUG
            print("No current tab to inspect")
            #endif
            return
        }

        let webView = currentTab.activeWebView

        // Ensure the webview is inspectable
        webView.isInspectable = true

        // There is no public API to programmatically open the Web Inspector
        // Show an alert instructing the user how to open it manually
        showWebInspectorAlert()
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Zoom Management

    /// Zoom in for the current tab
    func zoomInCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = tabs.activeWindowSession,
            let webView = getWebView(for: currentTab.itemID, in: windowState.id)
        else {
            return
        }

        zoomManager.zoomIn(for: webView, tabId: currentTab.itemID)
        shouldShowZoomPopup = true
    }

    /// Zoom out for the current tab
    func zoomOutCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = tabs.activeWindowSession,
            let webView = getWebView(for: currentTab.itemID, in: windowState.id)
        else {
            return
        }

        zoomManager.zoomOut(for: webView, tabId: currentTab.itemID)
        shouldShowZoomPopup = true
    }

    /// Reset zoom to 100% for the current tab
    func resetZoomCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = tabs.activeWindowSession,
            let webView = getWebView(for: currentTab.itemID, in: windowState.id)
        else {
            return
        }

        zoomManager.resetZoom(for: webView, tabId: currentTab.itemID)
        shouldShowZoomPopup = true
    }

    /// Reset zoom when a tab navigates, so a page never inherits the previous page's zoom.
    func loadZoomForTab(_ tabId: UUID) {
        // Every window's view of the page, not just the active window's: magnification is per view.
        for webView in webViewCoordinator?.getAllWebViews(for: tabId) ?? [] {
            zoomManager.resetZoom(for: webView, tabId: tabId)
        }
        // A background tab navigating must not move the readout off the tab being looked at.
        zoomManager.showZoomLevel(for: windowRegistry?.activeWindow?.selectedItemID)
    }

    /// Clean up zoom data when a tab is closed
    func cleanupZoomForTab(_ tabId: UUID) {
        zoomManager.removeTabZoomLevel(for: tabId)
    }

}
