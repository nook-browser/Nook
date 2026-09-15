//
//  WebViewCoordinator+LegacyTab.swift
//  Nook
//
//  `Tab` and `TabManager` entry points kept for foundation callers until task Z deletes `Tab`.
//

import WebKit

extension WebViewCoordinator {
    func createWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        if let existing = getWebView(for: tab.id, in: windowId) { return existing }
        tab.loadWebViewIfNeeded()
        let webView = tab.existingWebView ?? FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        setWebView(webView, for: tab.id, in: windowId)
        tab.assignWebViewToWindow(webView, windowId: windowId)
        return webView
    }

    func removeAllWebViews(for tab: Tab) {
        for webView in removeEntries(for: tab.id).values {
            tab.cleanupCloneWebView(webView)
            removeWebViewFromContainers(webView)
        }
    }

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        guard let tabs = tabManager.browserManager?.tabs else {
            removeCompositorContainerView(for: windowId)
            return
        }
        cleanupWindow(windowId, tabs: tabs)
    }
}
