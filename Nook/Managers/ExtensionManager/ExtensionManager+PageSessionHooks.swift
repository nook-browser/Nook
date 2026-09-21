// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+PageSessionHooks.swift
//  Nook
//
//  Extension notifications TabsController and PageSession call. Adapters are keyed by item
//  id (ExtensionManager+TabNotifications.swift). Private sessions are never reported.
//

import Foundation
import WebKit
import NookWeb

extension ExtensionManager {
    /// Called once a session has a web view, before it loads, so content scripts can resolve it.
    func notifyTabOpened(_ session: PageSession) {
        guard !session.isPrivate, let controller = extensionController,
              !openedTabIDs.contains(session.itemID),
              let adapter = adapter(for: session.itemID)
        else { return }
        // The window must be known to the controller before its tab.
        _ = adapter.hostWindow.flatMap { windowAdapter(for: $0) }
        openedTabIDs.insert(session.itemID)
        controller.didOpenTab(adapter)
    }

    func notifyTabActivated(new: PageSession, previous: PageSession?) {
        guard let controller = extensionController else { return }
        let oldAdapter = previous.flatMap { $0.isPrivate ? nil : openedAdapter(for: $0.itemID) }
        guard !new.isPrivate, let newAdapter = openedAdapter(for: new.itemID) else {
            // Switching to a private or unopened page: just deselect the previous one.
            if let oldAdapter { controller.didDeselectTabs([oldAdapter]) }
            return
        }
        controller.didActivateTab(newAdapter, previousActiveTab: oldAdapter)
        controller.didSelectTabs([newAdapter])
        if let oldAdapter, oldAdapter != newAdapter { controller.didDeselectTabs([oldAdapter]) }

        // Wake MV3 background workers so they update badge counts and autofill state for the
        // newly active tab.
        wakeBackgroundWorkers()

        grantExtensionAccessToURL(new.url)

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
        controller.didCloseTab(adapter, windowIsClosing: false)
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
        guard !session.isPrivate, let controller = extensionController,
              let adapter = openedAdapter(for: session.itemID)
        else { return }
        controller.didChangeTabProperties(properties, for: adapter)
    }
}
