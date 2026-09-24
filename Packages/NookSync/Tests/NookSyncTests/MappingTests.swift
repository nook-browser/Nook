// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import Testing
import NookTabsCore
@testable import NookSync

struct MappingTests {
    let spaceID = UUID()

    @Test func spaceRoundTrip() {
        let space = SpaceRecord(name: "Work", icon: "house", accentHex: "#112233",
                                order: OrderKey("V"), modifiedAt: Date(timeIntervalSince1970: 100))
        let record = RecordMapper.record(for: space, base: nil)
        #expect(record.recordType == SyncRecordType.space)
        #expect(record.recordID.recordName == space.id.uuidString)
        #expect(RecordMapper.space(from: record) == space)
    }

    @Test func spaceTombstoneRoundTrip() {
        let space = SpaceRecord(name: "Old", icon: "house", accentHex: "#000000",
                                order: OrderKey("V"), modifiedAt: Date(timeIntervalSince1970: 200),
                                deletedAt: Date(timeIntervalSince1970: 300))
        let back = RecordMapper.space(from: RecordMapper.record(for: space, base: nil))
        #expect(back == space)
    }

    @Test func itemRoundTripPinnedTab() {
        let item = Item(parent: .pinned(spaceID: spaceID), order: OrderKey("K"),
                        kind: .tab(url: URL(string: "https://example.com/a?b=1")!, pageTitle: "Example"),
                        customTitle: "Mine",
                        modifiedAt: Date(timeIntervalSince1970: 400),
                        deletedAt: Date(timeIntervalSince1970: 500))
        let record = RecordMapper.record(for: item, base: nil)
        #expect(record != nil)
        #expect(RecordMapper.item(from: record!) == item)
    }

    @Test func folderRoundTrip() {
        let folder = Item(parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                          kind: .folder, customTitle: "Stuff",
                          modifiedAt: Date(timeIntervalSince1970: 600))
        let record = RecordMapper.record(for: folder, base: nil)
        #expect(record != nil)
        #expect(RecordMapper.item(from: record!) == folder)
    }

    @Test func nestedFolderParentRoundTrip() {
        let folderID = UUID()
        let item = Item(parent: .folder(itemID: folderID), order: OrderKey("V"),
                        kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "In folder"),
                        modifiedAt: Date(timeIntervalSince1970: 700))
        let back = RecordMapper.item(from: RecordMapper.record(for: item, base: nil)!)
        #expect(back?.parent == .folder(itemID: folderID))
    }

    @Test func tabsParentDoesNotMap() {
        let item = Item(parent: .tabs(spaceID: spaceID), order: OrderKey("V"),
                        kind: .tab(url: URL(string: "https://a.example")!, pageTitle: "A"))
        #expect(RecordMapper.record(for: item, base: nil) == nil)
    }

    @Test func malformedRecordsSkipped() {
        let badName = CKRecord(recordType: SyncRecordType.space,
                               recordID: .init(recordName: "not-a-uuid", zoneID: RecordMapper.zoneID))
        badName["accentHex"] = "#112233"
        badName["order"] = "V"
        badName["modifiedAt"] = Date()
        #expect(RecordMapper.space(from: badName) == nil)

        let goodItem = Item(parent: .pinned(spaceID: spaceID), order: OrderKey("V"),
                            kind: .tab(url: URL(string: "https://example.com")!, pageTitle: "T"),
                            modifiedAt: Date(timeIntervalSince1970: 800))
        let badParent = RecordMapper.record(for: goodItem, base: nil)!
        badParent["parent"] = "garbage"
        #expect(RecordMapper.item(from: badParent) == nil)

        let noURL = RecordMapper.record(for: goodItem, base: nil)!
        noURL.encryptedValues["url"] = nil
        #expect(RecordMapper.item(from: noURL) == nil)

        let wrongType = CKRecord(recordType: "SomethingNew",
                                 recordID: RecordMapper.recordID(UUID()))
        #expect(RecordMapper.space(from: wrongType) == nil)
        #expect(RecordMapper.item(from: wrongType) == nil)
    }

    @Test func unknownFieldsIgnored() {
        let space = SpaceRecord(name: "Work", icon: "house", accentHex: "#112233",
                                order: OrderKey("V"), modifiedAt: Date(timeIntervalSince1970: 900))
        let record = RecordMapper.record(for: space, base: nil)
        record["futureField"] = "whatever"
        #expect(RecordMapper.space(from: record) == space)
    }

    @Test func baseRecordReused() {
        let space = SpaceRecord(name: "Work", icon: "house", accentHex: "#112233",
                                order: OrderKey("V"), modifiedAt: Date(timeIntervalSince1970: 1000))
        let original = RecordMapper.record(for: space, base: nil)
        var renamed = space
        renamed.name = "Play"
        let updated = RecordMapper.record(for: renamed, base: original)
        #expect(updated === original)
        #expect(RecordMapper.space(from: updated) == renamed)
    }
}
