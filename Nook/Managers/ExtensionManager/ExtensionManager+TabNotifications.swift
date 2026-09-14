//
//  ExtensionManager+TabNotifications.swift
//  Nook
//
//  Controller event notifications for tabs and action anchor management
//

import AppKit
import Foundation
import os
import WebKit

@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Controller event notifications for tabs

    @available(macOS 15.5, *)
    func adapter(for tab: Tab, browserManager: BrowserManager)
        -> ExtensionTabAdapter
    {
        if let existing = tabAdapters[tab.id] {
            return existing
        }
        let created = ExtensionTabAdapter(
            tab: tab,
            browserManager: browserManager
        )
        tabAdapters[tab.id] = created
        Self.logger.debug("Created tab adapter for '\(tab.name, privacy: .public)'")
        return created
    }

    // Expose a stable adapter getter for window adapters
    @available(macOS 15.4, *)
    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let bm = browserManagerRef else { return nil }
        return adapter(for: tab, browserManager: bm)
    }

    @available(macOS 15.4, *)
    func notifyTabOpened(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didOpenTab(a)
        tabCacheGeneration &+= 1
    }

    /// Grant all extension contexts explicit access to a URL.
    /// WKWebExtensionController uses Safari's per-URL permission model where even
    /// granted match patterns don't give implicit URL access. Without this, content
    /// scripts won't inject and messaging fails. Call before navigation starts.
    @available(macOS 15.4, *)
    func grantExtensionAccessToURL(_ url: URL) {
        for (_, ctx) in extensionContexts {
            ctx.setPermissionStatus(.grantedExplicitly, for: url)
        }

        // Also grant a match pattern covering the URL's origin for content script injection.
        // The per-URL grant above covers chrome.tabs.query() and messaging, but content
        // scripts require a matching pattern to inject. WebKit's <all_urls> may not match
        // IP addresses (e.g. local servers at 192.168.x.x, 10.x.x.x), so we create an
        // explicit origin pattern like "http://192.168.1.140/*" to ensure injection.
        if let scheme = url.scheme, let host = url.host {
            var hostPort = host
            if let port = url.port { hostPort = "\(host):\(port)" }
            let patternString = "\(scheme)://\(hostPort)/*"
            if let pattern = try? WKWebExtension.MatchPattern(string: patternString) {
                for (_, ctx) in extensionContexts {
                    ctx.setPermissionStatus(.grantedExplicitly, for: pattern)
                }
            }
        }
    }

    @available(macOS 15.4, *)
    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let newA = adapter(for: newTab, browserManager: bm)
        let oldA = previous.map { adapter(for: $0, browserManager: bm) }
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }

        // Wake MV3 background workers on tab switch so they can update
        // badge counts and autofill state for the newly active tab.
        wakeBackgroundWorkers()

        // Grant all extension contexts explicit access to the active tab's URL.
        // Without this, content scripts can't inject and chrome.tabs.query()
        // won't return the URL — WebKit requires per-URL grants even when
        // match patterns already cover the domain.
        if let scheme = newTab.url.scheme, ["http", "https"].contains(scheme) {
            grantExtensionAccessToURL(newTab.url)
        }

        // Fire property changes so background workers re-evaluate the page
        // (autofill detection, badge text, declarativeContent rules).
        controller.didChangeTabProperties([.URL, .title], for: newA)
        tabCacheGeneration &+= 1
    }

    @available(macOS 15.4, *)
    func notifyTabClosed(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didCloseTab(a, windowIsClosing: false)
        tabAdapters[tab.id] = nil
        tabCacheGeneration &+= 1
    }

    @available(macOS 15.4, *)
    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        guard let bm = browserManagerRef, let controller = extensionController
        else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didChangeTabProperties(properties, for: a)
        tabCacheGeneration &+= 1
    }

    // MARK: - Extension Command Forwarding

    /// Forward a keyboard event to all extension contexts to handle chrome.commands shortcuts.
    /// Returns true if any extension consumed the event.
    @available(macOS 15.4, *)
    func tryPerformExtensionCommand(for event: NSEvent) -> Bool {
        for (_, ctx) in extensionContexts {
            if ctx.performCommand(for: event) {
                return true
            }
        }
        return false
    }

    // MARK: - Background Worker Lifecycle

    /// Wake all MV3 background service workers so they can process the current page.
    /// MV3 workers auto-terminate after ~5 min of inactivity. Waking them on navigation
    /// and tab activation ensures content script messages reach a live worker for features
    /// like autofill detection and badge count updates.
    @available(macOS 15.4, *)
    func wakeBackgroundWorkers() {
        for (_, ctx) in extensionContexts {
            guard ctx.webExtension.hasBackgroundContent else { continue }
            ctx.loadBackgroundContent { error in
                if let error {
                    Self.logger.debug("Background wake failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Register a UI anchor view for an extension action button to position popovers.
    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        Self.logger.debug("setActionAnchor called for extension ID: \(extensionId, privacy: .public)")
        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        if actionAnchors[extensionId] == nil { actionAnchors[extensionId] = [] }
        // Remove stale anchors
        actionAnchors[extensionId]?.removeAll { $0.view == nil }
        if let idx = actionAnchors[extensionId]?.firstIndex(where: {
            $0.view === anchorView
        }) {
            actionAnchors[extensionId]?[idx] = anchor
        } else {
            actionAnchors[extensionId]?.append(anchor)
        }
        Self.logger.debug("Total anchors for extension \(extensionId, privacy: .public): \(self.actionAnchors[extensionId]?.count ?? 0)")

        // MEMORY LEAK FIX: Remove any previous observer for this anchor to prevent accumulation
        if anchorObserverTokens[extensionId] == nil { anchorObserverTokens[extensionId] = [] }

        // Update anchor if view moves to a different window
        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self, weak anchorView] _ in
            MainActor.assumeIsolated {
                guard let anchorView else { return }
                if let idx = self?.actionAnchors[extensionId]?.firstIndex(
                    where: { $0.view === anchorView }
                ) {
                    let updated = WeakAnchor(
                        view: anchorView,
                        window: anchorView.window
                    )
                    self?.actionAnchors[extensionId]?[idx] = updated
                }
            }
        }
        anchorObserverTokens[extensionId]?.append(token)
    }
}
