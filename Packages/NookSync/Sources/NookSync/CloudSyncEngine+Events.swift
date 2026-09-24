// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import NookTabsCore

extension CloudSyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveStateSerialization(update.stateSerialization)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleFetchedDatabaseChanges(changes)
        case .fetchedRecordZoneChanges(let changes):
            handleFetchedRecordZoneChanges(changes)
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
            // The zone was purged server-side. Reset and re-seed from local.
            log.info("NookSync zone deleted remotely; re-seeding")
            snapshot = SyncSnapshot()
            saveSnapshot()
            otherDevices = []
            lastPublishedTabs = nil
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapper.zoneID))])
            noteLocalChange()
        }
    }

    private func handleFetchedRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var batch = RemoteBatch(spaces: [], items: [], deletions: [])
        for modification in changes.modifications {
            let record = modification.record
            switch record.recordType {
            case SyncRecordType.space:
                guard let space = RecordMapper.space(from: record) else {
                    log.error("Skipped malformed Space record \(record.recordID.recordName, privacy: .public)")
                    continue
                }
                batch.spaces.append(space)
                snapshot.spaces[space.id] = space
                snapshot.systemFields[space.id] = SyncRecordProvider.systemFields(of: record)
            case SyncRecordType.item:
                guard let item = RecordMapper.item(from: record) else {
                    log.error("Skipped malformed SyncedItem record \(record.recordID.recordName, privacy: .public)")
                    continue
                }
                batch.items.append(item)
                snapshot.items[item.id] = item
                snapshot.systemFields[item.id] = SyncRecordProvider.systemFields(of: record)
            case SyncRecordType.device:
                if let payload = DeviceTabs.payload(from: record) {
                    absorbDevicePayload(payload)
                    snapshot.systemFields[payload.deviceID] = SyncRecordProvider.systemFields(of: record)
                }
            default:
                break // A newer Nook's record type; skipping keeps coexistence.
            }
        }
        for deletion in changes.deletions {
            let name = deletion.recordID.recordName
            if let id = UUID(uuidString: name) {
                batch.deletions.append(id)
                snapshot.spaces[id] = nil
                snapshot.items[id] = nil
                snapshot.systemFields[id] = nil
            } else if name.hasPrefix("device-") {
                let idPart = String(name.dropFirst("device-".count))
                if let id = UUID(uuidString: idPart) {
                    otherDevices.removeAll { $0.deviceID == id }
                    snapshot.systemFields[id] = nil
                }
            }
        }
        saveSnapshot()
        if !batch.isEmpty {
            delegate?.syncApplyRemote(batch)
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
        for failure in sent.failedRecordSaves {
            handleSaveFailure(failure)
        }
        saveSnapshot()
    }

    private func handleSaveFailure(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let recordID = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            // The server copy is the arbiter: take its system fields, then
            // re-enqueue so our fields merge onto it through the provider.
            if let server = failure.error.serverRecord {
                if let id = UUID(uuidString: recordID.recordName) {
                    snapshot.systemFields[id] = SyncRecordProvider.systemFields(of: server)
                    switch server.recordType {
                    case SyncRecordType.space:
                        if let space = RecordMapper.space(from: server) { snapshot.spaces[space.id] = space }
                    case SyncRecordType.item:
                        if let item = RecordMapper.item(from: server) { snapshot.items[item.id] = item }
                    default:
                        break
                    }
                } else if recordID.recordName == DeviceTabs.recordName(for: deviceID) {
                    snapshot.systemFields[deviceID] = SyncRecordProvider.systemFields(of: server)
                }
            }
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            noteLocalChange()
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
