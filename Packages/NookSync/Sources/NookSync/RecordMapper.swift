// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

public enum SyncRecordType {
    public static let space = "Space"
    public static let item = "SyncedItem"
    public static let device = "Device"
}

/// CKRecord round-tripping for the synced scope. Sensitive fields go through
/// `encryptedValues`; a record that fails any part of decoding maps to nil and
/// the caller skips it, so one bad record never aborts a batch.
public enum RecordMapper {
    public static let zoneID = CKRecordZone.ID(zoneName: "NookSync", ownerName: CKCurrentUserDefaultName)

    public static func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    // MARK: - Spaces

    public static func record(for space: SpaceRecord, base: CKRecord?) -> CKRecord {
        let record = base ?? CKRecord(recordType: SyncRecordType.space, recordID: recordID(space.id))
        record.encryptedValues["name"] = space.name
        record["icon"] = space.icon
        record["accentHex"] = space.accentHex
        record["order"] = space.order.rawValue
        record["modifiedAt"] = space.modifiedAt
        record["deletedAt"] = space.deletedAt
        return record
    }

    public static func space(from record: CKRecord) -> SpaceRecord? {
        guard record.recordType == SyncRecordType.space,
              let id = UUID(uuidString: record.recordID.recordName),
              let name = record.encryptedValues["name"] as? String,
              let accentHex = record["accentHex"] as? String,
              let order = record["order"] as? String,
              let modifiedAt = record["modifiedAt"] as? Date
        else { return nil }
        return SpaceRecord(id: id,
                           name: name,
                           icon: record["icon"] as? String ?? "house",
                           accentHex: accentHex,
                           order: OrderKey(order),
                           modifiedAt: modifiedAt,
                           deletedAt: record["deletedAt"] as? Date)
    }

    // MARK: - Items

    /// nil when the item's section never syncs (`.tabs`).
    public static func record(for item: Item, base: CKRecord?) -> CKRecord? {
        guard let parent = encodeParent(item.parent) else { return nil }
        let record = base ?? CKRecord(recordType: SyncRecordType.item, recordID: recordID(item.id))
        record["parent"] = parent
        record["order"] = item.order.rawValue
        record["modifiedAt"] = item.modifiedAt
        record["deletedAt"] = item.deletedAt
        record.encryptedValues["customTitle"] = item.customTitle
        switch item.kind {
        case .tab(let url, let pageTitle):
            record["kind"] = "tab"
            record.encryptedValues["url"] = url.absoluteString
            record.encryptedValues["pageTitle"] = pageTitle
        case .folder:
            record["kind"] = "folder"
            record.encryptedValues["url"] = nil
            record.encryptedValues["pageTitle"] = nil
        }
        return record
    }

    public static func item(from record: CKRecord) -> Item? {
        guard record.recordType == SyncRecordType.item,
              let id = UUID(uuidString: record.recordID.recordName),
              let parentRaw = record["parent"] as? String,
              let parent = decodeParent(parentRaw),
              let order = record["order"] as? String,
              let modifiedAt = record["modifiedAt"] as? Date,
              let kindRaw = record["kind"] as? String
        else { return nil }
        let kind: ItemKind
        switch kindRaw {
        case "folder":
            kind = .folder
        case "tab":
            guard let urlRaw = record.encryptedValues["url"] as? String,
                  let url = URL(string: urlRaw) else { return nil }
            kind = .tab(url: url, pageTitle: record.encryptedValues["pageTitle"] as? String ?? "")
        default:
            return nil
        }
        return Item(id: id,
                    parent: parent,
                    order: OrderKey(order),
                    kind: kind,
                    customTitle: record.encryptedValues["customTitle"] as? String,
                    modifiedAt: modifiedAt,
                    deletedAt: record["deletedAt"] as? Date)
    }

    // MARK: - Parent encoding

    public static func encodeParent(_ parent: Parent) -> String? {
        switch parent {
        case .favorites(let spaceID): return "favorites:\(spaceID.uuidString)"
        case .pinned(let spaceID): return "pinned:\(spaceID.uuidString)"
        case .folder(let itemID): return "folder:\(itemID.uuidString)"
        case .tabs: return nil
        }
    }

    public static func decodeParent(_ raw: String) -> Parent? {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "favorites": return .favorites(spaceID: id)
        case "pinned": return .pinned(spaceID: id)
        case "folder": return .folder(itemID: id)
        default: return nil
        }
    }
}
