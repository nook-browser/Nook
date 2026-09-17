//
//  TabsController+Sidebar.swift
//  Nook
//
//  Sidebar helpers built only from TabsController's public intents and reads.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookWeb

extension TabsController {
    // MARK: - Drops

    /// Applies a drop on one sidebar section's displayed rows.
    /// `before` and `into` go through `drop(...)`; `after` a row places the item next to that row
    /// at the row's own level, so an item can land after the last child of a folder.
    func drop(_ itemID: UUID, at position: DropPosition, section: Parent, rows: [Row]) {
        let index = position.index
        guard index < rows.count else {
            drop(itemID, section: section, rows: rows, index: rows.count, intoFolder: false)
            return
        }
        let row = rows[index]
        guard row.item.id != itemID else { return }
        switch position.placement {
        case .into:
            drop(itemID, section: section, rows: rows, index: index, intoFolder: true)
        case .before:
            drop(itemID, section: section, rows: rows, index: index, intoFolder: false)
        case .after:
            if index + 1 < rows.count, rows[index + 1].depth > row.depth {
                // An open folder: right below its header is its first child.
                drop(itemID, section: section, rows: rows, index: index + 1, intoFolder: false)
            } else {
                move(itemID, to: row.item.parent, after: row.item.id)
            }
        }
    }

    /// Drops into a space's favorites grid at tile `index` of the displayed favorites.
    func dropOnFavorites(_ itemID: UUID, spaceID: UUID, index: Int) {
        let favorites = favorites(of: spaceID)
        let after = favorites.prefix(index).last(where: { $0.id != itemID })?.id
        move(itemID, to: .favorites(spaceID: spaceID), after: after)
    }
}
