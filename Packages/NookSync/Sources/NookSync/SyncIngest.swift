// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

/// One path for every server copy, fetched or returned by a save conflict: the
/// snapshot takes it as known server state and the batch carries it to the LWW
/// merge. A conflict therefore resolves exactly like a fetch, and whichever
/// side is older loses on both paths.
extension SyncSnapshot {
    static let staleDeviceCutoff: TimeInterval = 14 * 24 * 60 * 60

    /// False for a record of ours that fails to decode, and for record types a
    /// newer Nook may add. Neither aborts the batch.
    @discardableResult
    public mutating func absorb(_ record: CKRecord, into batch: inout RemoteBatch) -> Bool {
        switch record.recordType {
        case SyncRecordType.space:
            guard let space = RecordMapper.space(from: record) else { return false }
            spaces[space.id] = space
            systemFields[space.id] = SyncRecordProvider.systemFields(of: record)
            batch.spaces.append(space)
        case SyncRecordType.item:
            guard let item = RecordMapper.item(from: record) else { return false }
            items[item.id] = item
            systemFields[item.id] = SyncRecordProvider.systemFields(of: record)
            batch.items.append(item)
        case SyncRecordType.device:
            guard let payload = DeviceTabs.payload(from: record) else { return false }
            devices[payload.deviceID] = payload
            systemFields[payload.deviceID] = SyncRecordProvider.systemFields(of: record)
        default:
            return false
        }
        return true
    }

    public mutating func absorbDeletion(_ recordID: CKRecord.ID, into batch: inout RemoteBatch) {
        let name = recordID.recordName
        if let id = UUID(uuidString: name) {
            spaces[id] = nil
            items[id] = nil
            systemFields[id] = nil
            batch.deletions.append(id)
        } else if name.hasPrefix("device-"), let id = UUID(uuidString: String(name.dropFirst("device-".count))) {
            devices[id] = nil
            systemFields[id] = nil
        }
    }

    /// Other devices seen in the last 14 days, most recent first.
    public func otherDevices(excluding ownID: UUID, now: Date = Date()) -> [DeviceTabsPayload] {
        let cutoff = now.addingTimeInterval(-Self.staleDeviceCutoff)
        return devices.values
            .filter { $0.deviceID != ownID && $0.lastSeen > cutoff }
            .sorted { $0.lastSeen > $1.lastSeen }
    }
}

/// What a remote deletion of the whole NookSync zone means for this Mac.
public enum SyncZoneDeletion: Equatable, Sendable {
    /// iCloud reset its encryption keys and dropped encrypted data; Apple
    /// requires clients to upload again.
    case reseed
    /// The user deleted the data (Nook's button on another Mac, or iCloud
    /// storage settings). Uploading it again would undo their request.
    case disable

    public static func action(for reason: CKDatabase.DatabaseChange.Deletion.Reason) -> SyncZoneDeletion {
        switch reason {
        case .encryptedDataReset: return .reseed
        case .deleted, .purged: return .disable
        @unknown default: return .disable
        }
    }
}
