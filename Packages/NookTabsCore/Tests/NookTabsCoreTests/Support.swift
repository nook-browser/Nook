import Foundation
import Testing
@testable import NookTabsCore

let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

func url(_ s: String) -> URL { URL(string: "https://example.com/\(s.replacingOccurrences(of: " ", with: "-"))")! }

/// One profile with two spaces, empty sections.
struct Fixture {
    var tree = TabTree()
    let profile = UUID()
    let spaceA = UUID()
    let spaceB = UUID()

    init() {
        tree.createProfile(id: profile, name: "P", icon: "person", now: fixedNow)
        try! tree.createSpace(id: spaceA, profileID: profile, name: "A", icon: "a", accentHex: "#000", after: nil, now: fixedNow)
        try! tree.createSpace(id: spaceB, profileID: profile, name: "B", icon: "b", accentHex: "#000", after: spaceA, now: fixedNow)
    }

    @discardableResult
    mutating func tab(_ name: String, in parent: Parent, after: UUID? = nil) -> UUID {
        let id = UUID()
        let last = after ?? tree.children(of: parent).last?.id
        try! tree.createTab(id: id, url: url(name), title: name, in: parent, after: last, now: fixedNow)
        return id
    }

    @discardableResult
    mutating func folder(_ name: String, in parent: Parent) -> UUID {
        let id = UUID()
        try! tree.createFolder(id: id, title: name, in: parent, after: tree.children(of: parent).last?.id, now: fixedNow)
        return id
    }

    func titles(_ parent: Parent) -> [String] { tree.children(of: parent).map(\.displayTitle) }
}

/// Every rule from the spec, checked against a whole tree.
func checkInvariants(_ tree: TabTree, sourceLocation: SourceLocation = #_sourceLocation) {
    for space in tree.spaces.values where space.deletedAt == nil {
        #expect(tree.profile(space.profileID) != nil, "space without live profile", sourceLocation: sourceLocation)
    }
    for item in tree.items.values where item.deletedAt == nil {
        switch item.parent {
        case .favorites(let p):
            #expect(tree.profile(p) != nil, "favorite without profile", sourceLocation: sourceLocation)
            #expect(!item.isFolder, "folder in favorites", sourceLocation: sourceLocation)
        case .pinned(let s), .tabs(let s):
            #expect(tree.space(s) != nil, "item in missing space", sourceLocation: sourceLocation)
        case .folder(let f):
            #expect(tree.item(f)?.isFolder == true, "item in missing folder", sourceLocation: sourceLocation)
        }
        guard let chain = tree.folderChain(of: item.id) else {
            Issue.record("cycle at \(item.id)", sourceLocation: sourceLocation)
            continue
        }
        let levels = chain.folders.count + (item.isFolder ? 1 : 0)
        #expect(levels <= TabTree.maxFolderDepth, "too deep: \(levels)", sourceLocation: sourceLocation)
        if case .favorites = chain.section { #expect(chain.folders.isEmpty, sourceLocation: sourceLocation) }
    }
}

/// Deterministic generator so failures replay.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
