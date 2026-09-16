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
    /// The spaces a window pages through: a private window's own spaces, else every space.
    func switchableSpaces(for window: BrowserWindowState) -> [SpaceRecord] {
        window.privateTree?.orderedSpaces ?? orderedSpaces
    }

    /// Tabs under a parent, counting inside folders at any depth.
    func tabCount(under parent: Parent) -> Int {
        children(of: parent).reduce(0) { total, item in
            total + (item.isFolder ? tabCount(under: .folder(itemID: item.id)) : 1)
        }
    }

    /// Tabs in a space's pinned and tabs sections.
    func tabCount(inSpace spaceID: UUID) -> Int {
        tabCount(under: .pinned(spaceID: spaceID)) + tabCount(under: .tabs(spaceID: spaceID))
    }
}
