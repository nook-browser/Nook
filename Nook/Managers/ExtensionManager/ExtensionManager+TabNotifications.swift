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

    // MARK: - Adapters

    /// Adapter for a tab item extensions may see; nil for folders, unknown ids and private items.
    func adapter(for itemID: UUID) -> ExtensionTabAdapter? {
        if let existing = tabAdapters[itemID] { return existing }
        guard let bm = browserManagerRef, let item = bm.tabs.item(itemID), !item.isFolder,
              bm.tabs.session(for: itemID)?.isPrivate != true,
              !(bm.windowRegistry?.allWindows ?? []).contains(where: { $0.privateTree?.item(itemID) != nil })
        else { return nil }
        // ponytail: adapters for items closed without ever loading stay cached (a few bytes each);
        // prune against the tree if that ever shows up.
        let created = ExtensionTabAdapter(itemID: itemID, browserManager: bm)
        tabAdapters[itemID] = created
        return created
    }

    /// Adapter for a tab the controller already knows about; nil for private or unopened tabs.
    func openedAdapter(for itemID: UUID) -> ExtensionTabAdapter? {
        openedTabIDs.contains(itemID) ? adapter(for: itemID) : nil
    }

    /// Adapter for a regular window, created (and announced to the controller) on first use.
    /// nil for private windows, which extensions never see.
    func windowAdapter(for window: BrowserWindowState) -> ExtensionWindowAdapter? {
        guard window.privateTree == nil, !window.isIncognito else { return nil }
        if let existing = windowAdapters[window.id] { return existing }
        guard let bm = browserManagerRef else { return nil }
        let created = ExtensionWindowAdapter(window: window, browserManager: bm)
        windowAdapters[window.id] = created
        extensionController?.didOpenWindow(created)
        return created
    }

    /// Regular windows, focused first.
    var openWindowAdapters: [ExtensionWindowAdapter] {
        guard let registry = browserManagerRef?.windowRegistry else { return [] }
        let active = registry.activeWindow
        let ordered = (active.map { [$0] } ?? []) + registry.allWindows.filter { $0 !== active }
        return ordered.compactMap { windowAdapter(for: $0) }
    }

    // MARK: - Window Events

    /// Window focus and close come from AppKit notifications; the tab model has no window hooks.
    func observeWindowEvents() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            let nsWindow = note.object as? NSWindow
            MainActor.assumeIsolated { self?.windowBecameMain(nsWindow) }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let nsWindow = note.object as? NSWindow
            MainActor.assumeIsolated { self?.windowWillClose(nsWindow) }
        }
    }

    private func windowBecameMain(_ nsWindow: NSWindow?) {
        guard let nsWindow, let controller = extensionController, let bm = browserManagerRef,
              let window = bm.windowRegistry?.allWindows.first(where: { $0.window === nsWindow })
        else { return }
        // A private window focused: tabs.query({active: true}) has no answer, as before.
        guard let adapter = windowAdapter(for: window) else { return }
        controller.didFocusWindow(adapter)
        // Extensions resolve the active tab from the focused window, so switching windows
        // switches the active tab too.
        if let session = bm.tabs.selectedSession(in: window) {
            notifyTabActivated(new: session, previous: nil)
        }
    }

    private func windowWillClose(_ nsWindow: NSWindow?) {
        guard let nsWindow,
              let adapter = windowAdapters.values.first(where: { $0.state?.window === nsWindow })
        else { return }
        windowAdapters[adapter.windowID] = nil
        extensionController?.didCloseWindow(adapter)
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
