// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct AgentSpaceTests {
    @Test func createdOnceLastWithLoginsFromGivenSpace() throws {
        var f = Fixture()
        let createdResult = f.tree.ensureAgentSpace(loginsFrom: f.spaceB, now: fixedNow)
        let created = try #require(createdResult)
        #expect(!created.change.isEmpty)
        #expect(f.tree.orderedSpaces.last?.id == created.id)
        #expect(f.tree.space(created.id)?.isAgent == true)
        #expect(f.tree.loginSpace(for: created.id) == f.spaceB)

        let againResult = f.tree.ensureAgentSpace(loginsFrom: f.spaceA, now: fixedNow)
        let again = try #require(againResult)
        #expect(again.id == created.id)
        #expect(again.change.isEmpty)
        #expect(f.tree.orderedSpaces.filter(\.isAgent).count == 1)
        checkInvariants(f.tree)
    }

    @Test func foundByMarkerNotName() throws {
        var f = Fixture()
        f.tree.createSpace(name: "Agent", icon: "sparkle", accentHex: "#000", after: f.spaceB, now: fixedNow)
        #expect(f.tree.agentSpace == nil)
        let createdResult = f.tree.ensureAgentSpace(loginsFrom: nil, now: fixedNow)
        let created = try #require(createdResult)
        try f.tree.updateSpace(created.id, name: "Robots", now: fixedNow)
        #expect(f.tree.agentSpace?.id == created.id)
        // Ordinary spaces keep their own store.
        #expect(f.tree.loginSpace(for: f.spaceA) == f.spaceA)
    }

    @Test func survivesSaveAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AgentSpaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var f = Fixture()
        let createdResult = f.tree.ensureAgentSpace(loginsFrom: f.spaceA, now: fixedNow)
        let created = try #require(createdResult)
        var device = DeviceState()
        device.firstLaunchCompleted = true
        let store = TabStore(directory: dir)
        store.save(f.tree, device)
        store.flush()

        var reloaded = TabStore(directory: dir).load(now: fixedNow).tree
        let reused = reloaded.ensureAgentSpace(loginsFrom: f.spaceB, now: fixedNow)
        #expect(reused?.id == created.id)
        #expect(reloaded.orderedSpaces.filter(\.isAgent).count == 1)
        #expect(reloaded.loginSpace(for: created.id) == f.spaceA)
    }

    @Test func loginsFallBackWhenBorrowedSpaceIsGone() throws {
        var f = Fixture()
        let createdResult = f.tree.ensureAgentSpace(loginsFrom: f.spaceB, now: fixedNow)
        let created = try #require(createdResult)
        _ = try f.tree.deleteSpace(f.spaceB, now: fixedNow)
        #expect(f.tree.loginSpace(for: created.id) == f.spaceA)
    }

    @Test func noOrdinarySpaceNoAgentSpace() {
        var tree = TabTree()
        let result = tree.ensureAgentSpace(loginsFrom: nil, now: fixedNow)
        #expect(result == nil)
    }
}

extension AgentSpaceTests {
    @Test func lastOrdinarySpaceStaysBesideAgentSpace() throws {
        var f = Fixture()
        let created = f.tree.ensureAgentSpace(loginsFrom: f.spaceA, now: fixedNow)
        let agent = try #require(created).id
        _ = try f.tree.deleteSpace(f.spaceB, now: fixedNow)
        #expect(throws: TreeError.lastSpace) { try f.tree.deleteSpace(f.spaceA, now: fixedNow) }
        _ = try f.tree.deleteSpace(agent, now: fixedNow)
        #expect(f.tree.agentSpace == nil)
    }

    @Test func staysLastWhenSpacesAreAddedOrMoved() throws {
        var f = Fixture()
        let created = f.tree.ensureAgentSpace(loginsFrom: f.spaceA, now: fixedNow)
        let agent = try #require(created).id
        let added = UUID()
        f.tree.createSpace(id: added, name: "C", icon: "", accentHex: "#000", after: agent, now: fixedNow)
        #expect(f.tree.orderedSpaces.map(\.id) == [f.spaceA, f.spaceB, added, agent])
        #expect(f.tree.space(added)!.order < f.tree.space(agent)!.order)
        try f.tree.moveSpace(f.spaceA, after: agent, now: fixedNow)
        #expect(f.tree.orderedSpaces.last?.id == agent)
        try f.tree.moveSpace(agent, after: nil, now: fixedNow)
        #expect(f.tree.orderedSpaces.last?.id == agent)
        checkInvariants(f.tree)
    }
}
