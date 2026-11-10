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

    /// An Escape the page left alone (`EscapeKey`). Closes the innermost thing the window shows:
    /// a page's own full screen, then Peek, then the find bar. The window itself stays as it is.
    func escapePressed(in nsWindow: NSWindow) {
        guard let state = windowRegistry?.windows.values.first(where: { $0.window === nsWindow }) else { return }
        let peek = peekManager.windowId == state.id ? peekManager.page : nil
        let shown = [peek, tabs.selectedSession(in: state)]
            + [splitManager.leftTabId(for: state.id), splitManager.rightTabId(for: state.id)].map { $0.flatMap(tabs.session(for:)) }
        if let view = shown.compactMap({ $0?.webView }).first(where: { $0.fullscreenState != .notInFullscreen }) {
            // In Nook's own world, where a page cannot replace exitFullscreen with a no-op.
            view.evaluateJavaScript("document.exitFullscreen()", in: nil, in: .defaultClient) { _ in }
        } else if peek != nil {
            peekManager.dismissPeek()
        } else if findManager.isFindBarVisible {
            findManager.hideFindBar()
        } else {
            state.multiSelection.clear()
        }
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
    /// Copies the URL of the page in front: a key mini window's page, Peek while it shows, else the
    /// active window's selected page (which follows the last split pane clicked).
    func copyCurrentURL() {
        let state = windowRegistry?.activeWindow
        let mini = (NSApp.keyWindow as? MiniBrowserWindow)?.page
        let peek = state.flatMap { peekManager.windowId == $0.id ? peekManager.page : nil }
        guard let page = mini ?? peek ?? tabs.activeWindowSession else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(page.url.absoluteString, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)

        if mini != nil {
            NotificationCenter.default.post(name: .miniWindowCopiedURL, object: page)
        } else if let state {
            state.isShowingCopyURLToast = true
            Task { [weak state] in
                try? await Task.sleep(for: .seconds(2))
                state?.isShowingCopyURLToast = false
            }
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

        // `_inspector` is WebKit SPI with no public spelling; the alert covers a WebKit without it.
        let webView = currentTab.activeWebView
        let selector = NSSelectorFromString("_inspector")
        guard webView.responds(to: selector),
              let inspector = webView.perform(selector)?.takeUnretainedValue() as? NSObject else {
            showWebInspectorAlert()
            return
        }
        inspector.perform(NSSelectorFromString("show"))
        inspector.perform(NSSelectorFromString("attach"))
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Printing

    /// The print panel for the active window's page, a PDF included.
    func printCurrentPage() {
        guard let windowState = windowRegistry?.activeWindow,
              let session = tabs.controllableSession(in: windowState),
              let webView = getWebView(for: session.itemID, in: windowState.id)
        else { return }
        webView.nookPrint()
    }

    /// Pins the window's selected tab to its space, or unpins it. Favorites are left alone.
    func togglePinCurrentTab() {
        guard let window = windowRegistry?.activeWindow, window.window?.attachedSheet == nil,
              NSApp.keyWindow === window.window, let id = window.selectedItemID else { return }
        switch tabs.section(of: id) {
        case .tabs:
            if let spaceID = tabs.spaceID(of: id) ?? window.spaceID { tabs.pin(id, to: .pinned(spaceID: spaceID)) }
        case .pinned:
            tabs.unpin(id)
        default:
            break
        }
    }

    /// true to pin, false to unpin, nil for a favorite or no tab.
    var pinToggleIsPin: Bool? {
        guard let id = windowRegistry?.activeWindow?.selectedItemID else { return nil }
        switch tabs.section(of: id) {
        case .tabs: return true
        case .pinned: return false
        default: return nil
        }
    }

    /// Stops the selected page loading. Cmd-. also cancels sheets, so with one up (or another window key) the key goes on as cancel.
    func stopLoadingCurrentPage() {
        guard let window = windowRegistry?.activeWindow, window.window?.attachedSheet == nil,
              NSApp.keyWindow === window.window else {
            NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
            return
        }
        tabs.controllableSession(in: window)?.stop()
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

        zoomManager.zoomIn(for: webView)
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

        zoomManager.zoomOut(for: webView)
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

        zoomManager.resetZoom(for: webView)
        shouldShowZoomPopup = true
    }

    /// Apply the new page's saved site zoom when a tab navigates.
    func loadZoomForTab(_ tabId: UUID) {
        // Every window's view of the page, not just the active window's: zoom is per view.
        for webView in webViewCoordinator?.getAllWebViews(for: tabId) ?? [] {
            zoomManager.restoreZoom(for: webView)
        }
        // A background tab navigating must not move the readout off the tab being looked at.
        zoomManager.showZoomLevel(for: tabs.activeWindowSession?.webView)
    }

}
