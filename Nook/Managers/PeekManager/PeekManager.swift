//
//  PeekManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import WebKit
import AppKit

@MainActor
final class PeekManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentSession: PeekSession?

    weak var browserManager: BrowserManager?
    var webView: PeekWebView?

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func presentExternalURL(_ url: URL, from tab: Tab?) {
        guard let browserManager else { return }

        // Don't show Peek if already showing this URL
        if currentSession?.currentURL == url {
            dismissPeek()
            return
        }

        let windowId = browserManager.activeWindowState?.id ?? UUID()
        let session = PeekSession(
            targetURL: url,
            sourceTabId: tab?.id,
            sourceURL: tab?.url,
            windowId: windowId,
            sourceProfileId: tab?.resolveProfile()?.id
        )

        // Create WebView FIRST, then activate
        currentSession = session
        let peekWebView = createWebView()
        self.webView = peekWebView
        
        // Defer activation to avoid runloop-mode reentrancy from WebKit delegates
        RunLoop.current.perform {
            self.isActive = true
            // Proactively nudge SwiftUI and provide out-of-band signal
            self.browserManager?.objectWillChange.send()
            NotificationCenter.default.post(name: .peekDidActivate, object: self)
        }
    }

    func dismissPeek() {
        guard isActive else { return }

        isActive = false
        webView = nil

        // Proactively notify dismissal
        browserManager?.objectWillChange.send()
        NotificationCenter.default.post(name: .peekDidDeactivate, object: self)

        currentSession = nil
    }


    func moveToSplitView() {
        guard let session = currentSession,
              let browserManager else { return }

        // Create a new tab with the peeked URL and integrate into tab management
        let newTab = browserManager.tabManager.createNewTab(
            url: session.currentURL.absoluteString,
            in: browserManager.tabManager.currentSpace
        )

        // Enter split view with the new tab
        browserManager.splitManager.enterSplit(with: newTab, placeOn: .right)

        // Activate the new tab using BrowserManager to update window UI state
        browserManager.selectTab(newTab)
        dismissPeek()
    }

    func moveToNewTab() {
        guard let session = currentSession,
              let browserManager else { return }

        // Create a new tab with the peeked URL and integrate into tab management
        let newTab = browserManager.tabManager.createNewTab(
            url: session.currentURL.absoluteString,
            in: browserManager.tabManager.currentSpace
        )
        // Activate via BrowserManager to ensure full UI updates
        browserManager.selectTab(newTab)
        dismissPeek()
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
