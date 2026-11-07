// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+MultiSelect.swift
//  NookWeb
//
//  Intents on several tabs at once. Each is one undo step.
//

import Foundation
import NookTabsCore

extension TabsController {
    /// The window's multi-selected tabs in sidebar order. Empty unless two or more are visible.
    public func selectedItems(in window: BrowserWindowState) -> [UUID] {
        guard let spaceID = window.spaceID, window.multiSelection.ids.count > 1 else { return [] }
        let ids = rows(space: spaceID).map(\.id).filter(window.multiSelection.contains)
        return ids.count > 1 ? ids : []
    }

    /// The visible tab rows of the section holding `itemID`, for a Shift-click range.
    public func sectionTabIDs(containing itemID: UUID, in window: BrowserWindowState) -> [UUID] {
        guard let spaceID = window.spaceID,
              let section = rows(space: spaceID).first(where: { $0.id == itemID })?.section else { return [] }
        return rows(space: spaceID).filter { $0.section == section && !$0.item.isFolder }.map(\.id)
    }

    public func pin(_ itemIDs: [UUID], to parent: Parent) {
        grouped { for id in itemIDs { pin(id, to: parent) } }
    }

    public func unpin(_ itemIDs: [UUID]) {
        guard let spaceID = itemIDs.first.flatMap(unpinSpaceID) else { return }
        move(itemIDs, to: .tabs(spaceID: spaceID), after: nil)
    }

    /// Moves the items in order, the first after `after`.
    public func move(_ itemIDs: [UUID], to parent: Parent, after: UUID?) {
        grouped {
            var previous = after
            for id in itemIDs {
                move(id, to: parent, after: previous)
                previous = id
            }
        }
    }

    /// A folder where the first item sits, holding all of them.
    @discardableResult
    public func createFolder(title: String, holding itemIDs: [UUID]) -> UUID? {
        guard let first = itemIDs.first.flatMap(item) else { return nil }
        var folder: UUID?
        grouped {
            folder = createFolder(title: title, in: first.parent, after: first.id)
            if let folder { move(itemIDs, to: .folder(itemID: folder), after: nil) }
        }
        return folder
    }

    /// Runs `drop`, which lands `dragged`, then puts the rest of `group` (sidebar order) around it
    /// in the same order.
    public func dropGroup(_ group: [UUID], dragged: UUID, drop: () -> Void) {
        grouped {
            let before = item(dragged).map { [$0.parent: $0.order] }
            drop()
            // A drop that left the dragged tab where it was leaves the group alone too.
            guard let now = item(dragged), before != [now.parent: now.order] else { return }
            guard let parent = item(dragged)?.parent, let at = group.firstIndex(of: dragged) else { return }
            let siblings = children(of: parent).map(\.id)
            let rest = Set(group)
            let beforeDragged = siblings.prefix { $0 != dragged }.last { !rest.contains($0) }
            move(Array(group[..<at]), to: parent, after: beforeDragged)
            move(Array(group[(at + 1)...]), to: parent, after: dragged)
        }
    }
}
