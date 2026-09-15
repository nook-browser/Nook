import Foundation

/// How a launch obtained its state.
public enum LoadOutcome: Equatable, Sendable {
    /// No files and no backups. The caller seeds the first profile, space and tab.
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
}

/// Reads and writes `structure.json` (synced scope) and `device.json` (device scope).
///
/// Saves are coalesced on a serial queue; `flush()` writes synchronously and is safe to call
/// from `applicationShouldTerminate`. Every write replaces the file atomically.
public final class TabStore: @unchecked Sendable {
    public static let coalesceInterval: TimeInterval = 0.5
    public static let backupDays = 7

    struct StructureFile: Codable {
        var formatVersion = 1
        var profiles: [Profile]
        var spaces: [Space]
        var items: [Item]
    }

    struct DeviceFile: Codable {
        var formatVersion = 1
        var items: [Item]
        var state: DeviceState
    }

    public let directory: URL
    private var structureURL: URL { directory.appendingPathComponent("structure.json") }
    private var deviceURL: URL { directory.appendingPathComponent("device.json") }
    private var backupsURL: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    private let queue = DispatchQueue(label: "com.baingurley.nook.tabstore", qos: .utility)
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
            return finish(LoadedState(tree: state.0, device: state.1, outcome: .loaded), now: now, backup: true)
        }

        for folder in backupFolders() {
            let s = folder.appendingPathComponent("structure.json")
            let d = folder.appendingPathComponent("device.json")
            if let state = Self.decode(structure: s, device: d) {
                return finish(LoadedState(tree: state.0, device: state.1, outcome: .restoredFromBackup(folder.lastPathComponent)), now: now, backup: false)
            }
        }

        lock.withLock { readOnly = true }
        let reason = hasStructure ? "structure.json could not be read and no backup could be restored"
                                  : "structure.json is missing and no backup could be restored"
        return LoadedState(tree: TabTree(), device: DeviceState(), outcome: .readOnly(reason: reason))
    }

    public var isReadOnly: Bool { lock.withLock { readOnly } }

    /// Decodes both files. structure.json must hold at least one live profile. A missing or
    /// unreadable device.json yields a fresh device state; a duplicate id keeps the synced copy.
    static func decode(structure: URL, device: URL) -> (TabTree, DeviceState)? {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: structure),
              let file = try? decoder.decode(StructureFile.self, from: data),
              file.profiles.contains(where: { $0.deletedAt == nil }) else { return nil }
        var deviceItems: [Item] = []
        var state = DeviceState()
        if let data = try? Data(contentsOf: device), let deviceFile = try? decoder.decode(DeviceFile.self, from: data) {
            deviceItems = deviceFile.items
            state = deviceFile.state
        }
        let syncedIDs = Set(file.items.map(\.id))
        let tree = TabTree(profiles: file.profiles, spaces: file.spaces, items: file.items + deviceItems.filter { !syncedIDs.contains($0.id) })
        state.firstLaunchCompleted = true
        return (tree, state)
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
        let structure = StructureFile(profiles: Array(tree.profiles.values), spaces: Array(tree.spaces.values), items: synced)

        // Destination first. structure.json gains items entering the synced scope and keeps items
        // leaving it, then device.json is written, then items that left are dropped from
        // structure.json. A crash between any two writes leaves a duplicate, never a loss.
        let leaving = previousSynced.subtracting(syncedIDs).intersection(Set(local.map(\.id)))
        let bridge = StructureFile(profiles: structure.profiles, spaces: structure.spaces, items: synced + local.filter { leaving.contains($0.id) })
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

    /// Copies both files into `Backups/<yyyy-MM-dd>/` and keeps the newest `backupDays` folders.
    func makeBackup(now: Date) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let folder = backupsURL.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in [structureURL, deviceURL] where fm.fileExists(atPath: source.path) {
                let target = folder.appendingPathComponent(source.lastPathComponent)
                let data = try Data(contentsOf: source)
                try data.write(to: target, options: .atomic)
            }
            for old in backupFolders().dropFirst(Self.backupDays) {
                try? fm.removeItem(at: old)
            }
        } catch {
            lock.withLock { lastError = error }
        }
    }
}

extension TabTree {
    /// The state a first launch starts with: one profile, one space, one tab.
    public static func firstLaunch(profileID: UUID = UUID(), profileName: String = "Default", spaceName: String = "Personal", homeURL: URL, now: Date = Date()) -> TabTree {
        var tree = TabTree()
        tree.createProfile(id: profileID, name: profileName, icon: "person.crop.circle", now: now)
        let spaceID = UUID()
        try! tree.createSpace(id: spaceID, profileID: profileID, name: spaceName, icon: "house", accentHex: "#7C7C7C", after: nil, now: now)
        try! tree.createTab(url: homeURL, title: "New Tab", in: .tabs(spaceID: spaceID), after: nil, now: now)
        return tree
    }
}
