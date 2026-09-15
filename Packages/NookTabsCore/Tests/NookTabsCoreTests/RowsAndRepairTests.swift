import Foundation
import Testing
@testable import NookTabsCore

struct RowsTests {
    @Test func visibleRowsExpandOnlyOpenFolders() {
        var f = Fixture()
        let pinned = Parent.pinned(spaceID: f.spaceA)
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let outer = f.folder("outer", in: pinned)
        let inner = f.folder("inner", in: .folder(itemID: outer))
        f.tab("deep", in: .folder(itemID: inner))
        f.tab("p1", in: pinned)
        f.tab("t1", in: tabs)

        let closed = f.tree.visibleRows(space: f.spaceA, openFolders: [])
        #expect(closed.map(\.item.displayTitle) == ["outer", "p1", "t1"])

        let open = f.tree.visibleRows(space: f.spaceA, openFolders: [outer, inner])
        #expect(open.map(\.item.displayTitle) == ["outer", "inner", "deep", "p1", "t1"])
        #expect(open.map(\.depth) == [0, 1, 2, 0, 0])
        #expect(open.map(\.section) == [.pinned, .pinned, .pinned, .pinned, .tabs])
    }

    @Test func dropTargetResolvesParentAndNeighbor() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let a = f.tab("a", in: tabs)
        let folder = f.folder("F", in: tabs)
        let child = f.tab("child", in: .folder(itemID: folder))
        let b = f.tab("b", in: tabs)
        let rows = f.tree.visibleRows(space: f.spaceA, openFolders: [folder]).filter { $0.section == .tabs }
        // rows: a, F, child, b

        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 0, intoFolder: false, dragged: nil) == (tabs, nil))
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 1, intoFolder: false, dragged: nil) == (tabs, a))
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 1, intoFolder: true, dragged: nil) == (.folder(itemID: folder), nil))
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 2, intoFolder: false, dragged: nil) == (.folder(itemID: folder), nil))
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 3, intoFolder: false, dragged: nil) == (tabs, folder))
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 4, intoFolder: false, dragged: nil) == (tabs, b))
        // Dragging b between F's child and b keeps b after F.
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 3, intoFolder: false, dragged: b) == (tabs, folder))
        // A folder cannot be dropped into itself.
        #expect(f.tree.dropTarget(section: tabs, rows: rows, index: 1, intoFolder: true, dragged: folder).parent == tabs)
        _ = child
    }
}

struct RepairTests {
    @Test func repairsOrphansCyclesDepthAndFavoriteFolders() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let pinned = Parent.pinned(spaceID: f.spaceA)

        // Orphan in a missing folder whose chain is gone entirely.
        let orphan = Item(parent: .folder(itemID: UUID()), order: OrderKey("V"), kind: .tab(url: url("o"), pageTitle: "o"))
        // Item in a tombstoned folder in the pinned section returns to the pinned root.
        let deadFolder = f.folder("dead", in: pinned)
        let survivor = f.tab("survivor", in: .folder(itemID: deadFolder))
        f.tree.items[deadFolder]?.deletedAt = fixedNow
        // Two folders pointing at each other.
        let c1 = UUID(), c2 = UUID()
        let cycleA = Item(id: c1, parent: .folder(itemID: c2), order: OrderKey("V"), kind: .folder)
        let cycleB = Item(id: c2, parent: .folder(itemID: c1), order: OrderKey("V"), kind: .folder)
        // Item in a deleted space.
        let lost = Item(parent: .tabs(spaceID: UUID()), order: OrderKey("V"), kind: .tab(url: url("l"), pageTitle: "l"))
        // Folder in favorites.
        let favFolder = Item(parent: .favorites(profileID: f.profile), order: OrderKey("V"), kind: .folder)
        // Seven nested folders.
        var parent = tabs
        var chain: [UUID] = []
        for _ in 0..<7 {
            let id = UUID()
            f.tree.items[id] = Item(id: id, parent: parent, order: OrderKey("V"), kind: .folder)
            chain.append(id)
            parent = .folder(itemID: id)
        }
        for item in [orphan, cycleA, cycleB, lost, favFolder] { f.tree.items[item.id] = item }

        let repaired = f.tree.repair(now: fixedNow)
        #expect(repaired)
        checkInvariants(f.tree)
        #expect(f.tree.item(orphan.id)?.parent == .tabs(spaceID: f.spaceA))
        #expect(f.tree.item(survivor)?.parent == pinned)
        #expect(f.tree.item(lost.id)?.parent == .tabs(spaceID: f.spaceA))
        #expect(f.tree.item(favFolder.id)?.parent == pinned)
        #expect(f.tree.item(chain[6]) != nil && f.tree.item(chain[5]) != nil)
        let repairedAgain = f.tree.repair(now: fixedNow)
        #expect(!repairedAgain)
    }

    @Test func purgesOldTombstones() {
        var f = Fixture()
        let t = f.tab("t", in: .pinned(spaceID: f.spaceA))
        f.tree.items[t]?.deletedAt = fixedNow.addingTimeInterval(-TabTree.tombstoneLifetime - 1)
        let recent = f.tab("r", in: .pinned(spaceID: f.spaceA))
        f.tree.items[recent]?.deletedAt = fixedNow
        f.tree.repair(now: fixedNow)
        #expect(f.tree.items[t] == nil)
        #expect(f.tree.items[recent] != nil)
    }

    @Test func spaceWithMissingProfileJoinsFirstProfile() {
        var f = Fixture()
        f.tree.spaces[f.spaceB]?.profileID = UUID()
        f.tree.repair(now: fixedNow)
        #expect(f.tree.space(f.spaceB)?.profileID == f.profile)
    }
}
