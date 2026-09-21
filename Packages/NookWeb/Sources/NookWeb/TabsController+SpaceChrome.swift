// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+SpaceChrome.swift
//  Nook
//
//  Reads the space switcher, space menus and profile settings share. Built only from the
//  public TabsController contract.
//

import Foundation
import NookTabsCore

extension TabsController {
    // MARK: - Sidebar Reads

    /// Every folder in a space's pinned and tabs sections, depth first, with its depth.
    public func folders(inSpace spaceID: UUID) -> [(item: Item, depth: Int)] {
        var result: [(item: Item, depth: Int)] = []
        func walk(_ parent: Parent, depth: Int) {
            for child in children(of: parent) where child.isFolder {
                result.append((child, depth))
                walk(.folder(itemID: child.id), depth: depth + 1)
            }
        }
        walk(.pinned(spaceID: spaceID), depth: 0)
        walk(.tabs(spaceID: spaceID), depth: 0)
        return result
    }

    /// True for favorites and pinned items (and anything inside pinned folders).
    public func isSynced(_ itemID: UUID) -> Bool {
        switch section(of: itemID) {
        case .favorites, .pinned: return true
        default: return false
        }
    }

    /// Row title: custom title, else the live page title, else the saved page title, else the host.
    public func title(for item: Item) -> String {
        if let custom = item.customTitle, !custom.isEmpty { return custom }
        if let live = session(for: item.id)?.title, !live.isEmpty { return live }
        if !item.displayTitle.isEmpty { return item.displayTitle }
        return item.url?.host ?? "New Tab"
    }

    /// Current page URL: the live page, else the saved URL.
    public func currentURL(for item: Item) -> URL? {
        session(for: item.id)?.url ?? item.url
    }

    /// The spaces a window pages through: a private window's own spaces, else every space.
    public func switchableSpaces(for window: BrowserWindowState) -> [SpaceRecord] {
        window.privateTree?.orderedSpaces ?? orderedSpaces
    }

    /// Tabs under a parent, counting inside folders at any depth.
    public func tabCount(under parent: Parent) -> Int {
        children(of: parent).reduce(0) { total, item in
            total + (item.isFolder ? tabCount(under: .folder(itemID: item.id)) : 1)
        }
    }

    /// Tabs in a space's pinned and tabs sections.
    public func tabCount(inSpace spaceID: UUID) -> Int {
        tabCount(under: .pinned(spaceID: spaceID)) + tabCount(under: .tabs(spaceID: spaceID))
    }
}
