// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct GuardedTabsTests {
    @Test func marksSurviveTheFile() throws {
        var device = DeviceState()
        let id = UUID()
        device.guarded = [id]
        let read = try JSONDecoder().decode(DeviceState.self, from: JSONEncoder().encode(device))
        #expect(read.guarded == [id])
        // A file written before the field existed has no such key.
        let older = try JSONDecoder().decode(DeviceState.self, from: JSONEncoder().encode(DeviceState()))
        #expect(older.guarded == nil)
    }

    @Test func pruneKeepsOpenTabsOnly() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let open = f.tab("open", in: tabs)
        let shut = f.tab("shut", in: tabs)
        var device = DeviceState()
        device.guarded = [open, shut, UUID()]

        _ = try f.tree.close(shut, now: fixedNow)
        device.prune(against: f.tree)
        #expect(device.guarded == [open])

        _ = try f.tree.close(open, now: fixedNow)
        device.prune(against: f.tree)
        #expect(device.guarded == nil)
    }

    // TabsController.remove closes inside perform, which prunes before the closed entry is recorded
    // (and auto-archive never records one), so the marks ride on the entries instead.
    @Test func closedAndArchiveEntriesCarryTheMarks() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("parent", in: tabs)
        let child = f.tab("child", in: .folder(itemID: parent))
        let plain = f.tab("plain", in: .folder(itemID: parent))
        var device = DeviceState()
        device.guarded = [parent, child, f.tab("other", in: tabs)]
        let marked = device.guarded ?? []

        var closed = try f.tree.close(parent, now: fixedNow).closed
        closed.carry(marked)
        device.prune(against: f.tree)
        #expect(device.guarded?.count == 1)
        #expect(closed.guarded == [parent, child])
        #expect(!(closed.guarded ?? []).contains(plain))

        let entry = try #require(ArchiveEntry(closed: closed, reason: .auto, now: fixedNow))
        #expect(entry.guarded == [parent, child])

        // The marks go through the files, and a file written before they existed has none.
        let read = try JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(Archive(entries: [entry])))
        #expect(read.entries.first?.guarded == [parent, child])
        let reread = try JSONDecoder().decode(ClosedEntry.self, from: JSONEncoder().encode(closed))
        #expect(reread.guarded == [parent, child])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json["guarded"] = nil
        let older = try JSONDecoder().decode(ArchiveEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.guarded == nil)
    }

    @Test func entriesWithNothingGuardedCarryNothing() throws {
        var f = Fixture()
        let id = f.tab("a", in: .tabs(spaceID: f.spaceA))
        var closed = try f.tree.close(id, now: fixedNow).closed
        closed.carry([UUID()])
        #expect(closed.guarded == nil)
        #expect(ArchiveEntry(closed: closed, reason: .closed, now: fixedNow)?.guarded == nil)
    }
}
