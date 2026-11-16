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

    @Test func pruneKeepsOpenAndReopenableTabs() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let open = f.tab("open", in: tabs)
        let shut = f.tab("shut", in: tabs)
        var device = DeviceState()
        device.guarded = [open, shut, UUID()]

        // Closed, and still in reach of Reopen Closed Tab: the mark stays.
        device.pushClosed(try f.tree.close(shut, now: fixedNow).closed)
        device.prune(against: f.tree)
        #expect(device.guarded == [open, shut])

        // Out of the reopen history: the mark goes with it.
        device.closed = []
        device.prune(against: f.tree)
        #expect(device.guarded == [open])

        _ = try f.tree.close(open, now: fixedNow)
        device.prune(against: f.tree)
        #expect(device.guarded == nil)
    }
}
