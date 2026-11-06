// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct ArchiveTests {
    private let hour: TimeInterval = 3600

    @Test func unstampedTabsStartTheirClockNow() {
        var f = Fixture()
        let a = f.tab("a", in: .tabs(spaceID: f.spaceA))
        var device = DeviceState()
        #expect(device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [], now: fixedNow).isEmpty)
        #expect(device.lastActive?[a] == fixedNow)
        #expect(device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [], now: fixedNow.addingTimeInterval(hour)) == [a])
    }

    @Test func protectedFoldersPinnedAndFreshTabsStay() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let idle = f.tab("idle", in: tabs)
        let selected = f.tab("selected", in: tabs)
        let fresh = f.tab("fresh", in: tabs)
        let pinned = f.tab("pinned", in: .pinned(spaceID: f.spaceA))
        let folder = try! f.tree.createFolder(title: "f", in: tabs, after: nil, now: fixedNow)
        _ = folder
        var device = DeviceState()
        let old = fixedNow.addingTimeInterval(-3 * hour)
        for id in [idle, selected, pinned] { device.stampActive(id, at: old) }
        device.stampActive(fresh, at: fixedNow)
        let roots = device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [selected], now: fixedNow)
        #expect(roots == [idle])
    }

    @Test func aTrailGoesWholeAndAnyActiveMemberKeepsIt() {
        var f = Fixture()
        let parent = f.tab("p", in: .tabs(spaceID: f.spaceA))
        let child = f.tab("c", in: .folder(itemID: parent))
        var device = DeviceState()
        let old = fixedNow.addingTimeInterval(-3 * hour)
        device.stampActive(parent, at: old)
        device.stampActive(child, at: fixedNow)
        #expect(device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [], now: fixedNow).isEmpty)
        device.stampActive(child, at: old)
        #expect(device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [], now: fixedNow) == [parent])
        #expect(device.idleArchiveRoots(in: f.tree, olderThan: hour, keeping: [child], now: fixedNow).isEmpty)
    }

    @Test func retentionDropsOldAndCapsCount() {
        var f = Fixture()
        let id = f.tab("a", in: .tabs(spaceID: f.spaceA))
        let item = f.tree.item(id)!
        let closed = ClosedEntry(items: [item], section: .tabs(spaceID: f.spaceA), closedAt: fixedNow)
        var archive = Archive()
        var old = ArchiveEntry(closed: closed, reason: .closed, now: fixedNow.addingTimeInterval(-31 * 86_400))!
        old.id = UUID()
        archive.entries = [old]
        archive.add(ArchiveEntry(closed: closed, reason: .auto, now: fixedNow)!)
        #expect(archive.entries.map(\.id) == [id])
        for _ in 0..<(Archive.maxEntries + 5) {
            var e = ArchiveEntry(closed: closed, reason: .closed, now: fixedNow)!
            e.id = UUID()
            archive.add(e)
        }
        #expect(archive.entries.count == Archive.maxEntries)
        #expect(archive.entries.first?.id != id)
    }

    @Test func restorePutsTheTrailFirstInTheTabsSection() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("p", in: tabs)
        let child = f.tab("c", in: .folder(itemID: parent))
        let other = f.tab("o", in: tabs)
        let closed = try f.tree.close(parent).closed
        _ = try f.tree.restore(closed.items, toTopOf: f.spaceA, now: fixedNow)
        #expect(f.tree.children(of: tabs).map(\.id) == [parent, other])
        #expect(f.tree.children(of: .folder(itemID: parent)).map(\.id) == [child])
    }

    @Test func storeRoundTripsAndOldDeviceFilesDecode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TabStore(directory: dir)
        var f = Fixture()
        let id = f.tab("a", in: .tabs(spaceID: f.spaceA))
        let closed = ClosedEntry(items: [f.tree.item(id)!], section: .tabs(spaceID: f.spaceA), closedAt: fixedNow)
        store.save(Archive(entries: [ArchiveEntry(closed: closed, reason: .closed, now: fixedNow)!]))
        store.flush()
        #expect(store.loadArchive(now: fixedNow).entries.map(\.id) == [id])
        let old = try JSONDecoder().decode(DeviceState.self, from: Data(#"{"openFolders":[],"openPages":[],"windows":[],"closed":[],"firstLaunchCompleted":true}"#.utf8))
        #expect(old.lastActive == nil)
    }

    @Test func unreadableOrNewerArchiveIsKeptAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":99,"entries":[]}"#.utf8).write(to: dir.appendingPathComponent("archive.json"))
        #expect(TabStore(directory: dir).loadArchive().entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("archive.json.bad").path))
    }
}
