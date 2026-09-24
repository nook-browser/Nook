// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

/// Builds the CKRecord for a pending save at send time, from the tree as it is
/// then. A row that left the synced scope since it was enqueued resolves to a
/// tombstone from the snapshot; a row gone from both resolves to nothing.
public enum SyncRecordProvider {
    public static func record(recordName: String, tree: TabTree, snapshot: SyncSnapshot,
                              deviceID: UUID, deviceName: String, now: Date = Date()) -> CKRecord? {
        if recordName == DeviceTabs.recordName(for: deviceID) {
            let payload = DeviceTabs.payload(tree: tree, deviceID: deviceID, name: deviceName, now: now)
            return DeviceTabs.record(for: payload, base: base(snapshot.systemFields[deviceID]))
        }
        guard let id = UUID(uuidString: recordName) else { return nil }
        if let space = tree.spaces[id] {
            return RecordMapper.record(for: space, base: base(snapshot.systemFields[id]))
        }
        if let item = tree.items[id] {
            switch tree.section(of: id) {
            case .favorites, .pinned, nil:
                return RecordMapper.record(for: item, base: base(snapshot.systemFields[id]))
            case .tabs, .folder:
                break // fell out of the synced scope; tombstone below
            }
        }
        if var row = snapshot.items[id] {
            row.deletedAt = now
            row.modifiedAt = now
            return RecordMapper.record(for: row, base: base(snapshot.systemFields[id]))
        }
        if var row = snapshot.spaces[id] {
            row.deletedAt = row.deletedAt ?? now
            row.modifiedAt = now
            return RecordMapper.record(for: row, base: base(snapshot.systemFields[id]))
        }
        return nil
    }

    // MARK: - System fields

    public static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func base(_ data: Data?) -> CKRecord? {
        guard let data,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }
}
