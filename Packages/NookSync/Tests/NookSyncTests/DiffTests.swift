// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

struct DiffTests {
    let spaceID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)
    let now = Date(timeIntervalSince1970: 9_000)

    var space: SpaceRecord {
        SpaceRecord(id: spaceID, name: "Personal", icon: "house", accentHex: "#7C7C7C",
                    order: OrderKey("V"), modifiedAt: t0)
    }

    func pinnedTab(_ id: UUID, modifiedAt: Date, parent: Parent? = nil, deletedAt: Date? = nil) -> Item {
        Item(id: id, parent: parent ?? .pinned(spaceID: spaceID), order: OrderKey("V"),
             kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "T"),
             modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    func snapshot(spaces: [SpaceRecord] = [], items: [Item] = []) -> SyncSnapshot {
        var s = SyncSnapshot()
        for sp in spaces { s.spaces[sp.id] = sp }
        for it in items { s.items[it.id] = it }
        return s
    }

    @Test func newRowsUpsert() {
        let id = UUID()
        let tree = TabTree(spaces: [space], items: [pinnedTab(id, modifiedAt: t0)])
        let changes = SyncDiff.changes(tree: tree, snapshot: SyncSnapshot(), now: now)
        #expect(changes.upsertSpaces.map(\.id) == [spaceID])
        #expect(changes.upsertItems.map(\.id) == [id])
        #expect(changes.deleteIDs.isEmpty)
    }

    @Test func unchangedRowsSilent() {
        let id = UUID()
        let item = pinnedTab(id, modifiedAt: t0)
        let tree = TabTree(spaces: [space], items: [item])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [item]), now: now)
        #expect(changes.isEmpty)
    }

    @Test func editedRowUpserts() {
        let id = UUID()
        let old = pinnedTab(id, modifiedAt: t0)
        var edited = old
        edited.customTitle = "Renamed"
        edited.modifiedAt = now
        let tree = TabTree(spaces: [space], items: [edited])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [old]), now: now)
        #expect(changes.upsertItems == [edited])
    }

    @Test func deviceScopeItemsNeverUpsert() {
        let id = UUID()
        let tree = TabTree(spaces: [space], items: [pinnedTab(id, modifiedAt: t0, parent: .tabs(spaceID: spaceID))])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space]), now: now)
        #expect(changes.upsertItems.isEmpty)
    }

    @Test func scopeExitEmitsTombstoneExactlyOnce() {
        let id = UUID()
        let pinned = pinnedTab(id, modifiedAt: t0)
        let moved = pinnedTab(id, modifiedAt: t0, parent: .tabs(spaceID: spaceID))
        let tree = TabTree(spaces: [space], items: [moved])
        var snap = snapshot(spaces: [space], items: [pinned])

        let first = SyncDiff.changes(tree: tree, snapshot: snap, now: now)
        #expect(first.upsertItems.count == 1)
        let tombstone = first.upsertItems[0]
        #expect(tombstone.id == id)
        #expect(tombstone.deletedAt == now)
        #expect(tombstone.modifiedAt == now)

        snap.items[id] = tombstone
        let second = SyncDiff.changes(tree: tree, snapshot: snap, now: now)
        #expect(second.isEmpty)
    }

    @Test func unresolvedSectionHeldBack() {
        let id = UUID()
        let pinned = pinnedTab(id, modifiedAt: t0)
        let orphaned = pinnedTab(id, modifiedAt: t0, parent: .folder(itemID: UUID()))
        let tree = TabTree(spaces: [space], items: [orphaned])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [pinned]), now: now)
        #expect(changes.isEmpty)
    }

    @Test func localTombstoneStillUpserts() {
        let id = UUID()
        let live = pinnedTab(id, modifiedAt: t0)
        let dead = pinnedTab(id, modifiedAt: now, deletedAt: now)
        let tree = TabTree(spaces: [space], items: [dead])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [live]), now: now)
        #expect(changes.upsertItems == [dead])
    }

    @Test func purgedRowsEmitDeletes() {
        let itemID = UUID()
        let deadSpaceID = UUID()
        var deadSpace = space
        let tree = TabTree(spaces: [space])
        deadSpace = SpaceRecord(id: deadSpaceID, name: "Gone", icon: "house", accentHex: "#000000",
                                order: OrderKey("X"), modifiedAt: t0, deletedAt: t0)
        let snap = snapshot(spaces: [space, deadSpace], items: [pinnedTab(itemID, modifiedAt: t0, deletedAt: t0)])
        let changes = SyncDiff.changes(tree: tree, snapshot: snap, now: now)
        #expect(Set(changes.deleteIDs) == [itemID, deadSpaceID])
        #expect(changes.upsertItems.isEmpty)
    }

    @Test func snapshotRoundTripsThroughDisk() throws {
        let id = UUID()
        var snap = snapshot(spaces: [space], items: [pinnedTab(id, modifiedAt: t0)])
        snap.systemFields[id] = Data([1, 2, 3])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nooksync-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snap.save(to: url)
        #expect(SyncSnapshot.load(from: url) == snap)
    }

    @Test func missingSnapshotLoadsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nooksync-absent-\(UUID().uuidString).json")
        #expect(SyncSnapshot.load(from: url) == SyncSnapshot())
    }
}

extension DiffTests {
    /// Relaunch mid-first-fetch, or a folder record that never decodes: the
    /// loader's repair drops the orphan into the tabs section. Nobody moved it,
    /// so no tombstone may go out and delete it on every other Mac.
    @Test func orphanEjectedByRepairIsHeldNotTombstoned() {
        let id = UUID()
        let neverArrived = UUID()
        let underFolder = pinnedTab(id, modifiedAt: t0, parent: .folder(itemID: neverArrived))
        let ejected = pinnedTab(id, modifiedAt: now, parent: .tabs(spaceID: spaceID))
        let tree = TabTree(spaces: [space], items: [ejected])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [underFolder]), now: now)
        #expect(changes.isEmpty)
    }

    @Test func folderMovedOutOfPinnedTombstonesFolderAndChildren() {
        let folderID = UUID()
        let childID = UUID()
        let pinnedFolder = Item(id: folderID, parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                                kind: .folder, modifiedAt: t0)
        let child = pinnedTab(childID, modifiedAt: t0, parent: .folder(itemID: folderID))
        var movedFolder = pinnedFolder
        movedFolder.parent = .tabs(spaceID: spaceID)
        let tree = TabTree(spaces: [space], items: [movedFolder, child])
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot(spaces: [space], items: [pinnedFolder, child]), now: now)
        #expect(Set(changes.upsertItems.map(\.id)) == [folderID, childID])
        #expect(changes.upsertItems.allSatisfy { $0.deletedAt == now })
    }
}
