// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct TabTreeTests {
    @Test func createPlacesAfterSibling() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let a = f.tab("a", in: tabs)
        f.tab("c", in: tabs)
        f.tab("b", in: tabs, after: a)
        try! f.tree.createTab(url: url("first"), title: "first", in: tabs, after: nil, now: fixedNow)
        #expect(f.titles(tabs) == ["first", "a", "b", "c"])
        checkInvariants(f.tree)
    }

    @Test func scopeFollowsSection() {
        var f = Fixture()
        let pinnedFolder = f.folder("F", in: .pinned(spaceID: f.spaceA))
        let inPinned = f.tab("x", in: .folder(itemID: pinnedFolder))
        let regular = f.tab("y", in: .tabs(spaceID: f.spaceA))
        let favorite = f.tab("z", in: .favorites(spaceID: f.spaceA))
        #expect(f.tree.scope(of: inPinned) == .synced)
        #expect(f.tree.scope(of: favorite) == .synced)
        #expect(f.tree.scope(of: regular) == .device)
        #expect(f.tree.spaceID(of: favorite) == f.spaceA)
        #expect(f.tree.spaceID(of: regular) == f.spaceA)
        #expect(f.tree.spaceID(of: inPinned) == f.spaceA)

        // Moving the folder into the tabs section moves its subtree into the device scope.
        try! f.tree.move(pinnedFolder, to: .tabs(spaceID: f.spaceA), after: nil, now: fixedNow)
        #expect(f.tree.scope(of: inPinned) == .device)
        checkInvariants(f.tree)
    }

    @Test func pinSetsHomeURLFromCurrentPage() {
        var f = Fixture()
        let t = f.tab("start", in: .tabs(spaceID: f.spaceA))
        try! f.tree.move(t, to: .pinned(spaceID: f.spaceA), after: nil, currentURL: url("now"), now: fixedNow)
        #expect(f.tree.item(t)?.url == url("now"))
        // A move inside the same scope keeps the home URL.
        try! f.tree.move(t, to: .favorites(spaceID: f.spaceA), after: nil, currentURL: url("elsewhere"), now: fixedNow)
        #expect(f.tree.item(t)?.url == url("now"))
    }

    @Test func rejectsCyclesDepthAndFavoriteFolders() {
        var f = Fixture()
        var parent = Parent.pinned(spaceID: f.spaceA)
        var folders: [UUID] = []
        for i in 0..<TabTree.maxFolderDepth {
            let id = f.folder("f\(i)", in: parent)
            folders.append(id)
            parent = .folder(itemID: id)
        }
        let before = f.tree
        #expect(throws: TreeError.tooDeep) { try f.tree.createFolder(title: "six", in: parent, after: nil, now: fixedNow) }
        #expect(throws: TreeError.cycle) { try f.tree.move(folders[0], to: .folder(itemID: folders[3]), after: nil, now: fixedNow) }
        #expect(throws: TreeError.cycle) { try f.tree.move(folders[2], to: .folder(itemID: folders[2]), after: nil, now: fixedNow) }
        #expect(throws: TreeError.folderInFavorites) { try f.tree.move(folders[4], to: .favorites(spaceID: f.spaceA), after: nil, now: fixedNow) }
        #expect(throws: TreeError.missingSpace) { try f.tree.createTab(url: url("x"), title: "x", in: .tabs(spaceID: UUID()), after: nil, now: fixedNow) }
        #expect(f.tree == before)

        // A tab may sit in the deepest folder; a two-level folder may not move under level 4.
        #expect((try? f.tree.createTab(url: url("deep"), title: "deep", in: parent, after: nil, now: fixedNow)) != nil)
        let shallow = f.folder("s", in: .tabs(spaceID: f.spaceA))
        f.folder("s2", in: .folder(itemID: shallow))
        #expect(throws: TreeError.tooDeep) { try f.tree.move(shallow, to: .folder(itemID: folders[3]), after: nil, now: fixedNow) }
        #expect((try? f.tree.move(shallow, to: .folder(itemID: folders[2]), after: nil, now: fixedNow)) != nil)
        checkInvariants(f.tree)
    }

    @Test func closeTombstonesSyncedAndRemovesDevice() {
        var f = Fixture()
        let folder = f.folder("F", in: .pinned(spaceID: f.spaceA))
        let child = f.tab("c", in: .folder(itemID: folder))
        let regular = f.tab("r", in: .tabs(spaceID: f.spaceA))

        let pinnedClose = try! f.tree.close(folder, now: fixedNow)
        #expect(pinnedClose.closed.items.map(\.id) == [folder, child])
        #expect(f.tree.items[folder]?.deletedAt == fixedNow)
        #expect(f.tree.items[child]?.deletedAt == fixedNow)
        #expect(f.tree.item(child) == nil)

        _ = try! f.tree.close(regular, now: fixedNow)
        #expect(f.tree.items[regular] == nil)
        checkInvariants(f.tree)
    }

    @Test func reopenReturnsToOriginalPlaceOrFallsBack() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let folder = f.folder("F", in: tabs)
        let a = f.tab("a", in: .folder(itemID: folder))
        let b = f.tab("b", in: .folder(itemID: folder))
        f.tab("c", in: .folder(itemID: folder))

        let closedB = try! f.tree.close(b, now: fixedNow).closed
        try! f.tree.reopen(closedB, fallback: tabs, now: fixedNow)
        #expect(f.titles(.folder(itemID: folder)) == ["a", "b", "c"])

        // Folder deleted since: the tab returns to the root of the folder's section.
        let closedA = try! f.tree.close(a, now: fixedNow).closed
        _ = try! f.tree.close(folder, now: fixedNow)
        try! f.tree.reopen(closedA, fallback: .tabs(spaceID: f.spaceB), now: fixedNow)
        #expect(f.tree.item(a)?.parent == tabs)

        // SpaceRecord deleted since: the fallback parent.
        let pinnedTab = f.tab("p", in: .pinned(spaceID: f.spaceB))
        let closedP = try! f.tree.close(pinnedTab, now: fixedNow).closed
        _ = try! f.tree.deleteSpace(f.spaceB, now: fixedNow)
        try! f.tree.reopen(closedP, fallback: tabs, now: fixedNow)
        #expect(f.tree.item(pinnedTab)?.parent == tabs)
        #expect(f.tree.item(pinnedTab)?.deletedAt == nil)
        checkInvariants(f.tree)
    }

    /// A space owns its favorites now, so deleting it closes all three of its sections.
    @Test func deleteSpaceClosesFavoritesPinnedAndTabs() {
        var f = Fixture()
        f.tab("fav", in: .favorites(spaceID: f.spaceB))
        f.tab("p", in: .pinned(spaceID: f.spaceB))
        f.tab("t", in: .tabs(spaceID: f.spaceB))
        let result = try! f.tree.deleteSpace(f.spaceB, now: fixedNow)
        #expect(result.closed.count == 3)
        #expect(f.tree.space(f.spaceB) == nil)
        #expect(f.tree.favorites(of: f.spaceB).isEmpty)
        #expect(throws: TreeError.lastSpace) { try f.tree.deleteSpace(f.spaceA, now: fixedNow) }
        checkInvariants(f.tree)
    }

    /// Favorites belong to one space, so each space has its own grid.
    @Test func favoritesArePerSpace() {
        var f = Fixture()
        let a = f.tab("a", in: .favorites(spaceID: f.spaceA))
        let b = f.tab("b", in: .favorites(spaceID: f.spaceB))
        #expect(f.tree.favorites(of: f.spaceA).map(\.id) == [a])
        #expect(f.tree.favorites(of: f.spaceB).map(\.id) == [b])

        // Moving a favorite to the other space's grid stays in the synced scope.
        try! f.tree.move(a, to: .favorites(spaceID: f.spaceB), after: b, currentURL: url("cur"), now: fixedNow)
        #expect(f.tree.favorites(of: f.spaceA).isEmpty)
        #expect(f.tree.favorites(of: f.spaceB).map(\.id) == [b, a])
        #expect(f.tree.item(a)?.url == url("a"))
        #expect(f.tree.spaceID(of: a) == f.spaceB)
        checkInvariants(f.tree)
    }

    @Test func moveSpaceReorders() {
        var f = Fixture()
        #expect(f.tree.orderedSpaces.map(\.id) == [f.spaceA, f.spaceB])
        try! f.tree.moveSpace(f.spaceB, after: nil, now: fixedNow)
        #expect(f.tree.orderedSpaces.map(\.id) == [f.spaceB, f.spaceA])
        try! f.tree.moveSpace(f.spaceB, after: f.spaceA, now: fixedNow)
        #expect(f.tree.orderedSpaces.map(\.id) == [f.spaceA, f.spaceB])
        #expect(throws: TreeError.missingSpace) { try f.tree.moveSpace(UUID(), after: nil, now: fixedNow) }
    }

    @Test func renameTrimsAndClears() {
        var f = Fixture()
        let t = f.tab("page", in: .tabs(spaceID: f.spaceA))
        try! f.tree.rename(t, customTitle: "  Mine  ", now: fixedNow)
        #expect(f.tree.item(t)?.displayTitle == "Mine")
        try! f.tree.rename(t, customTitle: "   ", now: fixedNow)
        #expect(f.tree.item(t)?.customTitle == nil)
        #expect(f.tree.item(t)?.displayTitle == "page")
        #expect(try! f.tree.rename(t, customTitle: nil, now: fixedNow).isEmpty)
    }

    @Test func renumbersWhenKeysCollide() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let a = f.tab("a", in: tabs)
        let b = f.tab("b", in: tabs)
        // Force equal keys, as a merge from two devices could produce.
        let sharedOrder = f.tree.items[a]!.order
        f.tree.items[b]?.order = sharedOrder
        let before = f.tree
        let change = try! f.tree.createTab(url: url("mid"), title: "mid", in: tabs, after: f.tree.children(of: tabs)[0].id, now: fixedNow)
        #expect(f.tree.children(of: tabs).count == 3)
        #expect(Set(f.tree.children(of: tabs).map(\.order)).count == 3)
        f.tree.apply(change)
        #expect(f.tree == before)
    }

    /// Random edits never break a rule, a failed edit changes nothing, and every change undoes
    /// and redoes exactly.
    @Test(arguments: [1, 2, 3, 42, 2026] as [UInt64])
    func randomEditsKeepRulesAndUndo(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var f = Fixture()
        var closed: [ClosedEntry] = []
        var history: [Change] = []
        var applied = 0
        var deepest = 0

        for step in 0..<1_000 {
            let liveItems = f.tree.items.values.filter { $0.deletedAt == nil }.map(\.id).sorted { $0.uuidString < $1.uuidString }
            let folders = f.tree.items.values.filter { $0.deletedAt == nil && $0.isFolder }.map(\.id).sorted { $0.uuidString < $1.uuidString }
            let spaces = f.tree.orderedSpaces.map(\.id)
            func randomParent() -> Parent {
                // Folders are favored so deep nesting and depth-limit rejections both occur.
                switch Int.random(in: 0..<6, using: &rng) {
                case 0: return .favorites(spaceID: spaces.randomElement(using: &rng)!)
                case 1: return .pinned(spaceID: spaces.randomElement(using: &rng)!)
                case 2 where !folders.isEmpty, 3 where !folders.isEmpty, 4 where !folders.isEmpty:
                    return .folder(itemID: folders.randomElement(using: &rng)!)
                default: return .tabs(spaceID: spaces.randomElement(using: &rng)!)
                }
            }
            func randomAfter(_ parent: Parent) -> UUID? {
                let siblings = f.tree.children(of: parent)
                return Bool.random(using: &rng) ? nil : siblings.randomElement(using: &rng)?.id
            }

            let before = f.tree
            let op = Int.random(in: 0..<13, using: &rng)
            do {
                var change: Change?
                switch op {
                case 0, 1:
                    let p = randomParent()
                    change = try f.tree.createTab(url: url("t\(step)"), title: "t\(step)", in: p, after: randomAfter(p), now: fixedNow)
                case 2:
                    let p = randomParent()
                    change = try f.tree.createFolder(title: "f\(step)", in: p, after: randomAfter(p), now: fixedNow)
                case 3, 4:
                    guard let id = liveItems.randomElement(using: &rng) else { continue }
                    let p = randomParent()
                    change = try f.tree.move(id, to: p, after: randomAfter(p), currentURL: url("cur\(step)"), now: fixedNow)
                case 5:
                    guard let id = liveItems.randomElement(using: &rng) else { continue }
                    change = try f.tree.rename(id, customTitle: Bool.random(using: &rng) ? "n\(step)" : nil, now: fixedNow)
                case 6:
                    guard let id = liveItems.randomElement(using: &rng) else { continue }
                    let result = try f.tree.close(id, now: fixedNow)
                    closed.append(result.closed)
                    change = result.change
                case 7:
                    guard let entry = closed.popLast(), let space = spaces.first else { continue }
                    change = try f.tree.reopen(entry, fallback: .tabs(spaceID: space), now: fixedNow)
                case 8:
                    change = f.tree.createSpace(name: "s\(step)", icon: "i", accentHex: "#000",
                                                after: Bool.random(using: &rng) ? nil : spaces.randomElement(using: &rng), now: fixedNow)
                case 9:
                    let result = try f.tree.deleteSpace(spaces.randomElement(using: &rng)!, now: fixedNow)
                    closed.append(contentsOf: result.closed)
                    change = result.change
                case 10:
                    let p = randomParent()
                    change = try f.tree.createFolder(title: "g\(step)", in: p, after: randomAfter(p), now: fixedNow)
                case 11:
                    change = try f.tree.moveSpace(spaces.randomElement(using: &rng)!,
                                                  after: Bool.random(using: &rng) ? nil : spaces.randomElement(using: &rng), now: fixedNow)
                default:
                    guard let last = history.popLast() else { continue }
                    f.tree.apply(last)
                    closed.removeAll { entry in entry.items.contains { f.tree.item($0.id) != nil } }
                    checkInvariants(f.tree)
                    continue
                }
                guard let change else { continue }
                checkInvariants(f.tree)

                // Undo restores the prior tree, redo restores the new one.
                let after = f.tree
                let redo = f.tree.apply(change)
                #expect(f.tree == before, "undo mismatch at step \(step) op \(op)")
                f.tree.apply(redo)
                #expect(f.tree == after, "redo mismatch at step \(step) op \(op)")
                history.append(change)
                applied += 1
                deepest = max(deepest, f.tree.items.values.filter { $0.deletedAt == nil }.map { f.tree.folderDepth(of: $0.id) }.max() ?? 0)
            } catch {
                #expect(f.tree == before, "failed op \(op) at step \(step) changed the tree: \(error)")
            }
        }
        #expect(applied > 400, "only \(applied) edits succeeded; the generator is too restrictive")
        #expect(deepest >= 3, "nesting only reached depth \(deepest)")
    }
}
