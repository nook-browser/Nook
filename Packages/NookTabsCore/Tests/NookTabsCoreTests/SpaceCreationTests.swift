// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct SpaceCreationTests {
    @Test(arguments: SpaceAppearance.Mode.allCases)
    func defaultThemeSurvivesPersistenceAndCanReturnToColor(mode: SpaceAppearance.Mode) throws {
        var f = Fixture()
        let before = try #require(f.tree.space(f.spaceA))
        let theme = SpaceAppearance(nodes: [], mode: mode, grain: 0.2)
        let change = try f.tree.updateSpaceAppearance(f.spaceA, appearance: theme, now: fixedNow)
        let updated = try #require(f.tree.space(f.spaceA))
        #expect(updated.resolvedAppearance.usesDefaultTheme)
        #expect(updated.resolvedAppearance.mode == mode)
        let decoded = try JSONDecoder().decode(SpaceRecord.self, from: JSONEncoder().encode(updated))
        #expect(decoded.resolvedAppearance == theme.normalized)
        f.tree.apply(change)
        #expect(f.tree.space(f.spaceA) == before)
        try f.tree.updateSpaceAppearance(f.spaceA, appearance: theme)
        try f.tree.updateSpace(f.spaceA, accentHex: "#ABCDEF")
        let colored = try #require(f.tree.space(f.spaceA)?.resolvedAppearance)
        #expect(!colored.usesDefaultTheme)
        #expect(colored.nodes.count == 1)
        #expect(colored.primaryAccentHex == "#ABCDEF")
        #expect(colored.mode == mode)
    }

    @Test func themeAndProfileSurviveSaveAndLoad() throws {
        var f = Fixture()
        let theme = SpaceAppearance(nodes: [.init(colorHex: "#AABBCC"), .init(colorHex: "#DDEEFF")], mode: .dark, grain: 0.4)
        let id = UUID()
        f.tree.createSpace(id: id, name: "Research", icon: "book", accentHex: "#000000", after: f.spaceB,
                           now: fixedNow, appearance: theme, profileID: f.spaceA)
        let created = try #require(f.tree.space(id))
        #expect(created.resolvedAppearance == theme.normalized)
        #expect(created.accentHex == "#AABBCC")
        #expect(f.tree.profileIdentifier(for: id) == f.spaceA)
        let decoded = try JSONDecoder().decode(SpaceRecord.self, from: JSONEncoder().encode(created))
        #expect(decoded == created)
    }

    @Test func sharedProfileSurvivesDeletionOfItsOriginalSpace() throws {
        var f = Fixture()
        let id = UUID()
        f.tree.createSpace(id: id, name: "Shared", icon: "book", accentHex: "#AABBCC", after: f.spaceB,
                           profileID: f.spaceA)
        _ = try f.tree.deleteSpace(f.spaceA, now: fixedNow)
        #expect(f.tree.profileIdentifier(for: id) == f.spaceA)
        #expect(f.tree.usesProfile(f.spaceA))
        #expect(f.tree.profileIdentifier(for: f.spaceB) == f.spaceB)
        _ = try f.tree.deleteSpace(id, now: fixedNow)
        #expect(!f.tree.usesProfile(f.spaceA))
    }

    @Test func newProfilesStayIsolatedAndAgentsBorrowTheChosenProfile() throws {
        var f = Fixture()
        #expect(f.tree.profileIdentifier(for: f.spaceA) == f.spaceA)
        #expect(f.tree.profileIdentifier(for: f.spaceB) == f.spaceB)
        let shared = UUID()
        f.tree.createSpace(id: shared, name: "Shared", icon: "book", accentHex: "#AABBCC", after: f.spaceB,
                           profileID: f.spaceB)
        let result = f.tree.ensureAgentSpace(loginsFrom: shared, now: fixedNow)
        let agent = try #require(result)
        #expect(f.tree.profileIdentifier(for: agent.id) == f.spaceB)
        _ = try f.tree.deleteSpace(shared, now: fixedNow)
        #expect(f.tree.profileIdentifier(for: agent.id) == f.spaceA)
    }
}
