// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

/// A tab in the Tabs section holding the tabs opened from it.
struct TrailTests {
    @Test func onlyTabsSectionTabsHoldTabs() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("parent", in: tabs)
        #expect(f.tree.canTakeChild(parent))
        let child = f.tab("child", in: .folder(itemID: parent))
        #expect(f.tree.hasChildren(parent))
        #expect(f.tree.scope(of: child) == .device)
        #expect(f.tree.spaceID(of: child) == f.spaceA)

        #expect(throws: TreeError.folderInTab) {
            try f.tree.createFolder(title: "f", in: .folder(itemID: parent), after: nil, now: fixedNow)
        }
        let pinned = f.tab("pinned", in: .pinned(spaceID: f.spaceA))
        #expect(throws: TreeError.childOutsideTabs) {
            try f.tree.createTab(url: url("x"), title: "x", in: .folder(itemID: pinned), after: nil, now: fixedNow)
        }
        #expect(!f.tree.canTakeChild(pinned))
        let favorite = f.tab("fav", in: .favorites(spaceID: f.spaceA))
        #expect(throws: TreeError.childOutsideTabs) {
            try f.tree.createTab(url: url("x"), title: "x", in: .folder(itemID: favorite), after: nil, now: fixedNow)
        }
        // A tab inside a folder in the Tabs section still counts as the Tabs section.
        let folder = f.folder("folder", in: tabs)
        let inFolder = f.tab("in folder", in: .folder(itemID: folder))
        f.tab("grandchild", in: .folder(itemID: inFolder))
        checkInvariants(f.tree)
    }

    @Test func trailsCountTowardDepth() throws {
        var f = Fixture()
        var host = f.tab("0", in: .tabs(spaceID: f.spaceA))
        for level in 1...TabTree.maxFolderDepth {
            host = f.tab("\(level)", in: .folder(itemID: host))
        }
        // A tab may sit five levels deep, as in folders; a sixth level is refused.
        #expect(!f.tree.canTakeChild(host))
        #expect(throws: TreeError.tooDeep) {
            try f.tree.createTab(url: url("deep"), title: "deep", in: .folder(itemID: host), after: nil, now: fixedNow)
        }
        checkInvariants(f.tree)
    }

    @Test func closePromotesChildrenInOrder() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let before = f.tab("before", in: tabs)
        let parent = f.tab("parent", in: tabs)
        f.tab("after", in: tabs)
        for name in ["one", "two", "three"] { f.tab(name, in: .folder(itemID: parent)) }
        let grand = f.tree.children(of: .folder(itemID: parent))[1].id
        f.tab("grand", in: .folder(itemID: grand))

        let result = try f.tree.close(parent, promotingChildren: true, now: fixedNow)
        #expect(f.titles(tabs) == ["before", "one", "two", "three", "after"])
        #expect(f.titles(.folder(itemID: grand)) == ["grand"])
        #expect(result.closed.items.map(\.id) == [parent])
        _ = before
        checkInvariants(f.tree)

        // Undo puts the trail back exactly.
        f.tree.apply(result.change)
        #expect(f.titles(.folder(itemID: parent)) == ["one", "two", "three"])
        checkInvariants(f.tree)
    }

    @Test func closeWithoutPromotionTakesTheTrail() throws {
        var f = Fixture()
        let parent = f.tab("parent", in: .tabs(spaceID: f.spaceA))
        f.tab("child", in: .folder(itemID: parent))
        let result = try f.tree.close(parent, now: fixedNow)
        #expect(result.closed.items.count == 2)
        #expect(f.tree.children(of: .tabs(spaceID: f.spaceA)).isEmpty)

        // Reopen brings the whole trail back.
        _ = try f.tree.reopen(result.closed, fallback: .tabs(spaceID: f.spaceA), now: fixedNow)
        #expect(f.titles(.folder(itemID: parent)) == ["child"])
        checkInvariants(f.tree)
    }

    @Test func pinningAParentLeavesItsChildren() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("parent", in: tabs)
        f.tab("after", in: tabs)
        f.tab("child", in: .folder(itemID: parent))

        try f.tree.move(parent, to: .pinned(spaceID: f.spaceA), after: nil, currentURL: url("cur"), now: fixedNow)
        #expect(f.titles(.pinned(spaceID: f.spaceA)) == ["parent"])
        #expect(f.titles(tabs) == ["child", "after"])
        checkInvariants(f.tree)

        // Into a folder in the pinned section, the same.
        let trail = f.tab("trail", in: tabs)
        f.tab("leaf", in: .folder(itemID: trail))
        let pinnedFolder = f.folder("pf", in: .pinned(spaceID: f.spaceA))
        try f.tree.move(trail, to: .folder(itemID: pinnedFolder), after: nil, now: fixedNow)
        #expect(f.tree.children(of: .folder(itemID: trail)).isEmpty)
        #expect(f.titles(tabs).contains("leaf"))
        checkInvariants(f.tree)

        // A folder carrying a trail flattens it on the way into pinned.
        let folder = f.folder("folder", in: tabs)
        let inner = f.tab("inner", in: .folder(itemID: folder))
        let deep = f.tab("deep", in: .folder(itemID: inner))
        f.tab("deeper", in: .folder(itemID: deep))
        f.tab("sibling", in: .folder(itemID: folder))
        try f.tree.move(folder, to: .pinned(spaceID: f.spaceA), after: nil, now: fixedNow)
        #expect(f.titles(.folder(itemID: folder)) == ["inner", "deep", "deeper", "sibling"])
        checkInvariants(f.tree)
    }

    @Test func movingATrailWithinTabsCarriesIt() throws {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("parent", in: tabs)
        f.tab("child", in: .folder(itemID: parent))
        let folder = f.folder("folder", in: tabs)
        try f.tree.move(parent, to: .folder(itemID: folder), after: nil, now: fixedNow)
        #expect(f.titles(.folder(itemID: parent)) == ["child"])
        // A tab cannot move under its own child.
        let child = f.tree.children(of: .folder(itemID: parent))[0].id
        #expect(throws: TreeError.cycle) {
            try f.tree.move(parent, to: .folder(itemID: child), after: nil, now: fixedNow)
        }
        checkInvariants(f.tree)
    }

    @Test func rowsShowTrailsWhileOpen() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let parent = f.tab("parent", in: tabs)
        f.tab("child", in: .folder(itemID: parent))
        f.tab("next", in: tabs)

        let closed = f.tree.visibleRows(space: f.spaceA, openFolders: [])
        #expect(closed.map(\.item.displayTitle) == ["parent", "next"])
        #expect(closed.map(\.hasChildren) == [true, false])

        let open = f.tree.visibleRows(space: f.spaceA, openFolders: [parent])
        #expect(open.map(\.item.displayTitle) == ["parent", "child", "next"])
        #expect(open.map(\.depth) == [0, 1, 0])
    }

    @Test func repairLiftsChildrenThatCannotStay() {
        var f = Fixture()
        let tabs = Parent.tabs(spaceID: f.spaceA)
        let pinned = f.tab("pinned", in: .pinned(spaceID: f.spaceA))
        let host = f.tab("host", in: tabs)
        // Shapes an older or newer build could write.
        let underPinned = Item(parent: .folder(itemID: pinned), order: OrderKey.sequence(count: 1)[0],
                               kind: .tab(url: url("a"), pageTitle: "a"), modifiedAt: fixedNow)
        let folderUnderTab = Item(parent: .folder(itemID: host), order: OrderKey.sequence(count: 1)[0],
                                  kind: .folder, customTitle: "f", modifiedAt: fixedNow)
        let fine = Item(parent: .folder(itemID: host), order: OrderKey.sequence(count: 2)[1],
                        kind: .tab(url: url("b"), pageTitle: "b"), modifiedAt: fixedNow)
        f.tree.items[underPinned.id] = underPinned
        f.tree.items[folderUnderTab.id] = folderUnderTab
        f.tree.items[fine.id] = fine

        let repaired = f.tree.repair(now: fixedNow)
        #expect(repaired)
        #expect(f.tree.item(underPinned.id)?.parent == tabs)
        #expect(f.tree.item(folderUnderTab.id)?.parent == tabs)
        #expect(f.tree.item(fine.id)?.parent == .folder(itemID: host))
        checkInvariants(f.tree)
    }

    @Test func pruneKeepsOpenTrails() {
        var f = Fixture()
        let parent = f.tab("parent", in: .tabs(spaceID: f.spaceA))
        let leaf = f.tab("leaf", in: .tabs(spaceID: f.spaceA))
        f.tab("child", in: .folder(itemID: parent))
        var device = DeviceState()
        device.openFolders = [parent, leaf]
        device.prune(against: f.tree)
        #expect(device.openFolders == [parent])
    }
}
