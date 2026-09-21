// Licensed under GPL-3.0. See LICENSE.
//
//  PeekManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import WebKit
import AppKit
import NookWeb

@MainActor
final class PeekManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentSession: PeekSession?

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    var webView: PeekWebView?
    var webViewCoordinator: PeekWebView.Coordinator?

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(_ url: URL, from source: PageSession?) {
        guard browserManager != nil else { return }

        // Don't show Peek if already showing this URL
        if currentSession?.currentURL == url {
            dismissPeek()
            return
        }

        // A private page never falls back to the default persistent store.
        let profile = source?.profile
        if source?.isPrivate == true, profile == nil { return }

        let windowId = windowRegistry?.activeWindow?.id ?? UUID()
        let session = PeekSession(
            targetURL: url,
            sourceTabId: source?.itemID,
            sourceURL: source?.url,
            windowId: windowId,
            sourceProfile: profile
        )

        // Create WebView FIRST, then activate
        currentSession = session
        let peekWebView = createWebView()
        self.webView = peekWebView

        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates
        RunLoop.current.perform { [weak self] in
            MainActor.assumeIsolated {
                self?.isActive = true
                NotificationCenter.default.post(name: .peekDidActivate, object: self)
            }
        }
    }

    func dismissPeek() {
        guard isActive else { return }

        isActive = false
        webView = nil
        webViewCoordinator = nil

        NotificationCenter.default.post(name: .peekDidDeactivate, object: self)

        currentSession = nil
    }


    func moveToSplitView() {
        guard let session = currentSession,
              let browserManager,
              let window = windowRegistry?.activeWindow else { return }
        let previous = window.selectedItemID
        guard let itemID = adoptPeekPage(session, in: window, browserManager: browserManager) else {
            dismissPeek()
            return
        }
        // The adopted page is selected; pair it with the page the window showed before.
        if let previous, previous != itemID {
            browserManager.tabs.select(previous, in: window)
            browserManager.splitManager.enterSplit(with: itemID, placeOn: .right, in: window)
        }
        dismissPeek()
    }

    func moveToNewTab() {
        guard let session = currentSession,
              let browserManager,
              let window = windowRegistry?.activeWindow else { return }
        adoptPeekPage(session, in: window, browserManager: browserManager)
        dismissPeek()
    }

    /// Turns the Peek page into a selected tab of `window`. The Peek web view moves over when it
    /// exists. A private window opens the URL fresh in its own tree, and a view on a private
    /// page's ephemeral store never becomes a saved tab.
    @discardableResult
    private func adoptPeekPage(_ session: PeekSession, in window: BrowserWindowState, browserManager: BrowserManager) -> UUID? {
        let tabs = browserManager.tabs
        if !window.isIncognito, session.sourceProfile?.isEphemeral != true, let webView = webViewCoordinator?.webView {
            return tabs.adopt(webView: webView, url: session.currentURL, title: webView.title ?? session.currentURL.host ?? "",
                              in: window, placement: .newTab)
        }
        return tabs.open(url: session.currentURL, in: window, placement: .newTab)
    }

    // MARK: - WebView Management

    func createWebView() -> PeekWebView {
        // If we already have a WebView, return it (shouldn't happen in normal flow)
        if let existingWebView = webView {
            return existingWebView
        }

        var newWebView = PeekWebView(session: currentSession!)
        newWebView.peekManager = self
        return newWebView
    }

    func updateWebView(_ webView: PeekWebView) {
        self.webView = webView
    }

    // MARK: - Helper Methods

    private func isExternalDomain(_ url: URL) -> Bool {
        guard let currentHost = currentSession?.sourceURL?.host,
              let newHost = url.host else { return false }

        return currentHost != newHost
    }

    var canEnterSplitView: Bool {
        guard let browserManager,
              let windowId = currentSession?.windowId else { return false }

        return !browserManager.splitManager.isSplit(for: windowId)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let peekDidActivate = Notification.Name("PeekDidActivate")
    static let peekDidDeactivate = Notification.Name("PeekDidDeactivate")
}
