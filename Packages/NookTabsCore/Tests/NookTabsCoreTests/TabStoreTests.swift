// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct TabStoreTests {
    func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NookTabsCoreTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func sample() -> (TabTree, DeviceState, Fixture) {
        var f = Fixture()
        let folder = f.folder("F", in: .pinned(spaceID: f.spaceA))
        f.tab("pinned child", in: .folder(itemID: folder))
        f.tab("fav", in: .favorites(spaceID: f.spaceA))
        let regular = f.tab("regular", in: .tabs(spaceID: f.spaceA))
        try! f.tree.rename(regular, customTitle: "Mine", now: fixedNow)
        var device = DeviceState()
        device.openFolders = [folder]
        device.windows = [WindowRecord(spaceID: f.spaceA, selectedItemBySpace: [f.spaceA: regular])]
        device.firstLaunchCompleted = true
        return (f.tree, device, f)
    }

    @Test func firstLaunchWithNoFiles() {
        let store = TabStore(directory: tempDirectory())
        let loaded = store.load(now: fixedNow)
        #expect(loaded.outcome == .firstLaunch)
        #expect(loaded.tree.spaces.isEmpty)

        let seeded = TabTree.firstLaunch(homeURL: url("home"), now: fixedNow)
        checkInvariants(seeded)
        #expect(seeded.orderedSpaces.count == 1)
        #expect(seeded.children(of: .tabs(spaceID: seeded.orderedSpaces[0].id)).count == 1)
    }

    @Test func roundTripSplitsScopes() throws {
        let dir = tempDirectory()
        let (tree, device, _) = sample()
        let store = TabStore(directory: dir)
        _ = store.load(now: fixedNow)
        store.save(tree, device)
        store.flush()

        let structure = try JSONDecoder().decode(TabStore.StructureFile.self, from: Data(contentsOf: dir.appendingPathComponent("structure.json")))
        let deviceFile = try JSONDecoder().decode(TabStore.DeviceFile.self, from: Data(contentsOf: dir.appendingPathComponent("device.json")))
        #expect(Set(structure.items.map(\.displayTitle)) == ["F", "pinned child", "fav"])
        #expect(deviceFile.items.map(\.displayTitle) == ["Mine"])

        let reloaded = TabStore(directory: dir).load(now: fixedNow)
        #expect(reloaded.outcome == .loaded)
        #expect(reloaded.tree == tree)
        #expect(reloaded.device == device)
    }

    @Test func coalescesBurstsIntoOneWrite() throws {
        let dir = tempDirectory()
        var (tree, device, f) = sample()
        let store = TabStore(directory: dir)
        _ = store.load(now: fixedNow)
        for i in 0..<20 {
            try tree.createTab(url: url("burst\(i)"), title: "b\(i)", in: .tabs(spaceID: f.spaceA), after: nil, now: fixedNow)
            store.save(tree, device)
        }
        store.flush()
        let reloaded = TabStore(directory: dir).load(now: fixedNow)
        #expect(reloaded.tree == tree)
        f.tree = tree
        device.openFolders = []
    }

    @Test func crashBetweenScopeWritesLosesNothing() throws {
        let dir = tempDirectory()
        var (tree, device, f) = sample()
        let store = TabStore(directory: dir)
        _ = store.load(now: fixedNow)
        store.save(tree, device)
        store.flush()

        // Unpin the pinned child into the tabs section, then simulate a crash after phase 1:
        // structure.json holds the bridge, device.json is still the old file.
        let child = tree.items.values.first { $0.displayTitle == "pinned child" }!.id
        try tree.move(child, to: .tabs(spaceID: f.spaceA), after: nil, now: fixedNow)
        let oldDevice = try Data(contentsOf: dir.appendingPathComponent("device.json"))
        let previous = Set(TabStore(directory: dir).load(now: fixedNow).tree.items.keys.filter { tree.scope(of: $0) == .synced || $0 == child })
        _ = try store.write(tree: tree, device: device, previousSynced: previous)
        let finalStructure = try Data(contentsOf: dir.appendingPathComponent("structure.json"))

        // Rebuild the bridge state: phase 1 structure plus the old device file.
        var bridgeItems = tree.items.values.filter { tree.scope(of: $0.id) == .synced }
        bridgeItems.append(tree.items[child]!)
        let bridge = TabStore.StructureFile(spaces: Array(tree.spaces.values), items: bridgeItems)
        try JSONEncoder().encode(bridge).write(to: dir.appendingPathComponent("structure.json"))
        try oldDevice.write(to: dir.appendingPathComponent("device.json"))
        let afterCrash = TabStore(directory: dir).load(now: fixedNow)
        #expect(afterCrash.tree.item(child)?.parent == .tabs(spaceID: f.spaceA))

        // The completed write has the child only in device.json.
        let structure = try JSONDecoder().decode(TabStore.StructureFile.self, from: finalStructure)
        #expect(!structure.items.contains { $0.id == child })
        f.tree = tree
    }

    @Test func corruptFileRestoresNewestBackup() throws {
        let dir = tempDirectory()
        let (tree, device, _) = sample()
        let store = TabStore(directory: dir)
        _ = store.load(now: fixedNow)
        store.save(tree, device)
        store.flush()
        // A successful load makes today's backup.
        #expect(TabStore(directory: dir).load(now: fixedNow).outcome == .loaded)

        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("structure.json"))
        let restored = TabStore(directory: dir).load(now: fixedNow)
        guard case .restoredFromBackup = restored.outcome else {
            Issue.record("expected backup restore, got \(restored.outcome)")
            return
        }
        #expect(restored.tree == tree)
    }

    @Test func noSpacesCountsAsCorruption() throws {
        let dir = tempDirectory()
        let empty = TabStore.StructureFile(spaces: [], items: [])
        try JSONEncoder().encode(empty).write(to: dir.appendingPathComponent("structure.json"))
        let store = TabStore(directory: dir)
        let loaded = store.load(now: fixedNow)
        guard case .readOnly = loaded.outcome else {
            Issue.record("expected read-only, got \(loaded.outcome)")
            return
        }
        #expect(store.isReadOnly)
        let (tree, device, _) = sample()
        store.save(tree, device)
        store.flush()
        let onDisk = try JSONDecoder().decode(TabStore.StructureFile.self, from: Data(contentsOf: dir.appendingPathComponent("structure.json")))
        #expect(onDisk.spaces.isEmpty, "read-only store must not write")
    }

    @Test func closedEntryDecodesWithoutEndedPage() throws {
        var entry = ClosedEntry(items: [], section: .tabs(spaceID: UUID()), closedAt: fixedNow, endedPage: OpenPage(url: url("page"), title: "Page"))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        #expect(json["endedPage"] != nil)
        json["endedPage"] = nil
        entry = try JSONDecoder().decode(ClosedEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(entry.endedPage == nil)
    }

    @Test func keepsSevenBackupFolders() throws {
        let dir = tempDirectory()
        let (tree, device, _) = sample()
        let store = TabStore(directory: dir)
        _ = store.load(now: fixedNow)
        store.save(tree, device)
        store.flush()
        for day in 0..<10 {
            _ = TabStore(directory: dir).load(now: fixedNow.addingTimeInterval(Double(day) * 86_400))
        }
        #expect(store.backupFolders().count == TabStore.backupDays)
    }
}
