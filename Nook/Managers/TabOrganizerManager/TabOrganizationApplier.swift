//
//  TabOrganizationApplier.swift
//  Nook
//
//  Maps TabOrganizationPlan actions to TabsController intents
//  and returns the Change that undoes them.
//

import Foundation
import NookTabsCore
import OSLog

// MARK: - AcceptedChanges

/// Which parts of a ``TabOrganizationPlan`` the user has accepted in the preview UI.
struct AcceptedChanges {
    var acceptedGroupIds: Set<UUID>
    var acceptedRenameIds: Set<UUID>
    var acceptedDuplicateIds: Set<UUID>
    var applySortOrder: Bool
}

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

    /// Execute accepted changes from the organization plan.
    ///
    /// - Parameters:
    ///   - plan: The parsed LLM organization plan.
    ///   - accepted: Which plan items were accepted.
    ///   - tabMapping: 1-based prompt indices to item ids.
    ///   - spaceID: The space whose tabs section is organized.
    ///   - tabs: The controller to run intents on.
    /// - Returns: The combined undo change, for `TabsController.apply(_:)`.
    static func apply(
        plan: TabOrganizationPlan,
        accepted: AcceptedChanges,
        tabMapping: [Int: UUID],
        spaceID: UUID,
        tabs: TabsController
    ) -> Change {
        let before = tabs.tree
        let section = Parent.tabs(spaceID: spaceID)

        // 1. Groups: folders at the top of the tabs section, in plan order, holding their tabs in order.
        var lastFolder: UUID?
        for group in plan.groups where accepted.acceptedGroupIds.contains(group.id) {
            guard let folderID = tabs.createFolder(title: group.name, in: section, after: lastFolder) else { continue }
            lastFolder = folderID
            log.debug("Created folder '\(group.name)' for \(group.tabs.count) tabs")
            var lastTab: UUID?
            for index in group.tabs {
                guard let itemID = tabMapping[index] else { continue }
                tabs.move(itemID, to: .folder(itemID: folderID), after: lastTab)
                lastTab = itemID
            }
        }

        // 2. Renames
        for rename in plan.renames where accepted.acceptedRenameIds.contains(rename.id) {
            guard let itemID = tabMapping[rename.tab] else {
                log.warning("Rename: no tab at index \(rename.tab)")
                continue
            }
            tabs.rename(itemID, rename.name)
        }

        // 3. Duplicates
        for duplicates in plan.duplicates where accepted.acceptedDuplicateIds.contains(duplicates.id) {
            let ids = duplicates.close.compactMap { tabMapping[$0] }
            tabs.close(ids)
            log.debug("Closed \(ids.count) duplicate tabs")
        }

        // 4. Sort order, only when groups did not already reorder: sorted tabs go to the top in order.
        if accepted.applySortOrder, let sortOrder = plan.sort, !sortOrder.isEmpty, plan.groups.isEmpty {
            var previous: UUID?
            for index in sortOrder {
                guard let itemID = tabMapping[index], tabs.item(itemID) != nil else { continue }
                tabs.move(itemID, to: section, after: previous)
                previous = itemID
            }
            log.debug("Applied sort order for \(sortOrder.count) tabs")
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
