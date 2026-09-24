// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

/// Server copies reach the engine two ways: fetched, or handed back by a save
/// conflict. Both go through SyncSnapshot.absorb, then LWW merge, then a diff.
struct IngestTests {
    let spaceID = UUID()
    let ownDevice = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    let t2 = Date(timeIntervalSince1970: 3_000)

    var space: SpaceRecord {
        SpaceRecord(id: spaceID, name: "Personal", icon: "house", accentHex: "#7C7C7C",
                    order: OrderKey("V"), modifiedAt: t0)
    }

    func pinnedTab(_ id: UUID, title: String, modifiedAt: Date, deletedAt: Date? = nil) -> Item {
        Item(id: id, parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
             kind: .tab(url: URL(string: "https://example.com")!, pageTitle: title),
             modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    /// The engine's sequence for one server record, minus CloudKit transport.
    func resolve(server: CKRecord, tree: TabTree, snapshot: inout SyncSnapshot) -> TabTree {
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        _ = snapshot.absorb(server, into: &batch)
        return SyncMerge.merge(batch, into: tree).tree
    }

    @Test func conflictWithNewerServerTakesServerAndUploadsNothing() {
        let id = UUID()
        let local = pinnedTab(id, title: "Stale", modifiedAt: t1)
        let server = pinnedTab(id, title: "Fresh", modifiedAt: t2)
        var snapshot = SyncSnapshot()
        let tree = resolve(server: RecordMapper.record(for: server, base: nil)!,
                           tree: TabTree(spaces: [space], items: [local]), snapshot: &snapshot)
        #expect(tree.item(id)?.pageTitle == "Fresh")
        #expect(SyncDiff.changes(tree: tree, snapshot: snapshot).upsertItems.isEmpty)
        #expect(snapshot.systemFields[id] != nil)
    }

    @Test func conflictWithNewerLocalReuploadsLocal() {
        let id = UUID()
        let local = pinnedTab(id, title: "Mine", modifiedAt: t2)
        let server = pinnedTab(id, title: "Theirs", modifiedAt: t1)
        var snapshot = SyncSnapshot()
        let tree = resolve(server: RecordMapper.record(for: server, base: nil)!,
                           tree: TabTree(spaces: [space], items: [local]), snapshot: &snapshot)
        #expect(tree.item(id)?.pageTitle == "Mine")
        #expect(SyncDiff.changes(tree: tree, snapshot: snapshot).upsertItems == [local])
    }

    @Test func staleLiveRowNeverOverwritesNewerServerTombstone() {
        let id = UUID()
        let local = pinnedTab(id, title: "Old", modifiedAt: t1)
        let tombstone = pinnedTab(id, title: "Old", modifiedAt: t2, deletedAt: t2)
        var snapshot = SyncSnapshot()
        let tree = resolve(server: RecordMapper.record(for: tombstone, base: nil)!,
                           tree: TabTree(spaces: [space], items: [local]), snapshot: &snapshot)
        #expect(tree.item(id) == nil)
        #expect(SyncDiff.changes(tree: tree, snapshot: snapshot).upsertItems.isEmpty)
    }

    @Test func malformedRecordIsRejected() {
        var snapshot = SyncSnapshot()
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        let junk = CKRecord(recordType: SyncRecordType.item,
                            recordID: .init(recordName: "not-a-uuid", zoneID: RecordMapper.zoneID))
        #expect(!snapshot.absorb(junk, into: &batch))
        #expect(batch.isEmpty)
    }

    // MARK: - Devices

    func deviceRecord(_ id: UUID, name: String, lastSeen: Date) -> CKRecord {
        let payload = DeviceTabsPayload(deviceID: id, name: name, lastSeen: lastSeen,
                                        tabs: [.init(url: URL(string: "https://a.example")!, title: "A", spaceID: spaceID)])
        return DeviceTabs.record(for: payload, base: nil)
    }

    @Test func devicesSurviveASnapshotRoundTrip() throws {
        let other = UUID()
        var snapshot = SyncSnapshot()
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        #expect(snapshot.absorb(deviceRecord(other, name: "Studio", lastSeen: t1), into: &batch))
        #expect(batch.isEmpty)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nooksync-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.save(to: url)
        let reloaded = SyncSnapshot.load(from: url)
        #expect(reloaded.otherDevices(excluding: ownDevice, now: t1).map(\.name) == ["Studio"])
    }

    @Test func otherDevicesExcludesSelfAndStaleNewestFirst() {
        var snapshot = SyncSnapshot()
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        let now = Date(timeIntervalSince1970: 100 * 24 * 60 * 60)
        let day: TimeInterval = 24 * 60 * 60
        _ = snapshot.absorb(deviceRecord(ownDevice, name: "Self", lastSeen: now), into: &batch)
        _ = snapshot.absorb(deviceRecord(UUID(), name: "Older", lastSeen: now - 2 * day), into: &batch)
        _ = snapshot.absorb(deviceRecord(UUID(), name: "Newer", lastSeen: now - day), into: &batch)
        _ = snapshot.absorb(deviceRecord(UUID(), name: "Gone", lastSeen: now - 15 * day), into: &batch)
        #expect(snapshot.otherDevices(excluding: ownDevice, now: now).map(\.name) == ["Newer", "Older"])
    }

    @Test func deletionsClearRowsAndDevices() {
        let itemID = UUID()
        let other = UUID()
        var snapshot = SyncSnapshot()
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        _ = snapshot.absorb(RecordMapper.record(for: pinnedTab(itemID, title: "T", modifiedAt: t0), base: nil)!,
                            into: &batch)
        _ = snapshot.absorb(deviceRecord(other, name: "Studio", lastSeen: t0), into: &batch)

        var deletions = RemoteBatch(spaces: [], items: [], deletions: [])
        snapshot.absorbDeletion(RecordMapper.recordID(itemID), into: &deletions)
        snapshot.absorbDeletion(.init(recordName: DeviceTabs.recordName(for: other), zoneID: RecordMapper.zoneID),
                                into: &deletions)
        #expect(deletions.deletions == [itemID])
        #expect(snapshot.items[itemID] == nil)
        #expect(snapshot.systemFields[itemID] == nil)
        #expect(snapshot.otherDevices(excluding: ownDevice, now: t0).isEmpty)
    }

    // MARK: - Zone deletion

    @Test func zoneDeletionReseedsOnlyAfterEncryptionReset() {
        #expect(SyncZoneDeletion.action(for: .encryptedDataReset) == .reseed)
        #expect(SyncZoneDeletion.action(for: .deleted) == .disable)
        #expect(SyncZoneDeletion.action(for: .purged) == .disable)
    }
}
