// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  TabOrganizationApplier.swift
//  Nook
//
//  Maps TabOrganizationPlan actions to TabsController intents
//  and returns the Change that undoes them.
//

import Foundation
import OSLog
import NookTabsCore
import NookWeb

// MARK: - TabOrganizationApplier

/// Stateless applier that turns a ``TabOrganizationPlan`` into `TabsController` intents and
/// returns the `Change` that reverts all of them.
@MainActor
enum TabOrganizationApplier {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook",
        category: "TabOrganizationApplier"
    )

    // MARK: - Apply

    /// Execute the organization plan.
    ///
    /// - Parameters:
    ///   - plan: The organization plan.
    ///   - tabMapping: 1-based prompt indices to item ids.
    ///   - spaceID: The space whose tabs section is organized.
    ///   - tabs: The controller to run intents on.
    /// - Returns: The combined undo change, for `TabsController.apply(_:)`.
    static func apply(
        plan: TabOrganizationPlan,
        tabMapping: [Int: UUID],
        spaceID: UUID,
        tabs: TabsController
    ) -> Change {
        let before = tabs.tree
        let section = Parent.tabs(spaceID: spaceID)

        // 1. Groups: new folders at the top of the tabs section, in plan order; an existing folder
        // takes its tabs at the end. Folder order and tab order inside a folder are the sort.
        var lastFolder: UUID?
        for group in plan.groups {
            let folderID: UUID
            var lastTab: UUID?
            if let existing = group.existingFolderID, tabs.item(existing) != nil {
                folderID = existing
                lastTab = tabs.children(of: .folder(itemID: existing)).last?.id
            } else {
                guard let created = tabs.createFolder(title: group.name, in: section, after: lastFolder) else { continue }
                folderID = created
                lastFolder = created
            }
            log.debug("Filing \(group.tabs.count) tabs into '\(group.name)'")
            for index in group.tabs {
                guard let itemID = tabMapping[index] else { continue }
                tabs.move(itemID, to: .folder(itemID: folderID), after: lastTab)
                lastTab = itemID
            }
        }

        // 2. Renames
        for rename in plan.renames {
            guard let itemID = tabMapping[rename.tab] else { continue }
            tabs.rename(itemID, rename.name)
        }

        // 3. Duplicates
        let duplicates = plan.duplicates.compactMap { tabMapping[$0] }
        if !duplicates.isEmpty {
            tabs.close(duplicates)
            log.debug("Closed \(duplicates.count) duplicate tabs")
        }

        return undoChange(from: before, to: tabs.tree)
    }

    /// The change that turns `after` back into `before`: every item that differs, with its old
    /// value (nil for items the organizer created). Intents keep their own changes internal, so
    /// the organizer diffs the tree instead.
    static func undoChange(from before: TabTree, to after: TabTree) -> Change {
        var change = Change()
        for id in Set(before.items.keys).union(after.items.keys) where before.items[id] != after.items[id] {
            // updateValue keeps an explicit nil ("did not exist"); subscript assignment would drop the key.
            change.items.updateValue(before.items[id], forKey: id)
        }
        return change
    }
}
