// Licensed under GPL-3.0. See LICENSE.
// Run: swiftc Packages/NookTabsCore/Sources/NookTabsCore/*.swift Packages/NookTabsCore/Checks/SpaceAppearanceCheck.swift -o /tmp/nook-appearance-check && /tmp/nook-appearance-check
import Foundation

@main
struct SpaceAppearanceCheck {
    static func main() throws {
        let oldJSON = """
        {"id":"00000000-0000-0000-0000-000000000099","name":"Work","icon":"house","accentHex":"#123456","order":"V","modifiedAt":0}
        """
        let old = try JSONDecoder().decode(SpaceRecord.self, from: Data(oldJSON.utf8))
        precondition(old.appearance == nil)
        precondition(old.resolvedAppearance.nodes[0].colorHex == "#123456")
        precondition(old.resolvedAppearance == old.resolvedAppearance)
        precondition(SpaceAppearance(accentHex: "#abc").normalized.nodes[0].colorHex == "#AABBCC")

        let appearance = SpaceAppearance(nodes: [
            .init(colorHex: "#AABBCC", x: 0.1, y: 0.7),
            .init(colorHex: "#DDEEFF", x: 0.8, y: 0.3)
        ], mode: .dark, grain: 0.4, opacity: 0.7)
        var tree = TabTree(spaces: [old])
        let change = try tree.updateSpaceAppearance(old.id, appearance: appearance, now: Date(timeIntervalSince1970: 42))
        let updated = tree.space(old.id)!
        precondition(updated.name == old.name && updated.icon == old.icon && updated.order == old.order)
        precondition(updated.accentHex == "#AABBCC" && updated.appearance == appearance)
        precondition(updated.modifiedAt == Date(timeIntervalSince1970: 42))
        let roundTrip = try JSONDecoder().decode(SpaceRecord.self, from: JSONEncoder().encode(updated))
        precondition(roundTrip == updated)
        tree.apply(change)
        precondition(tree.space(old.id) == old)
        try tree.updateSpaceAppearance(old.id, appearance: appearance)
        try tree.updateSpace(old.id, accentHex: "#112233")
        precondition(tree.space(old.id)?.appearance?.nodes[0].colorHex == "#112233")
        precondition(tree.space(old.id)?.appearance?.nodes[1] == appearance.nodes[1])
        precondition(tree.space(old.id)?.appearance?.grain == appearance.grain)

        let id = UUID()
        let malformed = SpaceAppearance(nodes: [
            .init(id: id, colorHex: "invalid", x: .nan, y: .infinity),
            .init(id: id, colorHex: "abcdef", x: -1, y: 2),
            .init(colorHex: "#123456"), .init(colorHex: "#654321")
        ], grain: .infinity, opacity: .nan).normalized
        precondition(malformed.nodes.count == 3)
        precondition(Set(malformed.nodes.map(\.id)).count == 3)
        precondition(malformed.nodes[0].colorHex == "#3A8FA3")
        precondition(malformed.nodes[0].x == 0.25 && malformed.nodes[0].y == 0.25)
        precondition(malformed.nodes[1].x == 0 && malformed.nodes[1].y == 1)
        precondition(malformed.nodes[1].colorHex == "#ABCDEF")
        precondition(malformed.grain == 0 && malformed.opacity == 0.65)
        precondition(malformed == malformed.normalized)
        precondition(SpaceAppearance(nodes: [], grain: -1, opacity: 9).normalized.nodes.isEmpty)
        precondition(SpaceAppearance(nodes: [], grain: 9, opacity: -1).normalized.opacity == 0.3)
        _ = try JSONEncoder().encode(malformed)
        print("SpaceAppearance checks passed")
    }
}
