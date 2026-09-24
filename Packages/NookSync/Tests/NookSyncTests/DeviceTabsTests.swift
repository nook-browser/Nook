// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

struct DeviceTabsTests {
    let spaceA = UUID()
    let spaceB = UUID()
    let deviceID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)

    func makeTree() -> TabTree {
        let spaces = [
            SpaceRecord(id: spaceA, name: "A", icon: "house", accentHex: "#111111",
                        order: OrderKey("H"), modifiedAt: t0),
            SpaceRecord(id: spaceB, name: "B", icon: "house", accentHex: "#222222",
                        order: OrderKey("V"), modifiedAt: t0),
        ]
        let folderID = UUID()
        let items = [
            Item(parent: .pinned(spaceID: spaceA), order: OrderKey("V"),
                 kind: .tab(url: URL(string: "https://pinned.example")!, pageTitle: "Pinned"), modifiedAt: t0),
            Item(parent: .tabs(spaceID: spaceA), order: OrderKey("H"),
                 kind: .tab(url: URL(string: "https://a1.example")!, pageTitle: "A1"), modifiedAt: t0),
            Item(id: folderID, parent: .tabs(spaceID: spaceA), order: OrderKey("V"),
                 kind: .folder, customTitle: "F", modifiedAt: t0),
            Item(parent: .folder(itemID: folderID), order: OrderKey("V"),
                 kind: .tab(url: URL(string: "https://a2.example")!, pageTitle: "A2"), modifiedAt: t0),
            Item(parent: .tabs(spaceID: spaceB), order: OrderKey("V"),
                 kind: .tab(url: URL(string: "https://b1.example")!, pageTitle: "B1"), modifiedAt: t0),
            Item(parent: .tabs(spaceID: spaceB), order: OrderKey("k"),
                 kind: .tab(url: URL(string: "https://dead.example")!, pageTitle: "Dead"),
                 modifiedAt: t0, deletedAt: t0),
        ]
        return TabTree(spaces: spaces, items: items)
    }

    @Test func payloadCollectsDeviceTabsOnly() {
        let payload = DeviceTabs.payload(tree: makeTree(), deviceID: deviceID, name: "Studio", now: t0)
        #expect(payload.deviceID == deviceID)
        #expect(payload.name == "Studio")
        #expect(payload.lastSeen == t0)
        #expect(payload.tabs.map(\.title) == ["A1", "A2", "B1"])
        #expect(payload.tabs.map(\.spaceID) == [spaceA, spaceA, spaceB])
    }

    @Test func recordRoundTrip() {
        let payload = DeviceTabs.payload(tree: makeTree(), deviceID: deviceID, name: "Studio", now: t0)
        let record = DeviceTabs.record(for: payload, base: nil)
        #expect(record.recordType == SyncRecordType.device)
        #expect(record.recordID.recordName == "device-\(deviceID.uuidString)")
        #expect(DeviceTabs.payload(from: record) == payload)
    }

    @Test func malformedPayloadSkipped() {
        let record = CKRecord(recordType: SyncRecordType.device,
                              recordID: .init(recordName: "device-x", zoneID: RecordMapper.zoneID))
        record.encryptedValues["payload"] = "not json".data(using: .utf8)
        record["lastSeen"] = Date()
        #expect(DeviceTabs.payload(from: record) == nil)
    }
}
