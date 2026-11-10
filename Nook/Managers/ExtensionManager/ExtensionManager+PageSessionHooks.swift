// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+PageSessionHooks.swift
//  Nook
//
//  Extension notifications TabsController and PageSession call. Adapters are keyed by item
//  id (ExtensionManager+TabNotifications.swift). Private pages are reported with their private
//  window, and WebKit hides them from extensions without `hasAccessToPrivateData`.
//

import Foundation
import WebKit
import NookWeb

extension ExtensionManager {
    /// Called once a session has a web view, before it loads, so content scripts can resolve it.
    func notifyTabOpened(_ session: PageSession) {
        guard let controller = extensionController, !openedTabIDs.contains(session.itemID) else { return }
        guard let adapter = session.isDetached ? detachedAdapter(for: session) : adapter(for: session.itemID) else {
            Self.logger.notice("Page not announced to extensions: no adapter (item \(session.itemID.uuidString, privacy: .public))")
            return
        }
        // The window must be known to the controller before its tab. WebKit caches a tab's
        // privacy from its first window, so a private page without its private window stays hidden.
        let window = adapter.hostWindow
        if session.isPrivate, window?.privateTree == nil {
            tabAdapters[session.itemID] = nil
            return
        }
        _ = window.flatMap { windowAdapter(for: $0) }
        openedTabIDs.insert(session.itemID)
        controller.didOpenTab(adapter)
        // Peek and mini window pages open in front, so they become the active tab.
        if adapter.detached != nil {
            notifyTabActivated(new: session, previous: window.flatMap { browserManagerRef?.tabs.selectedSession(in: $0) })
        }
    }

    /// Peek, mini window and sign-in popup pages are tabs to extensions, so content scripts
    /// can reach the background page and the popup fills the page in front.
    private func detachedAdapter(for session: PageSession) -> ExtensionTabAdapter? {
        guard let bm = browserManagerRef else { return nil }
        let created = ExtensionTabAdapter(itemID: session.itemID, browserManager: bm, detachedPage: session)
        tabAdapters[session.itemID] = created
        return created
    }

    /// The tab an action button in `window` acts on: a Peek page over it, else its selected tab.
    func actionAdapter(in window: BrowserWindowState) -> ExtensionTabAdapter? {
        if let peek = detachedAdapters(in: window).first(where: { $0.isInFront }) { return peek }
        return browserManagerRef?.tabs.selectedSession(in: window).flatMap { adapter(for: $0.itemID) }
    }

    /// Clicks an extension's action. WebKit ignores every click while it believes a popup is
    /// open, so a popover it still holds but no longer shows is closed first. Reading
    /// `popupPopover` would build and load a new popup, hence the weak reference.
    func performAction(_ context: WKWebExtensionContext, for tab: ExtensionTabAdapter?) {
        let tab = tab.flatMap { $0.isPrivate && !context.hasAccessToPrivateData ? nil : $0 }
        if let popover = shownPopover, !popover.isShown {
            context.action(for: tab)?.closePopup()
            shownPopover = nil
        }
        // As in Chrome: a button with no popup opens the side panel when the extension asked for that.
        if context.action(for: tab)?.presentsPopup != true, compatSidePanel.opensOnActionClick(context) {
            compatSidePanel.open(context)
            return
        }
        context.performAction(for: tab)
    }

    /// Opened Peek and mini window pages hosted by `window`.
    func detachedAdapters(in window: BrowserWindowState) -> [ExtensionTabAdapter] {
        openedTabIDs.compactMap { id in
            tabAdapters[id].flatMap { $0.detached != nil && $0.hostWindow === window ? $0 : nil }
        }
    }

    func notifyTabActivated(new: PageSession, previous: PageSession?) {
        guard let controller = extensionController else { return }
        let oldAdapter = previous.flatMap { openedAdapter(for: $0.itemID) }
        guard let newAdapter = openedAdapter(for: new.itemID) else {
            // Switching to an unopened page: just deselect the previous one.
            if let oldAdapter { controller.didDeselectTabs([oldAdapter]) }
            return
        }
        controller.didActivateTab(newAdapter, previousActiveTab: oldAdapter)
        controller.didSelectTabs([newAdapter])
        if let oldAdapter, oldAdapter != newAdapter { controller.didDeselectTabs([oldAdapter]) }

        // Wake MV3 background workers so they update badge counts and autofill state for the
        // newly active tab.
        wakeBackgroundWorkers()

        grantExtensionAccessToURL(new.url, private: new.isPrivate)

        // Background workers re-evaluate the page (autofill detection, badge text,
        // declarativeContent rules).
        controller.didChangeTabProperties([.URL, .title], for: newAdapter)
    }

    /// The item's page ended (item closed, pinned page closed, private window closed).
    func notifyTabClosed(itemID: UUID) {
        defer {
            tabAdapters[itemID] = nil
            openedTabIDs.remove(itemID)
        }
        guard let controller = extensionController, let adapter = openedAdapter(for: itemID) else { return }
        let detachedHost = adapter.detached != nil ? adapter.hostWindow : nil
        controller.didCloseTab(adapter, windowIsClosing: false)
        // The page Peek or a mini window covered is in front again.
        if let detachedHost, let selected = browserManagerRef?.tabs.selectedSession(in: detachedHost) {
            notifyTabActivated(new: selected, previous: nil)
        }
    }

    /// An opened tab moved in the sidebar: reorder, folder, pin, unpin or another space.
    /// `oldIndex` is its place in `oldWindow`'s tab list before the move.
    func notifyTabMoved(itemID: UUID, from oldIndex: Int?, in oldWindow: BrowserWindowState?, pinnedChanged: Bool) {
        guard let controller = extensionController, let adapter = openedAdapter(for: itemID) else { return }
        if let oldIndex {
            controller.didMoveTab(adapter, from: oldIndex, in: oldWindow.flatMap { windowAdapter(for: $0) })
        }
        if pinnedChanged {
            controller.didChangeTabProperties([.pinned], for: adapter)
        }
    }

    func notifyTabPropertiesChanged(_ session: PageSession, properties: WKWebExtension.TabChangedProperties) {
        guard let controller = extensionController,
              let adapter = openedAdapter(for: session.itemID)
        else { return }
        controller.didChangeTabProperties(properties, for: adapter)
    }
}
