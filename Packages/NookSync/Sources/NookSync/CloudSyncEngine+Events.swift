// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

extension CloudSyncEngine {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine dropped by stop() can still deliver; its state is not ours.
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            saveStateSerialization(update.stateSerialization)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleFetchedDatabaseChanges(changes)
        case .fetchedRecordZoneChanges(let changes):
            absorbServerRecords(changes.modifications.map(\.record),
                                deletedIDs: changes.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let sent):
            handleSentRecordZoneChanges(sent)
        case .willFetchChanges, .willSendChanges:
            if status != .quotaExceeded { status = .syncing }
        case .didFetchChanges:
            delegate?.syncFetchDidComplete()
            if status == .syncing { status = .synced }
        case .didSendChanges:
            if status == .syncing { status = .synced }
        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty, let tree = delegate?.syncCurrentTree else { return nil }
        let snapshot = self.snapshot
        let deviceID = self.deviceID
        let deviceName = self.deviceName
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            SyncRecordProvider.record(recordName: recordID.recordName, tree: tree, snapshot: snapshot,
                                      deviceID: deviceID, deviceName: deviceName)
        }
    }

    // MARK: - Server copies

    /// Fetched records and conflict server copies both land here. The diff
    /// afterwards is what sends back any row where local won; skipping it when
    /// the merge changed nothing left the server stale until the next edit.
    func absorbServerRecords(_ records: [CKRecord], deletedIDs: [CKRecord.ID]) {
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        for record in records where !snapshot.absorb(record, into: &batch) {
            log.error("Skipped \(record.recordType, privacy: .public) record \(record.recordID.recordName, privacy: .public)")
        }
        for recordID in deletedIDs {
            snapshot.absorbDeletion(recordID, into: &batch)
        }
        saveSnapshot()
        refreshOtherDevices()
        if !batch.isEmpty {
            delegate?.syncApplyRemote(batch)
        }
        noteLocalChange()
    }

    // MARK: - Event handling

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signOut, .switchAccounts:
            log.info("iCloud account changed; sync stopped and state discarded")
            stop(discardState: true)
        case .signIn:
            break
        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in changes.deletions where deletion.zoneID == RecordMapper.zoneID {
            switch SyncZoneDeletion.action(for: deletion.reason) {
            case .reseed:
                log.info("NookSync zone reset by iCloud; re-seeding from this Mac")
                snapshot = SyncSnapshot()
                saveSnapshot()
                refreshOtherDevices()
                lastPublishedTabs = nil
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapper.zoneID))])
                noteLocalChange()
            case .disable:
                log.info("NookSync zone deleted by the user; sync turned off on this Mac")
                stop(discardState: true)
                delegate?.syncDisabledRemotely()
                return
            }
        }
    }

    private func handleSentRecordZoneChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in sent.savedRecords {
            switch record.recordType {
            case SyncRecordType.space:
                if let space = RecordMapper.space(from: record) {
                    snapshot.spaces[space.id] = space
                    snapshot.systemFields[space.id] = SyncRecordProvider.systemFields(of: record)
                }
            case SyncRecordType.item:
                if let item = RecordMapper.item(from: record) {
                    snapshot.items[item.id] = item
                    snapshot.systemFields[item.id] = SyncRecordProvider.systemFields(of: record)
                }
            case SyncRecordType.device:
                snapshot.systemFields[deviceID] = SyncRecordProvider.systemFields(of: record)
            default:
                break
            }
        }
        for deletion in sent.deletedRecordIDs {
            if let id = UUID(uuidString: deletion.recordName) {
                snapshot.spaces[id] = nil
                snapshot.items[id] = nil
                snapshot.systemFields[id] = nil
            }
        }
        saveSnapshot()
        var conflicts: [CKRecord] = []
        for failure in sent.failedRecordSaves {
            if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                conflicts.append(server)
            } else {
                handleSaveFailure(failure)
            }
        }
        guard !conflicts.isEmpty else { return }
        // The server copy goes through the same LWW as a fetch. Our own device
        // record has one writer, so its conflict only means stale system fields.
        absorbServerRecords(conflicts, deletedIDs: [])
        if conflicts.contains(where: { $0.recordID == deviceRecordID }) {
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(deviceRecordID)])
        }
    }

    private func handleSaveFailure(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let recordID = failure.record.recordID
        switch failure.error.code {
        case .zoneNotFound:
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapper.zoneID))])
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            // Deleted server-side; drop stale system fields and save fresh.
            if let id = UUID(uuidString: recordID.recordName) { snapshot.systemFields[id] = nil }
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .quotaExceeded:
            status = .quotaExceeded
            log.error("iCloud quota exceeded; sync paused")
        default:
            log.error("Save failed for \(recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
        }
    }
}
