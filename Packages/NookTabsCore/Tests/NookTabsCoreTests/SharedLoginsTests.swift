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

struct ProfilesTests {
    @Test func everySpaceIsInOneProfileNamedAfterItUntilRenamed() throws {
        var f = Fixture()
        let profiles = f.tree.profiles
        #expect(profiles.map(\.id) == f.tree.orderedSpaces.map(\.id))
        #expect(profiles.map(\.name) == f.tree.orderedSpaces.map(\.name))
        try f.tree.renameProfile(f.spaceA, to: "Personal", now: fixedNow)
        #expect(f.tree.profile(ofSpace: f.spaceA)?.name == "Personal")
    }

    @Test func joiningAndLeaving() throws {
        var f = Fixture()
        try f.tree.renameProfile(f.spaceA, to: "Work", now: fixedNow)
        try f.tree.setProfile(f.spaceB, to: f.spaceA, now: fixedNow)
        #expect(f.tree.profiles.count == 1)
        #expect(f.tree.profile(ofSpace: f.spaceB)?.name == "Work")
        #expect(f.tree.dataStoreID(for: f.spaceB) == f.spaceA)

        // Spaces that share keep sharing when one leaves for a new profile.
        try f.tree.setProfile(f.spaceA, to: nil, name: "Side", now: fixedNow)
        #expect(f.tree.dataStoreID(for: f.spaceA) != f.spaceA)
        #expect(f.tree.dataStoreID(for: f.spaceB) == f.spaceA)
        #expect(f.tree.profile(ofSpace: f.spaceA)?.name == "Side")
        #expect(f.tree.profiles.count == 2)
    }

    @Test func agentIsInNoProfile() throws {
        var f = Fixture()
        _ = f.tree.ensureAgentSpace(loginsFrom: f.spaceA, now: fixedNow)
        #expect(f.tree.profiles.flatMap(\.spaceIDs).count == 2)
    }
}
