// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct SharedLoginsTests {
    @Test func spacesUseTheirOwnStoreUnlessShared() {
        var f = Fixture()
        let shared = UUID()
        f.tree.createSpace(id: shared, name: "Work 2", icon: "", accentHex: "#000", after: f.spaceB,
                           dataStoreID: f.spaceA, now: fixedNow)
        #expect(f.tree.dataStoreID(for: f.spaceA) == f.spaceA)
        #expect(f.tree.dataStoreID(for: f.spaceB) == f.spaceB)
        #expect(f.tree.dataStoreID(for: shared) == f.spaceA)
    }

    @Test func storeOutlivesTheSpaceItIsNamedFor() throws {
        var f = Fixture()
        let shared = UUID()
        f.tree.createSpace(id: shared, name: "Work 2", icon: "", accentHex: "#000", after: f.spaceB,
                           dataStoreID: f.spaceA, now: fixedNow)
        _ = try f.tree.deleteSpace(f.spaceA, now: fixedNow)
        #expect(f.tree.dataStoreID(for: shared) == f.spaceA)
    }

    @Test func agentBorrowsTheSharedStore() throws {
        var f = Fixture()
        let shared = UUID()
        f.tree.createSpace(id: shared, name: "Work 2", icon: "", accentHex: "#000", after: f.spaceB,
                           dataStoreID: f.spaceA, now: fixedNow)
        let created = f.tree.ensureAgentSpace(loginsFrom: shared, now: fixedNow)
        let agent = try #require(created)
        #expect(f.tree.dataStoreID(for: agent.id) == f.spaceA)
    }

    @Test func survivesSaveAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SharedLoginsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var f = Fixture()
        let shared = UUID()
        f.tree.createSpace(id: shared, name: "Work 2", icon: "", accentHex: "#000", after: f.spaceB,
                           dataStoreID: f.spaceA, now: fixedNow)
        var device = DeviceState()
        device.firstLaunchCompleted = true
        let store = TabStore(directory: dir)
        store.save(f.tree, device)
        store.flush()
        let reloaded = TabStore(directory: dir).load(now: fixedNow).tree
        #expect(reloaded.dataStoreID(for: shared) == f.spaceA)
        #expect(reloaded.space(f.spaceB)?.dataStoreID == nil)
    }
}
