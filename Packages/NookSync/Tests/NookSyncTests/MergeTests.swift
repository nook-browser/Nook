// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

struct MergeTests {
    let spaceID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    let t2 = Date(timeIntervalSince1970: 3_000)

    func space(_ id: UUID? = nil, name: String = "Personal", modifiedAt: Date? = nil) -> SpaceRecord {
        SpaceRecord(id: id ?? spaceID, name: name, icon: "house", accentHex: "#7C7C7C",
                    order: OrderKey("V"), modifiedAt: modifiedAt ?? t0)
    }

    func pinnedTab(_ id: UUID, title: String = "Tab", modifiedAt: Date, deletedAt: Date? = nil,
                   parent: Parent? = nil) -> Item {
        Item(id: id, parent: parent ?? .pinned(spaceID: spaceID), order: OrderKey("V"),
             kind: .tab(url: URL(string: "https://example.com")!, pageTitle: title),
             modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    @Test func remoteNewerWins() {
        let tree = TabTree(spaces: [space(name: "Old", modifiedAt: t0)])
        let remote = RemoteBatch(spaces: [space(name: "New", modifiedAt: t1)], items: [], deletions: [])
        let (merged, changed) = SyncMerge.merge(remote, into: tree)
        #expect(merged.space(spaceID)?.name == "New")
        #expect(changed)
    }

    @Test func localNewerWins() {
        let tree = TabTree(spaces: [space(name: "Local", modifiedAt: t1)])
        let remote = RemoteBatch(spaces: [space(name: "Stale", modifiedAt: t0)], items: [], deletions: [])
        let (merged, changed) = SyncMerge.merge(remote, into: tree)
        #expect(merged.space(spaceID)?.name == "Local")
        #expect(!changed)
    }

    @Test func tieRemoteWins() {
        let tree = TabTree(spaces: [space(name: "Local", modifiedAt: t1)])
        let remote = RemoteBatch(spaces: [space(name: "Server", modifiedAt: t1)], items: [], deletions: [])
        let (merged, _) = SyncMerge.merge(remote, into: tree)
        #expect(merged.space(spaceID)?.name == "Server")
    }

    @Test func deleteVsEditSettledByTimestamp() {
        let id = UUID()
        let live = TabTree(spaces: [space()], items: [pinnedTab(id, modifiedAt: t1)])
        let newerTombstone = RemoteBatch(spaces: [], items: [pinnedTab(id, modifiedAt: t2, deletedAt: t2)], deletions: [])
        let (afterDelete, _) = SyncMerge.merge(newerTombstone, into: live)
        #expect(afterDelete.item(id) == nil)
        #expect(afterDelete.items[id]?.deletedAt != nil)

        let edited = TabTree(spaces: [space()], items: [pinnedTab(id, title: "Edited", modifiedAt: t2)])
        let olderTombstone = RemoteBatch(spaces: [], items: [pinnedTab(id, modifiedAt: t1, deletedAt: t1)], deletions: [])
        let (afterStale, _) = SyncMerge.merge(olderTombstone, into: edited)
        #expect(afterStale.item(id)?.pageTitle == "Edited")
    }

    @Test func deviceScopeItemNeverResurrected() {
        let id = UUID()
        let deviceTab = pinnedTab(id, modifiedAt: t0, parent: .tabs(spaceID: spaceID))
        let tree = TabTree(spaces: [space()], items: [deviceTab])
        let remote = RemoteBatch(spaces: [], items: [pinnedTab(id, modifiedAt: t2)], deletions: [])
        let (merged, changed) = SyncMerge.merge(remote, into: tree)
        #expect(merged.item(id)?.parent == .tabs(spaceID: spaceID))
        #expect(!changed)
    }

    @Test func orphanKeptUntilRepair() {
        let childID = UUID()
        let missingFolder = UUID()
        let tree = TabTree(spaces: [space()])
        let remote = RemoteBatch(spaces: [],
                                 items: [pinnedTab(childID, modifiedAt: t1, parent: .folder(itemID: missingFolder))],
                                 deletions: [])
        var (merged, _) = SyncMerge.merge(remote, into: tree)
        #expect(merged.items[childID] != nil)
        #expect(merged.section(of: childID) == nil)
        merged.repair()
        #expect(merged.section(of: childID) != nil)
    }

    @Test func partialBatchFolderArrivesSecond() {
        let folderID = UUID()
        let childID = UUID()
        let tree = TabTree(spaces: [space()])
        let batch1 = RemoteBatch(spaces: [],
                                 items: [pinnedTab(childID, modifiedAt: t1, parent: .folder(itemID: folderID))],
                                 deletions: [])
        let (mid, _) = SyncMerge.merge(batch1, into: tree)
        let folder = Item(id: folderID, parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                          kind: .folder, modifiedAt: t1)
        let batch2 = RemoteBatch(spaces: [], items: [folder], deletions: [])
        var (merged, _) = SyncMerge.merge(batch2, into: mid)
        merged.repair()
        #expect(merged.section(of: childID) == .pinned(spaceID: spaceID))
        #expect(merged.item(childID)?.parent == .folder(itemID: folderID))
        #expect(merged.scope(of: childID) == .synced)
    }

    @Test func firstSyncUnion() {
        let otherSpace = UUID()
        let tree = TabTree(spaces: [space()])
        let remote = RemoteBatch(spaces: [space(otherSpace, name: "Work", modifiedAt: t1)], items: [], deletions: [])
        let (merged, _) = SyncMerge.merge(remote, into: tree)
        #expect(merged.space(spaceID) != nil)
        #expect(merged.space(otherSpace) != nil)
    }

    @Test func remoteDeletionRemovesTombstoneOnly() {
        let deadID = UUID()
        let liveID = UUID()
        let tree = TabTree(spaces: [space()],
                           items: [pinnedTab(deadID, modifiedAt: t0, deletedAt: t0),
                                   pinnedTab(liveID, modifiedAt: t1)])
        let remote = RemoteBatch(spaces: [], items: [], deletions: [deadID, liveID])
        let (merged, _) = SyncMerge.merge(remote, into: tree)
        #expect(merged.items[deadID] == nil)
        #expect(merged.item(liveID) != nil)
    }
}

extension MergeTests {
    @Test func changeFromToReachesTargetIncludingRemovals() {
        let keepID = UUID()
        let goneID = UUID()
        let newID = UUID()
        let current = TabTree(spaces: [space(name: "Old", modifiedAt: t0)],
                              items: [pinnedTab(keepID, title: "Keep", modifiedAt: t0),
                                      pinnedTab(goneID, title: "Gone", modifiedAt: t0)])
        var edited = pinnedTab(keepID, title: "Keep", modifiedAt: t1)
        edited.customTitle = "Renamed"
        let target = TabTree(spaces: [space(name: "New", modifiedAt: t1)],
                             items: [edited, pinnedTab(newID, title: "New", modifiedAt: t1)])
        let change = SyncMerge.change(from: current, to: target)
        var applied = current
        _ = applied.apply(change)
        #expect(applied.spaces == target.spaces)
        #expect(applied.items == target.items)
        #expect(applied.items[goneID] == nil)
    }

    @Test func changeFromIdenticalTreesIsEmpty() {
        let tree = TabTree(spaces: [space()], items: [pinnedTab(UUID(), modifiedAt: t0)])
        #expect(SyncMerge.change(from: tree, to: tree).isEmpty)
    }
}
