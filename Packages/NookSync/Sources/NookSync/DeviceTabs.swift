// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

/// One device's open regular tabs, published read-only. Single writer per
/// record, so these never conflict.
public struct DeviceTabsPayload: Codable, Equatable, Sendable {
    public struct Tab: Codable, Equatable, Sendable {
        public var url: URL
        public var title: String
        public var spaceID: UUID

        public init(url: URL, title: String, spaceID: UUID) {
            self.url = url
            self.title = title
            self.spaceID = spaceID
        }
    }

    public var deviceID: UUID
    public var name: String
    public var lastSeen: Date
    public var tabs: [Tab]

    public init(deviceID: UUID, name: String, lastSeen: Date, tabs: [Tab]) {
        self.deviceID = deviceID
        self.name = name
        self.lastSeen = lastSeen
        self.tabs = tabs
    }
}

public enum DeviceTabs {
    public static func recordName(for deviceID: UUID) -> String { "device-\(deviceID.uuidString)" }

    /// Live tabs-section tabs across all spaces, space order then row order,
    /// folder contents in place. Pinned, favorites and tombstones never appear.
    public static func payload(tree: TabTree, deviceID: UUID, name: String, now: Date = Date()) -> DeviceTabsPayload {
        var tabs: [DeviceTabsPayload.Tab] = []
        for space in tree.orderedSpaces {
            collect(tree: tree, parent: .tabs(spaceID: space.id), spaceID: space.id, into: &tabs)
        }
        return DeviceTabsPayload(deviceID: deviceID, name: name, lastSeen: now, tabs: tabs)
    }

    private static func collect(tree: TabTree, parent: Parent, spaceID: UUID,
                                into tabs: inout [DeviceTabsPayload.Tab]) {
        for child in tree.children(of: parent) {
            switch child.kind {
            case .tab(let url, let pageTitle):
                tabs.append(.init(url: url, title: child.displayTitle.isEmpty ? pageTitle : child.displayTitle,
                                  spaceID: spaceID))
            case .folder:
                collect(tree: tree, parent: .folder(itemID: child.id), spaceID: spaceID, into: &tabs)
            }
        }
    }

    // MARK: - Record mapping

    public static func record(for payload: DeviceTabsPayload, base: CKRecord?) -> CKRecord {
        let id = CKRecord.ID(recordName: recordName(for: payload.deviceID), zoneID: RecordMapper.zoneID)
        let record = base ?? CKRecord(recordType: SyncRecordType.device, recordID: id)
        record["deviceID"] = payload.deviceID.uuidString
        record["lastSeen"] = payload.lastSeen
        record.encryptedValues["payload"] = try? JSONEncoder().encode(payload)
        return record
    }

    public static func payload(from record: CKRecord) -> DeviceTabsPayload? {
        guard record.recordType == SyncRecordType.device,
              let data = record.encryptedValues["payload"] as? Data,
              let payload = try? JSONDecoder().decode(DeviceTabsPayload.self, from: data)
        else { return nil }
        return payload
    }
}
