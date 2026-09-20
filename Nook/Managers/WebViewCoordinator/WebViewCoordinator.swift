// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  WebViewCoordinator.swift
//  Nook
//
//  Manages WebView instances across multiple windows
//

import Foundation
import AppKit
import WebKit
import NookWeb

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

    /// Web views by item id, then window id. A page has one live view, held by the window that
    /// owns it (`TabsController.pageOwnerWindow(of:)`); other windows show a placeholder.
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

    /// The live view for `session`, assigned to `windowId`. When another window held it, the
    /// same view moves here (adding it to this window's container removes it from the other),
    /// so the page keeps its state and runs in one process.
    func createWebView(for session: PageSession, in windowId: UUID) -> WKWebView {
        if let existing = getWebView(for: session.itemID, in: windowId), existing === session.webView {
            return existing
        }
        // Adopt the session's configured view, including restored navigation and popup state.
        // Selection may already have created it; never start a second navigation for assignment.
        session.loadWebViewIfNeeded()
        let primary = session.webView ?? createClone(for: session, in: windowId, copyFrom: nil)
        for (otherWindow, view) in webViewsByItemAndWindow[session.itemID] ?? [:] where view !== primary {
            // Views from before single ownership, or a stale entry: release them.
            session.cleanupClone(view)
            removeWebViewFromContainers(view)
            webViewsByItemAndWindow[session.itemID]?.removeValue(forKey: otherWindow)
        }
        webViewsByItemAndWindow[session.itemID] = [windowId: primary]
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

    // MARK: - Window Cleanup

    /// A window closed: its views go. A live page another window still shows moves there on
    /// that window's next compositor pass; otherwise the page unloads.
    func cleanupWindow(_ windowId: UUID, tabs: TabsController) {
        let closing = webViewsByItemAndWindow.compactMap { itemID, views in
            views[windowId].map { (itemID, $0) }
        }
        for (itemID, webView) in closing {
            webViewsByItemAndWindow[itemID]?.removeValue(forKey: windowId)
            if webViewsByItemAndWindow[itemID]?.isEmpty == true {
                webViewsByItemAndWindow.removeValue(forKey: itemID)
            }
            removeWebViewFromContainers(webView)
            if let session = tabs.session(for: itemID) {
                if session.webView === webView {
                    let stillShown = tabs.regularWindows.contains { window in
                        window.id != windowId && (window.selectedItemID == itemID
                            || window.split?.leftItemID == itemID || window.split?.rightItemID == itemID)
                    } || tabs.privateWindows.contains { $0.id != windowId && $0.selectedItemID == itemID }
                    if stillShown {
                        tabs.refreshWindows(showing: itemID)
                    } else {
                        session.unload()
                    }
                } else {
                    session.cleanupClone(webView)
                }
            } else {
                Self.detachOrphan(webView, itemID: itemID)
            }
        }
        removeCompositorContainerView(for: windowId)
    }

    /// Cleanup for a view whose session is gone.
    static func detachOrphan(_ webView: WKWebView, itemID: UUID) {
        webView.stopLoading()
        let controller = webView.configuration.userContentController
        let handlerNames = [
            "linkHover", "commandHover", "pipStateChange",
            "mediaStateChange_\(itemID.uuidString)", "backgroundColor_\(itemID.uuidString)",
            "historyStateDidChange", "nookShortcutDetect",
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
