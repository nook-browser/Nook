//
//  TabOrganizationApplier.swift
//  Nook
//
//  Maps TabOrganizationPlan actions to TabManager API calls
//  with snapshot/undo support.
//

import Foundation
import OSLog

// MARK: - TabSnapshot

/// Captures the state of tabs before an organization operation,
/// enabling full undo of grouping, renaming, duplicate removal, and sorting.
struct TabSnapshot {

    struct TabState {
        let tabId: UUID
        let spaceId: UUID?
        let folderId: UUID?
        let index: Int
        let isPinned: Bool
        let isSpacePinned: Bool
        let displayNameOverride: String?
    }

    struct ClosedTabState {
        let tabId: UUID
        let url: URL
        let name: String
        let spaceId: UUID?
        let folderId: UUID?
        let index: Int
        let isPinned: Bool
        let isSpacePinned: Bool
        let displayNameOverride: String?
    }

    let tabStates: [TabState]
    let createdFolderIds: [UUID]
    let closedTabs: [ClosedTabState]
}

// MARK: - AcceptedChanges

/// Which parts of a ``TabOrganizationPlan`` the user has accepted in the preview UI.
struct AcceptedChanges {
    var acceptedGroupIds: Set<UUID>
    var acceptedRenameIds: Set<UUID>
    var acceptedDuplicateIds: Set<UUID>
    var applySortOrder: Bool
}

// MARK: - TabOrganizationApplier

