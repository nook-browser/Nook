import Foundation
import Testing
@testable import NookTabsCore

let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

func url(_ s: String) -> URL { URL(string: "https://example.com/\(s.replacingOccurrences(of: " ", with: "-"))")! }

/// Two spaces and their sections.
struct Fixture {
    var tree = TabTree()
    let spaceA = UUID()
    let spaceB = UUID()

    init() {
        tree.createSpace(id: spaceA, name: "A", icon: "a", accentHex: "#000", after: nil, now: fixedNow)
        tree.createSpace(id: spaceB, name: "B", icon: "b", accentHex: "#000", after: spaceA, now: fixedNow)
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

/// Every rule in the spec, checked against the whole tree.
func checkInvariants(_ tree: TabTree, sourceLocation: SourceLocation = #_sourceLocation) {
    for item in tree.items.values where item.deletedAt == nil {
        // The parent exists and is a live record.
        switch item.parent {
        case .favorites(let spaceID), .pinned(let spaceID), .tabs(let spaceID):
            #expect(tree.space(spaceID) != nil, "parent space missing", sourceLocation: sourceLocation)
        case .folder(let folderID):
            #expect(tree.item(folderID)?.isFolder == true, "parent folder missing", sourceLocation: sourceLocation)
        }
        // No cycles, within the depth limit, and no folder in favorites.
        guard let chain = tree.folderChain(of: item.id) else {
            Issue.record("cycle at \(item.id)", sourceLocation: sourceLocation)
            continue
        }
        let levels = chain.folders.count + (item.isFolder ? 1 : 0)
        #expect(levels <= TabTree.maxFolderDepth, "too deep: \(levels)", sourceLocation: sourceLocation)
        if case .favorites = chain.section {
            #expect(chain.folders.isEmpty, "folder in favorites", sourceLocation: sourceLocation)
            #expect(!item.isFolder, "folder in favorites", sourceLocation: sourceLocation)
        }
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
