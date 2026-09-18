// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import Foundation

/// How a launch obtained its state.
public enum LoadOutcome: Equatable, Sendable {
    /// No files and no backups. The caller seeds the first space and tab.
    case firstLaunch
    case loaded
    /// A file failed to decode or was empty; state came from this backup folder.
    case restoredFromBackup(String)
    /// Nothing usable decoded. The session runs without writing so the files stay untouched.
    case readOnly(reason: String)
}

public struct LoadedState: Sendable {
    public var tree: TabTree
    public var device: DeviceState
    public var outcome: LoadOutcome
    /// Space ids the profile merge remapped (old space id -> merged space id). Empty unless this
    /// launch migrated a format-1 file; the app uses it to repoint ids it stores elsewhere.
    public var migratedSpaceIDs: [UUID: UUID] = [:]
}

/// Reads and writes `structure.json` (synced scope) and `device.json` (device scope).
///
/// Saves are coalesced on a serial queue; `flush()` writes synchronously and is safe to call
/// from `applicationShouldTerminate`. Every write replaces the file atomically.
public final class TabStore: @unchecked Sendable {
    public static let coalesceInterval: TimeInterval = 0.5
    public static let backupDays = 7
    /// Bumped when profiles merged into spaces. Format 1 files are migrated on load.
    public static let formatVersion = 2

    struct StructureFile: Codable {
        var formatVersion = TabStore.formatVersion
        var spaces: [SpaceRecord]
        var items: [Item]
    }

    struct DeviceFile: Codable {
        var formatVersion = TabStore.formatVersion
        var items: [Item]
        var state: DeviceState
    }

    /// Just enough of either file to tell which format it is.
    private struct VersionProbe: Codable { var formatVersion: Int }

    public let directory: URL
    private var structureURL: URL { directory.appendingPathComponent("structure.json") }
    private var deviceURL: URL { directory.appendingPathComponent("device.json") }
    private var backupsURL: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    private let queue = DispatchQueue(label: "com.gstudios.nook.tabstore", qos: .utility)
    private let lock = NSLock()
    private var pending: (TabTree, DeviceState)?
    private var scheduled = false
    private var readOnly = false
    /// Synced item ids last written to structure.json. A synced item that moves to the device
    /// scope stays in structure.json until device.json holds it, so a crash between the two
    /// writes leaves a duplicate the loader resolves, never a loss.
    private var writtenSyncedIDs: Set<UUID> = []

    public private(set) var lastError: Error?

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Load

    public func load(now: Date = Date()) -> LoadedState {
        let fm = FileManager.default
        let hasStructure = fm.fileExists(atPath: structureURL.path)
        let hasDevice = fm.fileExists(atPath: deviceURL.path)

        if !hasStructure && !hasDevice && backupFolders().isEmpty {
            return finish(LoadedState(tree: TabTree(), device: DeviceState(), outcome: .firstLaunch), now: now, backup: false)
        }

        if let state = Self.decode(structure: structureURL, device: deviceURL) {
            // The pre-merge files are kept apart from the daily backups, which a later launch
            // today would overwrite with migrated data.
            if !state.migrated.isEmpty { copyFiles(into: "\(Self.dayStamp(now))-pre-merge") }
            var loaded = LoadedState(tree: state.tree, device: state.device, outcome: .loaded)
            loaded.migratedSpaceIDs = state.migrated
            return finish(loaded, now: now, backup: true)
        }

        for folder in backupFolders() {
            let s = folder.appendingPathComponent("structure.json")
            let d = folder.appendingPathComponent("device.json")
            if let state = Self.decode(structure: s, device: d) {
                var loaded = LoadedState(tree: state.tree, device: state.device,
                                         outcome: .restoredFromBackup(folder.lastPathComponent))
                loaded.migratedSpaceIDs = state.migrated
                return finish(loaded, now: now, backup: false)
            }
        }

        lock.withLock { readOnly = true }
        let reason = hasStructure ? "structure.json could not be read and no backup could be restored"
                                  : "structure.json is missing and no backup could be restored"
        return LoadedState(tree: TabTree(), device: DeviceState(), outcome: .readOnly(reason: reason))
    }

    public var isReadOnly: Bool { lock.withLock { readOnly } }