/// Stateless applier that translates a ``TabOrganizationPlan`` into
/// ``TabManager`` mutations with snapshot-based undo.
///
/// All methods are `@MainActor` because they mutate `Tab` and `TabManager` state.
@MainActor
enum TabOrganizationApplier {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook",
        category: "TabOrganizationApplier"
    )

    // MARK: - Snapshot

    /// Capture the current state of the provided tabs so it can be restored later.
    static func snapshot(tabs: [Tab]) -> TabSnapshot {
        let states = tabs.map { tab in
            TabSnapshot.TabState(
                tabId: tab.id,
                spaceId: tab.spaceId,
                folderId: tab.folderId,
                index: tab.index,
                isPinned: tab.isPinned,
                isSpacePinned: tab.isSpacePinned,
                displayNameOverride: tab.displayNameOverride
            )
        }
        return TabSnapshot(tabStates: states, createdFolderIds: [], closedTabs: [])
    }

    // MARK: - Apply

    /// Execute accepted changes from the organization plan.
    ///
    /// - Parameters:
    ///   - plan: The parsed LLM organization plan.
    ///   - accepted: Which plan items the user accepted in the preview sheet.
    ///   - tabMapping: 1-based prompt indices to actual `Tab` objects.
    ///   - spaceId: The space these tabs belong to.
    ///   - tabManager: The tab manager to mutate.
    /// - Returns: A ``TabSnapshot`` that can be passed to ``undo`` to revert all changes.
    static func apply(
        plan: TabOrganizationPlan,
        accepted: AcceptedChanges,
        tabMapping: [Int: Tab],
        spaceId: UUID,
        tabManager: TabManager
    ) -> TabSnapshot {
        // 1. Snapshot all mapped tabs before any mutations
        let allTabs = Array(tabMapping.values)
        let preSnapshot = snapshot(tabs: allTabs)

        var closedTabs: [TabSnapshot.ClosedTabState] = []
        var createdFolderIds: [UUID] = []

        // 2. Apply groups — create regular folders and move tabs into them
        for group in plan.groups where accepted.acceptedGroupIds.contains(group.id) {
            let folder = tabManager.createRegularFolder(for: spaceId, name: group.name)
            createdFolderIds.append(folder.id)
            log.debug("Created regular folder '\(group.name)' for \(group.tabs.count) tabs")

            for tabIndex in group.tabs {
                guard let tab = tabMapping[tabIndex] else { continue }
                tabManager.moveTabToRegularFolder(tab: tab, folderId: folder.id)
            }
        }

        // 3. Apply renames — set displayNameOverride on each tab
        for rename in plan.renames where accepted.acceptedRenameIds.contains(rename.id) {
            guard let tab = tabMapping[rename.tab] else {
                log.warning("Rename: no tab at index \(rename.tab)")
                continue
            }
            tab.displayNameOverride = rename.name
            log.debug("Renamed tab \(rename.tab) to '\(rename.name)'")
        }

        // 4. Apply duplicate removal — unpin if needed, then remove
        for dupSet in plan.duplicates where accepted.acceptedDuplicateIds.contains(dupSet.id) {
            for tabIndex in dupSet.close {
                guard let tab = tabMapping[tabIndex] else {
                    log.warning("Duplicate close: no tab at index \(tabIndex)")
                    continue
                }

                // Record state for undo before removal
                closedTabs.append(TabSnapshot.ClosedTabState(
                    tabId: tab.id,
                    url: tab.url,
                    name: tab.name,
                    spaceId: tab.spaceId,
                    folderId: tab.folderId,
                    index: tab.index,
                    isPinned: tab.isPinned,
                    isSpacePinned: tab.isSpacePinned,
                    displayNameOverride: tab.displayNameOverride
                ))

                // Unpin before removing to ensure clean removal
                if tab.isPinned {
                    tabManager.unpinTab(tab)
                } else if tab.isSpacePinned {
                    tabManager.unpinTabFromSpace(tab)
                }

                tabManager.removeTab(tab.id)
                log.debug("Removed duplicate tab \(tabIndex) (id: \(tab.id))")
            }
        }

        // 5. Apply sort order — only if groups didn't already reorder
        if accepted.applySortOrder, let sortOrder = plan.sort, !sortOrder.isEmpty, plan.groups.isEmpty {
            for (newIndex, tabPromptIndex) in sortOrder.enumerated() {
                guard let tab = tabMapping[tabPromptIndex] else {
                    log.warning("Sort: no tab at index \(tabPromptIndex)")
                    continue
                }
                tab.index = newIndex
            }
            log.debug("Applied sort order for \(sortOrder.count) tabs")
            tabManager.persistSnapshot()
        }

        // Build final snapshot with created folders and closed tabs info
        // Persist all changes at once
        tabManager.persistSnapshot()

        return TabSnapshot(
            tabStates: preSnapshot.tabStates,
            createdFolderIds: createdFolderIds,
            closedTabs: closedTabs
        )
    }

    // MARK: - Undo

    /// Restore the tab state captured by a previous ``apply`` call.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot returned by ``apply``.
    ///   - spaceId: The space being restored.
    ///   - tabManager: The tab manager to mutate.
    static func undo(
        snapshot: TabSnapshot,
        spaceId: UUID,
        tabManager: TabManager
    ) {
        // 1. Delete folders that were created during apply
        for folderId in snapshot.createdFolderIds {
            tabManager.deleteFolder(folderId)
            log.debug("Undo: deleted folder \(folderId)")
        }

        // 2. Restore tab states (position, pins, displayNameOverride)
        let allCurrentTabs = tabManager.allTabs()
        let tabLookup = Dictionary(allCurrentTabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for state in snapshot.tabStates {
            guard let tab = tabLookup[state.tabId] else {
                log.debug("Undo: tab \(state.tabId) not found, may have been closed")
                continue
            }

            tab.spaceId = state.spaceId
            tab.folderId = state.folderId
            tab.index = state.index
            tab.isPinned = state.isPinned
            tab.isSpacePinned = state.isSpacePinned
            tab.displayNameOverride = state.displayNameOverride
        }

        // 3. Recreate closed tabs (duplicates that were removed)
        for closed in snapshot.closedTabs {
            let tab = Tab(
                id: closed.tabId,
                url: closed.url,
                name: closed.name,
                spaceId: closed.spaceId,
                index: closed.index
            )
            tab.isPinned = closed.isPinned
            tab.isSpacePinned = closed.isSpacePinned
            tab.folderId = closed.folderId
            tab.displayNameOverride = closed.displayNameOverride

            tabManager.addTab(tab)
            log.debug("Undo: recreated tab '\(closed.name)' (\(closed.tabId))")
        }

        // 4. Persist the restored state
        tabManager.persistSnapshot()
        log.info("Undo complete: restored \(snapshot.tabStates.count) tabs, recreated \(snapshot.closedTabs.count) closed tabs, deleted \(snapshot.createdFolderIds.count) folders")
    }
}
