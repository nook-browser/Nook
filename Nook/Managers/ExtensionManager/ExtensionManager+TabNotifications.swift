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

extension ExtensionManager {

    // MARK: - Controller event notifications for tabs

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

    /// Adapter for exposing a tab to extensions, or nil for private tabs, which extensions never see.
    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let bm = browserManagerRef, !tab.isEphemeral else { return nil }
        return adapter(for: tab, browserManager: bm)
    }

    func notifyTabOpened(_ tab: Tab) {
        guard let controller = extensionController,
              !openedTabIDs.contains(tab.id),
              let a = stableAdapter(for: tab)
        else { return }
        openedTabIDs.insert(tab.id)
        controller.didOpenTab(a)
        tabCacheGeneration &+= 1
    }

    /// Adapter for a tab the controller already knows about; nil for private or unopened tabs.
    private func openedAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard openedTabIDs.contains(tab.id), let bm = browserManagerRef else { return nil }
        return adapter(for: tab, browserManager: bm)
    }

    /// Give each loaded extension explicit access to `url`, but only when that extension's
    /// granted match patterns already cover it. Some WebKit builds did not treat a granted
    /// pattern as access to a URL (content scripts skipped, `tabs.query` without URLs), so
    /// this makes the implicit grant explicit. It never widens what an extension may reach.
    func grantExtensionAccessToURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host
        else { return }

        let originPattern: WKWebExtension.MatchPattern? = {
            let hostPort = url.port.map { "\(host):\($0)" } ?? host
            return try? WKWebExtension.MatchPattern(string: "\(scheme)://\(hostPort)/*")
        }()

        for ctx in extensionContexts.values where ctx.isLoaded {
            switch ctx.permissionStatus(for: url) {
            case .grantedExplicitly, .grantedImplicitly, .deniedExplicitly:
                continue
            default:
                break
            }
            let covered = ctx.grantedPermissionMatchPatterns.keys.contains { pattern in
                if pattern.matchesAllURLs { return true }
                // `<all_urls>`-style host wildcards did not always match IP-address hosts.
                if pattern.matchesAllHosts, let s = pattern.scheme, s == "*" || s == scheme { return true }
                return pattern.matches(url)
            }
            guard covered else { continue }
            ctx.setPermissionStatus(.grantedExplicitly, for: url)
            if let originPattern {
                ctx.setPermissionStatus(.grantedExplicitly, for: originPattern)
            }
        }
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let controller = extensionController else { return }
        let oldA = previous.flatMap { openedAdapter(for: $0) }
        guard let newA = openedAdapter(for: newTab) else {
            // Switching to a private or unloaded tab: just deselect the previous one.
            if let oldA { controller.didDeselectTabs([oldA]) }
            tabCacheGeneration &+= 1
            return
        }
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }

        // Wake MV3 background workers on tab switch so they can update
        // badge counts and autofill state for the newly active tab.
        wakeBackgroundWorkers()

        grantExtensionAccessToURL(newTab.url)

        // Fire property changes so background workers re-evaluate the page
        // (autofill detection, badge text, declarativeContent rules).
        controller.didChangeTabProperties([.URL, .title], for: newA)
        tabCacheGeneration &+= 1
    }

    func notifyTabClosed(_ tab: Tab) {
        defer {
            tabAdapters[tab.id] = nil
            openedTabIDs.remove(tab.id)
            tabCacheGeneration &+= 1
        }
        guard let controller = extensionController, let a = openedAdapter(for: tab) else { return }
        controller.didCloseTab(a, windowIsClosing: false)
    }

    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        guard let controller = extensionController, let a = openedAdapter(for: tab) else { return }
        controller.didChangeTabProperties(properties, for: a)
        tabCacheGeneration &+= 1
    }

    // MARK: - Extension Command Forwarding

    /// Forward a keyboard event to all extension contexts to handle chrome.commands shortcuts.
    /// Returns true if any extension consumed the event.
    func tryPerformExtensionCommand(for event: NSEvent) -> Bool {
        for ctx in extensionContexts.values where ctx.isLoaded {
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
    func wakeBackgroundWorkers() {
        for ctx in extensionContexts.values where ctx.isLoaded {
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