    /// Decodes both files, migrating a format-1 pair first. structure.json must hold at least one
    /// live space. A missing or unreadable device.json yields a fresh device state; a duplicate id
    /// keeps the synced copy.
    static func decode(structure: URL, device: URL) -> (tree: TabTree, device: DeviceState, migrated: [UUID: UUID])? {
        guard var structureData = try? Data(contentsOf: structure) else { return nil }
        var deviceData = try? Data(contentsOf: device)
        let decoder = JSONDecoder()

        var migrated: [UUID: UUID] = [:]
        let version = (try? decoder.decode(VersionProbe.self, from: structureData))?.formatVersion
        if version != formatVersion {
            guard let result = ProfileMerge.migrate(structure: structureData, device: deviceData) else { return nil }
            structureData = result.structure
            deviceData = result.device
            migrated = result.spaceIDs
        }

        guard let file = try? decoder.decode(StructureFile.self, from: structureData),
              file.spaces.contains(where: { $0.deletedAt == nil }) else { return nil }
        var deviceItems: [Item] = []
        var state = DeviceState()
        if let deviceData, let deviceFile = try? decoder.decode(DeviceFile.self, from: deviceData) {
            deviceItems = deviceFile.items
            state = deviceFile.state
        }
        let syncedIDs = Set(file.items.map(\.id))
        let tree = TabTree(spaces: file.spaces, items: file.items + deviceItems.filter { !syncedIDs.contains($0.id) })
        state.firstLaunchCompleted = true
        return (tree, state, migrated)
    }

    private func finish(_ loaded: LoadedState, now: Date, backup: Bool) -> LoadedState {
        var result = loaded
        result.tree.repair(now: now)
        result.device.prune(against: result.tree)
        lock.withLock {
            writtenSyncedIDs = Set(result.tree.items.keys.filter { result.tree.scope(of: $0) == .synced })
        }
        if backup { makeBackup(now: now) }
        return result
    }

    // MARK: - Save

    /// Queues a save of the latest state; bursts within `coalesceInterval` write once.
    public func save(_ tree: TabTree, _ device: DeviceState) {
        lock.lock()
        defer { lock.unlock() }
        guard !readOnly else { return }
        pending = (tree, device)
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + Self.coalesceInterval) { [weak self] in self?.writePending() }
    }

    /// Writes any queued state now and waits for it.
    public func flush() {
        queue.sync { writePending() }
    }

    private func writePending() {
        lock.lock()
        let next = pending
        pending = nil
        scheduled = false
        let previousSynced = writtenSyncedIDs
        lock.unlock()
        guard let (tree, device) = next else { return }
        do {
            let syncedIDs = try write(tree: tree, device: device, previousSynced: previousSynced)
            lock.withLock { writtenSyncedIDs = syncedIDs; lastError = nil }
        } catch {
            lock.withLock { lastError = error }
        }
    }

    /// Runs on `queue`. Returns the synced ids now on disk.
    func write(tree: TabTree, device: DeviceState, previousSynced: Set<UUID>) throws -> Set<UUID> {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        var synced: [Item] = []
        var local: [Item] = []
        for item in tree.items.values {
            if tree.scope(of: item.id) == .synced { synced.append(item) } else { local.append(item) }
        }
        let syncedIDs = Set(synced.map(\.id))
        let structure = StructureFile(spaces: Array(tree.spaces.values), items: synced)

        // Destination first. structure.json gains items entering the synced scope and keeps items
        // leaving it, then device.json is written, then items that left are dropped from
        // structure.json. A crash between any two writes leaves a duplicate, never a loss.
        let leaving = previousSynced.subtracting(syncedIDs).intersection(Set(local.map(\.id)))
        let bridge = StructureFile(spaces: structure.spaces, items: synced + local.filter { leaving.contains($0.id) })
        try encoder.encode(bridge).write(to: structureURL, options: .atomic)
        try encoder.encode(DeviceFile(items: local, state: device)).write(to: deviceURL, options: .atomic)
        if !leaving.isEmpty {
            try encoder.encode(structure).write(to: structureURL, options: .atomic)
        }
        return syncedIDs
    }

    // MARK: - Backups

    /// Backup folders, newest first.
    func backupFolders() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
        return names.sorted(by: >).map { backupsURL.appendingPathComponent($0, isDirectory: true) }
    }

    static func dayStamp(_ now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    /// Copies both files into `Backups/<name>/`.
    private func copyFiles(into name: String) {
        let fm = FileManager.default
        let folder = backupsURL.appendingPathComponent(name, isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in [structureURL, deviceURL] where fm.fileExists(atPath: source.path) {
                let data = try Data(contentsOf: source)
                try data.write(to: folder.appendingPathComponent(source.lastPathComponent), options: .atomic)
            }
        } catch {
            lock.withLock { lastError = error }
        }
    }

    /// Copies both files into `Backups/<yyyy-MM-dd>/` and keeps the newest `backupDays` folders.
    func makeBackup(now: Date) {
        copyFiles(into: Self.dayStamp(now))
        for old in backupFolders().dropFirst(Self.backupDays) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}

extension TabTree {
    /// The state a first launch starts with: one space with one tab.
    public static func firstLaunch(spaceID: UUID = UUID(), spaceName: String = "Personal", homeURL: URL, now: Date = Date()) -> TabTree {
        var tree = TabTree()
        tree.createSpace(id: spaceID, name: spaceName, icon: "house", accentHex: "#7C7C7C", after: nil, now: now)
        try! tree.createTab(url: homeURL, title: "New Tab", in: .tabs(spaceID: spaceID), after: nil, now: now)
        return tree
    }
}
