// Licensed under GPL-3.0. See LICENSE.
import CloudKit
import Foundation
import OSLog
import NookTabsCore

@MainActor
public protocol CloudSyncEngineDelegate: AnyObject {
    var syncCurrentTree: TabTree { get }
    func syncApplyRemote(_ batch: RemoteBatch)
    /// End of a fetch cycle. The delegate runs `repair` here, never per batch,
    /// so a child whose folder arrives in a later batch is not ejected.
    func syncFetchDidComplete()
    /// The user deleted Nook's iCloud data from elsewhere. The engine has
    /// stopped; the delegate turns the setting off so a relaunch does not
    /// upload everything again.
    func syncDisabledRemotely()
}

/// Thin owner of one CKSyncEngine over the private database's NookSync zone.
/// All logic that can be pure lives in SyncDiff / SyncMerge / SyncRecordProvider;
/// this class schedules, persists and translates events.
@MainActor
@Observable
public final class CloudSyncEngine: CKSyncEngineDelegate {
    public enum Status: Equatable, Sendable {
        case off
        case noAccount
        case syncing
        case synced
        case quotaExceeded
        case error(String)
    }

    public internal(set) var status: Status = .off
    /// Other devices' published tabs, newest lastSeen first, nothing older than 14 days.
    public internal(set) var otherDevices: [DeviceTabsPayload] = []

    @ObservationIgnored public weak var delegate: CloudSyncEngineDelegate?

    @ObservationIgnored let directory: URL
    @ObservationIgnored let containerID: String
    @ObservationIgnored let deviceID: UUID
    @ObservationIgnored let deviceName: String
    @ObservationIgnored var snapshot = SyncSnapshot()
    @ObservationIgnored var engine: CKSyncEngine?
    @ObservationIgnored var starting = false
    @ObservationIgnored var diffScheduled = false
    @ObservationIgnored var devicePublishScheduled = false
    @ObservationIgnored var lastPublishedTabs: [DeviceTabsPayload.Tab]?
    @ObservationIgnored let log = Logger(subsystem: "com.gstudios.nook", category: "Sync")

    static let diffCoalesce: Duration = .seconds(2)
    static let devicePublishInterval: Duration = .seconds(30)

    var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    var stateURL: URL { directory.appendingPathComponent("state.data") }
    var deviceRecordID: CKRecord.ID {
        CKRecord.ID(recordName: DeviceTabs.recordName(for: deviceID), zoneID: RecordMapper.zoneID)
    }

    public init(directory: URL, containerID: String, deviceID: UUID, deviceName: String) {
        self.directory = directory
        self.containerID = containerID
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    // MARK: - Lifecycle

    /// True when the user is signed into iCloud. Callers gate the one-time
    /// offer on this; `start()` checks it again itself.
    public static func accountAvailable(containerID: String) async -> Bool {
        (try? await CKContainer(identifier: containerID).accountStatus()) == .available
    }

    public func start() {
        guard engine == nil, !starting else { return }
        starting = true
        status = .syncing
        Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await CKContainer(identifier: self.containerID).accountStatus()
                self.starting = false
                guard account == .available else {
                    self.status = .noAccount
                    return
                }
                self.configureEngine()
            } catch {
                self.starting = false
                self.status = .error(error.localizedDescription)
                self.log.error("Account status failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func configureEngine() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        snapshot = SyncSnapshot.load(from: snapshotURL)
        refreshOtherDevices()
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadStateSerialization(),
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if snapshot.spaces.isEmpty && snapshot.items.isEmpty {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapper.zoneID))])
        }
        status = .synced
        noteLocalChange()
        log.info("Sync engine started")
    }

    public func stop(discardState: Bool) {
        engine = nil
        status = .off
        otherDevices = []
        lastPublishedTabs = nil
        if discardState {
            snapshot = SyncSnapshot()
            try? FileManager.default.removeItem(at: snapshotURL)
            try? FileManager.default.removeItem(at: stateURL)
        }
        log.info("Sync engine stopped (discardState: \(discardState))")
    }

    // MARK: - Local changes

    /// Called after every TabsController save. Cheap; real work is coalesced.
    public func noteLocalChange() {
        guard engine != nil else { return }
        scheduleDiff()
        scheduleDevicePublish()
    }

    private func scheduleDiff() {
        guard !diffScheduled else { return }
        diffScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.diffCoalesce)
            guard let self else { return }
            self.diffScheduled = false
            self.runDiff()
        }
    }

    func runDiff() {
        guard let engine, let tree = delegate?.syncCurrentTree else { return }
        let changes = SyncDiff.changes(tree: tree, snapshot: snapshot)
        guard !changes.isEmpty else { return }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for space in changes.upsertSpaces { pending.append(.saveRecord(RecordMapper.recordID(space.id))) }
        for item in changes.upsertItems { pending.append(.saveRecord(RecordMapper.recordID(item.id))) }
        for id in changes.deleteIDs { pending.append(.deleteRecord(RecordMapper.recordID(id))) }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    private func scheduleDevicePublish() {
        guard !devicePublishScheduled else { return }
        devicePublishScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.devicePublishInterval)
            guard let self else { return }
            self.devicePublishScheduled = false
            self.publishDeviceRecordIfChanged()
        }
    }

    func publishDeviceRecordIfChanged() {
        guard let engine, let tree = delegate?.syncCurrentTree else { return }
        let tabs = DeviceTabs.payload(tree: tree, deviceID: deviceID, name: deviceName).tabs
        guard tabs != lastPublishedTabs else { return }
        lastPublishedTabs = tabs
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(deviceRecordID)])
    }

    /// Best effort at quit, next to TabStore.flushSync.
    public func flushForTermination() {
        publishDeviceRecordIfChanged()
        saveSnapshot()
    }

    // MARK: - Devices

    public func removeDevice(_ id: UUID) {
        snapshot.devices[id] = nil
        saveSnapshot()
        refreshOtherDevices()
        engine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CKRecord.ID(recordName: DeviceTabs.recordName(for: id), zoneID: RecordMapper.zoneID)),
        ])
    }

    func refreshOtherDevices() {
        otherDevices = snapshot.otherDevices(excluding: deviceID)
    }

    // MARK: - Cloud data removal

    /// Stops first: a live engine answers the deletion's zoneNotFound errors
    /// by creating the zone again.
    public func deleteCloudData() async {
        stop(discardState: true)
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [RecordMapper.zoneID])
        } catch {
            log.error("Zone delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Persistence

    func saveSnapshot() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? snapshot.save(to: snapshotURL)
    }

    func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func saveStateSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(serialization) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
