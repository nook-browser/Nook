// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

struct RecordProviderTests {
    let spaceID = UUID()
    let deviceID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)
    let now = Date(timeIntervalSince1970: 5_000)

    var space: SpaceRecord {
        SpaceRecord(id: spaceID, name: "Personal", icon: "house", accentHex: "#7C7C7C",
                    order: OrderKey("V"), modifiedAt: t0)
    }

    func provided(_ name: String, tree: TabTree, snapshot: SyncSnapshot = SyncSnapshot()) -> CKRecord? {
        SyncRecordProvider.record(recordName: name, tree: tree, snapshot: snapshot,
                                  deviceID: deviceID, deviceName: "Studio", now: now)
    }

    @Test func spaceInTreeProvidesSpaceRecord() {
        let tree = TabTree(spaces: [space])
        let record = provided(spaceID.uuidString, tree: tree)
        #expect(record?.recordType == SyncRecordType.space)
        #expect(record.flatMap(RecordMapper.space(from:)) == space)
    }

    @Test func pinnedItemProvidesItemRecord() {
        let item = Item(parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                        kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "T"),
                        modifiedAt: t0)
        let tree = TabTree(spaces: [space], items: [item])
        let record = provided(item.id.uuidString, tree: tree)
        #expect(record.flatMap(RecordMapper.item(from:)) == item)
    }

    @Test func scopeExitedItemProvidesTombstoneFromSnapshot() {
        let id = UUID()
        let pinned = Item(id: id, parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                          kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "T"),
                          modifiedAt: t0)
        let moved = Item(id: id, parent: .tabs(spaceID: spaceID), order: OrderKey("V"),
                         kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "T"),
                         modifiedAt: t0)
        var snap = SyncSnapshot()
        snap.items[id] = pinned
        let tree = TabTree(spaces: [space], items: [moved])
        let record = provided(id.uuidString, tree: tree, snapshot: snap)
        let back = record.flatMap(RecordMapper.item(from:))
        #expect(back?.deletedAt == now)
        #expect(back?.modifiedAt == now)
    }

    @Test func unknownIDProvidesNothing() {
        let tree = TabTree(spaces: [space])
        #expect(provided(UUID().uuidString, tree: tree) == nil)
        #expect(provided("garbage", tree: tree) == nil)
    }

    @Test func ownDeviceNameProvidesDeviceRecord() {
        let tab = Item(parent: .tabs(spaceID: spaceID), order: OrderKey("V"),
                       kind: .tab(url: URL(string: "https://a.example")!, pageTitle: "A"),
                       modifiedAt: t0)
        let tree = TabTree(spaces: [space], items: [tab])
        let record = provided(DeviceTabs.recordName(for: deviceID), tree: tree)
        #expect(record?.recordType == SyncRecordType.device)
        let payload = record.flatMap(DeviceTabs.payload(from:))
        #expect(payload?.deviceID == deviceID)
        #expect(payload?.tabs.map(\.title) == ["A"])
    }

    @Test func baseComesFromArchivedSystemFields() {
        let tree = TabTree(spaces: [space])
        let original = RecordMapper.record(for: space, base: nil)
        var snap = SyncSnapshot()
        snap.systemFields[spaceID] = SyncRecordProvider.systemFields(of: original)
        let record = provided(spaceID.uuidString, tree: tree, snapshot: snap)
        #expect(record?.recordID == original.recordID)
        #expect(record.flatMap(RecordMapper.space(from:)) == space)
    }
}
