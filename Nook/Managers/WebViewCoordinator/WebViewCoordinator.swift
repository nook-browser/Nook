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

    /// Web views by item id, then window id. The first window to show a page holds the
    /// session's primary view; other windows get clones. A live view never moves between windows.
    private var webViewsByItemAndWindow: [UUID: [UUID: WKWebView]] = [:]

    func getWebView(for itemID: UUID, in windowId: UUID) -> WKWebView? {
        webViewsByItemAndWindow[itemID]?[windowId]
    }

    func getAllWebViews(for itemID: UUID) -> [WKWebView] {
        webViewsByItemAndWindow[itemID].map { Array($0.values) } ?? []
    }

    func setWebView(_ webView: WKWebView, for itemID: UUID, in windowId: UUID) {
        webViewsByItemAndWindow[itemID, default: [:]][windowId] = webView
    }

    /// The view `windowId` shows for `session`: its existing one, else the session's primary
    /// when no other window shows the page, else a clone.
    func createWebView(for session: PageSession, in windowId: UUID) -> WKWebView {
        if let existing = getWebView(for: session.itemID, in: windowId) { return existing }
        if let otherWindow = webViewsByItemAndWindow[session.itemID]?.keys.first {
            return createClone(for: session, in: windowId, copyFrom: getWebView(for: session.itemID, in: otherWindow))
        }
        // Adopt the session's configured view, including restored navigation and popup state.
        // Selection may already have created it; never start a second navigation for assignment.
        session.loadWebViewIfNeeded()
        let primary = session.webView ?? createClone(for: session, in: windowId, copyFrom: nil)
        setWebView(primary, for: session.itemID, in: windowId)
        session.assignWebView(primary, toWindow: windowId)
        return primary
    }

    private func createClone(for session: PageSession, in windowId: UUID, copyFrom source: WKWebView?) -> WKWebView {
        // Derive the config from an existing view or the profile's shared config to keep the
        // process pool and extension controller (fresh configs break content script injection).
        let configuration: WKWebViewConfiguration
        if let sourceWebView = source ?? session.webView {
            configuration = sourceWebView.configuration
        } else if let profile = session.profile {
            configuration = BrowserConfiguration.shared.webViewConfiguration(for: profile)
        } else {
            configuration = BrowserConfiguration.shared.webViewConfiguration.copy() as! WKWebViewConfiguration
        }
        // Fresh user content controller per view: handlers are keyed by name.
        configuration.userContentController = BrowserConfiguration.shared.freshUserContentController()

        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = session
        newWebView.uiDelegate = session
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.owningSession = session
        newWebView.contextMenuBridge = WebContextMenuBridge(session: session, configuration: configuration)
        // Same handlers, user agent and preferences as the primary: a clone is promoted to
        // primary when its window outlives the primary's window.
        session.configure(newWebView)
        session.setupThemeColorObserver(for: newWebView)
        session.setupNavigationStateObservers(for: newWebView)

        PageSession.loadPage(session.url, in: newWebView)
        newWebView.isMuted = session.isAudioMuted
        setWebView(newWebView, for: session.itemID, in: windowId)
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

    func removeAllWebViews(for session: PageSession) {
        guard let entries = webViewsByItemAndWindow.removeValue(forKey: session.itemID) else { return }
        for webView in entries.values {
            session.cleanupClone(webView)
            removeWebViewFromContainers(webView)
        }
    }

    /// Removes the item's pool entries without cleaning the views (legacy `Tab` callers do that).
    func removeEntries(for itemID: UUID) -> [UUID: WKWebView] {
        webViewsByItemAndWindow.removeValue(forKey: itemID) ?? [:]
    }

    // MARK: - Window Cleanup

    /// A window closed: its views go. A primary passes to another window's clone when one
    /// exists, else the page unloads.
    func cleanupWindow(_ windowId: UUID, tabs: TabsController) {
        let closing = webViewsByItemAndWindow.compactMap { itemID, views in
            views[windowId].map { (itemID, $0) }
        }
        for (itemID, webView) in closing {
            webViewsByItemAndWindow[itemID]?.removeValue(forKey: windowId)
            if webViewsByItemAndWindow[itemID]?.isEmpty == true {
                webViewsByItemAndWindow.removeValue(forKey: itemID)
            }
            if let session = tabs.session(for: itemID) {
                if session.webView === webView {
                    if let replacement = webViewsByItemAndWindow[itemID]?.first {
                        session.assignWebView(replacement.value, toWindow: replacement.key)
                        session.cleanupClone(webView)
                    } else {
                        session.unload()
                    }
                } else {
                    session.cleanupClone(webView)
                }
            } else {
                Self.detachOrphan(webView, itemID: itemID)
            }
            removeWebViewFromContainers(webView)
        }
        removeCompositorContainerView(for: windowId)
    }

    /// Cleanup for a view whose session is gone.
    static func detachOrphan(_ webView: WKWebView, itemID: UUID) {
        webView.stopLoading()
        let controller = webView.configuration.userContentController
        let handlerNames = [
            "linkHover", "commandHover", "commandClick", "pipStateChange",
            "mediaStateChange_\(itemID.uuidString)", "backgroundColor_\(itemID.uuidString)",
            "historyStateDidChange", "NookIdentity", "nookShortcutDetect",
        ]
        for name in handlerNames {
            controller.removeScriptMessageHandler(forName: name)
        }
        if let focusable = webView as? FocusableWKWebView {
            focusable.contextMenuBridge?.detach()
            focusable.contextMenuBridge = nil
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    // MARK: - Cross-Window Sync

    /// Loads `url` in every window's view of the item that shows something else.
    func syncTab(_ itemID: UUID, to url: URL) {
        guard !isSyncingTab.contains(itemID) else { return }
        isSyncingTab.insert(itemID)
        defer { isSyncingTab.remove(itemID) }

        for webView in getAllWebViews(for: itemID) {
            // Sync the URL if it's different. WebKit canonicalizes the URL it reports
            // (a bare host gains "/"), so compare canonical forms: a raw mismatch would
            // start a second navigation in the view that is already loading it.
            if Self.canonical(webView.url) != Self.canonical(url) {
                PageSession.loadPage(url, in: webView)
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

    func reloadTab(_ itemID: UUID) {
        getAllWebViews(for: itemID).forEach { $0.reload() }
    }

    func setMuteState(_ muted: Bool, for itemID: UUID, excludingWindow originatingWindowId: UUID?) {
        getAllWebViews(for: itemID).forEach { $0.isMuted = muted }
    }
}
