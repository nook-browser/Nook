#!/usr/bin/env python3
"""Run real TabManager transfer methods with Foundation-only model fixtures (no WebViews)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Nook/Managers/TabManager/TabManager.swift').read_text()

def declaration(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    result = source[start:end]
    if marker in ('private func restoreClosedTab(', 'private func regularGroupTabs('):
        result = result.replace('private func', 'func', 1)  # called directly by the checks
    return '@discardableResult\n' + result if marker == 'private func transferTab(' else result

methods = [
    'private enum TabTransferDestination', 'private func transferTab(',
    'private func removeFromCurrentContainer(', 'func handleDragOperation(',
    'func moveTabToFolder(', 'func pinTab(',
    'func unpinTab(', 'func pinTabToSpace(', 'func unpinTabFromSpace(',
    'func moveTab(_ tabId:', 'private func restoreClosedTab(', 'private func regularGroupTabs(',
    'func cleanupProfileReferences(', 'func essentialTabs(for',
]
fixture = r'''
import Foundation
final class Tab {
    let id = UUID()
    var index = 0
    var spaceId: UUID?
    var profileId: UUID?
    var folderId: UUID?
    var isPinned = false
    var isSpacePinned = false
    var url = URL(string: "https://example.com")!
    var pinnedURL: URL?
}
final class Space {
    let id = UUID()
    var profileId: UUID?
    var activeTabId: UUID?
    init(_ profileId: UUID) { self.profileId = profileId }
}
final class TabFolder {
    let id = UUID()
    let spaceId: UUID
    let isRegular: Bool
    init(_ spaceId: UUID, _ regular: Bool) { self.spaceId = spaceId; isRegular = regular }
}
struct Profile { let id = UUID() }
final class SplitManager {
    enum Side { case left, right }
    func isSplit(for id: UUID) -> Bool { false }
    func leftTabId(for id: UUID) -> UUID? { nil }
    func rightTabId(for id: UUID) -> UUID? { nil }
    func exitSplit(keep: Side, for id: UUID) {}
    var closed: [UUID] = []
    func handleTabClosure(_ id: UUID) { closed.append(id) }
}
final class WindowState { var currentTabId: UUID? }
final class Registry { var windows: [UUID: WindowState] = [:] }
final class ProfileManager { var profiles: [Profile] = [] }
final class BrowserManager {
    var currentProfile: Profile? = Profile()
    var splitManager = SplitManager()
    var windowRegistry: Registry? = Registry()
    var profileManager = ProfileManager()
    var selected: [(UUID, WindowState)] = []
    func selectTab(_ tab: Tab, in window: WindowState) { selected.append((tab.id, window)); window.currentTabId = tab.id }
}
enum TabDragManager {
    enum DragContainer: Equatable {
        case none, essentials, spacePinned(UUID), spaceRegular(UUID), folder(UUID)
    }
}
struct DragOperation {
    let tab: Tab
    let fromContainer: TabDragManager.DragContainer
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int
}
final class TabManager {
    var browserManager: BrowserManager? = BrowserManager()
    var spaces: [Space] = []
    var currentSpace: Space? { spaces.first }
    var tabsBySpace: [UUID: [Tab]] = [:]
    var spacePinnedTabs: [UUID: [Tab]] = [:]
    var pinnedByProfile: [UUID: [Tab]] = [:]
    var foldersBySpace: [UUID: [TabFolder]] = [:]
    var saves = 0
    var allPinnedTabsAllProfiles: [Tab] { pinnedByProfile.values.flatMap { $0 } }
    func allTabs() -> [Tab] { tabsBySpace.values.flatMap { $0 } + spacePinnedTabs.values.flatMap { $0 } + allPinnedTabsAllProfiles }
    func contains(_ tab: Tab) -> Bool { allTabs().contains { $0.id == tab.id } }
    func tabById(_ id: UUID) -> Tab? { allTabs().first { $0.id == id } }
    func setTabs(_ tabs: [Tab], for id: UUID) { tabsBySpace[id] = tabs.sorted { $0.index < $1.index } }
    func setSpacePinnedTabs(_ tabs: [Tab], for id: UUID) { spacePinnedTabs[id] = tabs.sorted { $0.index < $1.index } }
    func setPinnedTabs(_ tabs: [Tab], for id: UUID) { pinnedByProfile[id] = tabs.sorted { $0.index < $1.index } }
    func debouncedPersistSnapshot() { saves += 1 }
    // Production addTab: append into the tab's space, or the current space when it is gone.
    func addTab(_ tab: Tab) {
        if contains(tab) { return }
        if tab.spaceId == nil || !spaces.contains(where: { $0.id == tab.spaceId }) { tab.spaceId = currentSpace?.id }
        guard let sid = tab.spaceId else { return }
        var arr = tabsBySpace[sid] ?? []
        arr.append(tab)
        setTabs(arr, for: sid)
    }
    func handleProfileSwitch() {}
    func persistSnapshot() { saves += 1 }
'''
checks = r'''
}
func fixture() -> (TabManager, [TabDragManager.DragContainer]) {
    let m = TabManager()
    let space = Space(m.browserManager!.currentProfile!.id)
    let other = Space(UUID())
    m.spaces = [space, other]
    let regular = TabFolder(space.id, true)
    let pinned = TabFolder(space.id, false)
    m.foldersBySpace[space.id] = [regular, pinned]
    return (m, [.essentials, .spaceRegular(space.id), .spacePinned(space.id), .folder(regular.id), .folder(pinned.id)])
}
func move(_ m: TabManager, _ tab: Tab, _ from: TabDragManager.DragContainer, _ to: TabDragManager.DragContainer, _ index: Int = 0) {
    m.handleDragOperation(DragOperation(tab: tab, fromContainer: from, toContainer: to, toIndex: index))
}
func validate(_ m: TabManager) {
    let all = m.allTabs()
    assert(all.count == Set(all.map { $0.id }).count, "Duplicate membership")
    for (id, tabs) in m.tabsBySpace {
        for (i, t) in tabs.enumerated() {
            assert(t.spaceId == id && t.profileId == nil && !t.isPinned && !t.isSpacePinned && t.index == i)
            if let folder = t.folderId { assert(m.foldersBySpace[id]!.contains { $0.id == folder && $0.isRegular }) }
        }
    }
    for (id, tabs) in m.spacePinnedTabs {
        for (i, t) in tabs.enumerated() {
            assert(t.spaceId == id && t.profileId == nil && !t.isPinned && t.isSpacePinned && t.index == i && t.pinnedURL != nil)
            if let folder = t.folderId { assert(m.foldersBySpace[id]!.contains { $0.id == folder && !$0.isRegular }) }
        }
    }
    for tabs in m.pinnedByProfile.values {
        for (i, t) in tabs.enumerated() { assert(t.isPinned && t.profileId != nil && !t.isSpacePinned && t.spaceId == nil && t.folderId == nil && t.index == i && t.pinnedURL != nil) }
    }
}
// All 25 source/destination combinations, including both folder types and essentials.
for fromIndex in 0..<5 {
    for toIndex in 0..<5 {
        let (m, destinations) = fixture()
        let before = Tab(), t = Tab(), after = Tab()
        for (i, tab) in [before, t, after].enumerated() { tab.spaceId = m.spaces[0].id; tab.index = i }
        m.tabsBySpace[m.spaces[0].id] = [before, t, after]
        for tab in [before, t, after] { move(m, tab, destinations[1], destinations[fromIndex], Int.max) }
        move(m, t, destinations[fromIndex], destinations[toIndex])
        validate(m)
        assert(m.allTabs().count == 3)
        switch destinations[toIndex] {
        case .essentials: assert(t.isPinned)
        case .spaceRegular: assert(!t.isPinned && !t.isSpacePinned && t.folderId == nil)
        case .spacePinned: assert(t.isSpacePinned && t.folderId == nil)
        case .folder(let id): assert(t.folderId == id)
        case .none: fatalError()
        }
    }
}
// Folder-local reorder indices must not reorder against unrelated loose/folder tabs.
for regular in [true, false] {
    let (m, destinations) = fixture()
    let folder = m.foldersBySpace[m.spaces[0].id]!.first { $0.isRegular == regular }!
    let a = Tab(), b = Tab(), loose = Tab()
    for (i, tab) in [loose, a, b].enumerated() { tab.spaceId = m.spaces[0].id; tab.index = i }
    m.tabsBySpace[m.spaces[0].id] = [loose, a, b]
    m.moveTabToFolder(tab: a, folderId: folder.id)
    m.moveTabToFolder(tab: b, folderId: folder.id)
    move(m, a, .folder(folder.id), .folder(folder.id), 1)
    let bucket = regular ? m.tabsBySpace[m.spaces[0].id]! : m.spacePinnedTabs[m.spaces[0].id]!
    assert(bucket.filter { $0.folderId == folder.id }.map { $0.id } == [b.id, a.id])
    move(m, a, .folder(folder.id), destinations[1], 0)
    assert(m.tabsBySpace[m.spaces[0].id]!.filter { $0.folderId == nil }.map { $0.id } == [a.id, loose.id])
    validate(m)
}
// Cross-space move clears folder and stale selection. Invalid destination leaves source untouched.
do {
    let (m, _) = fixture()
    let t = Tab(); t.spaceId = m.spaces[0].id
    m.tabsBySpace[t.spaceId!] = [t]
    m.spaces[0].activeTabId = t.id
    m.moveTabToFolder(tab: t, folderId: m.foldersBySpace[t.spaceId!]![0].id)
    let folder = t.folderId
    let saves = m.saves
    m.moveTabToFolder(tab: t, folderId: UUID())
    m.moveTab(t.id, to: UUID())
    assert(t.folderId == folder && m.allTabs().count == 1 && m.saves == saves)
    m.moveTab(t.id, to: m.spaces[1].id)
    assert(t.folderId == nil && t.spaceId == m.spaces[1].id && m.spaces[0].activeTabId == nil)
    validate(m)
}
// Menu pin/unpin transitions also clear folders, normalize flags, and preserve ownership.
do {
    let (m, _) = fixture()
    let t = Tab(); t.spaceId = m.spaces[0].id
    m.tabsBySpace[t.spaceId!] = [t]
    m.moveTabToFolder(tab: t, folderId: m.foldersBySpace[t.spaceId!]![1].id)
    assert(t.isSpacePinned)
    m.unpinTabFromSpace(t)
    assert(t.folderId == nil && !t.isSpacePinned && t.pinnedURL == nil)
    m.pinTabToSpace(t, spaceId: m.spaces[0].id)
    m.pinTab(t)
    validate(m)
    m.unpinTab(t)
    validate(m)
    let saves = m.saves
    m.browserManager!.currentProfile = nil
    m.pinTab(t)
    assert(m.saves == saves && !t.isPinned && m.allTabs().count == 1)
}
// Unpin with no destination must not discard an essential. Repair duplicate sources.
do {
    let (m, _) = fixture()
    let t = Tab(); t.spaceId = m.spaces[0].id
    m.tabsBySpace[t.spaceId!] = [t, t]
    m.spacePinnedTabs[t.spaceId!] = [t]
    m.pinTab(t)
    validate(m)
    m.spaces = []
    m.unpinTab(t)
    assert(m.allTabs().count == 1 && t.isPinned)
}
// Undo restores into the original container, or a loose tab when that container is gone.
do {
    let (m, _) = fixture()
    let space = m.spaces[0]
    let regularFolder = m.foldersBySpace[space.id]![0], pinnedFolder = m.foldersBySpace[space.id]![1]
    func closedCopy(folder: UUID?, spacePinned: Bool = false, essential: Bool = false, spaceId: UUID?) -> Tab {
        let t = Tab()
        t.spaceId = spaceId; t.folderId = folder; t.isSpacePinned = spacePinned; t.isPinned = essential
        t.profileId = essential ? m.browserManager!.currentProfile!.id : nil
        return t
    }
    let inFolder = closedCopy(folder: regularFolder.id, spaceId: space.id)
    m.restoreClosedTab(inFolder)
    assert(inFolder.folderId == regularFolder.id && !inFolder.isSpacePinned)
    let pinnedInFolder = closedCopy(folder: pinnedFolder.id, spacePinned: true, spaceId: space.id)
    m.restoreClosedTab(pinnedInFolder)
    assert(pinnedInFolder.folderId == pinnedFolder.id && pinnedInFolder.isSpacePinned)
    let spacePinned = closedCopy(folder: nil, spacePinned: true, spaceId: space.id)
    m.restoreClosedTab(spacePinned)
    assert(spacePinned.isSpacePinned && spacePinned.folderId == nil)
    let essential = closedCopy(folder: nil, essential: true, spaceId: nil)
    m.restoreClosedTab(essential)
    assert(essential.isPinned && m.essentialTabs(for: essential.profileId).contains { $0.id == essential.id })
    let deletedFolder = closedCopy(folder: UUID(), spaceId: space.id)
    m.restoreClosedTab(deletedFolder)
    assert(deletedFolder.folderId == nil && deletedFolder.spaceId == space.id && !deletedFolder.isSpacePinned)
    let deletedSpace = closedCopy(folder: nil, spaceId: UUID())
    m.restoreClosedTab(deletedSpace)
    assert(deletedSpace.spaceId == m.currentSpace!.id && m.allTabs().contains { $0.id == deletedSpace.id })
    validate(m)
}
// Bulk-close groups: a folder's tabs and loose tabs are separate groups in the sidebar.
do {
    let (m, _) = fixture()
    let space = m.spaces[0]
    let a = Tab(), b = Tab(), c = Tab(), f1 = Tab(), f2 = Tab()
    for (i, tab) in [a, b, c, f1, f2].enumerated() { tab.spaceId = space.id; tab.index = i }
    m.tabsBySpace[space.id] = [a, b, c, f1, f2]
    m.moveTabToFolder(tab: f1, folderId: m.foldersBySpace[space.id]![0].id)
    m.moveTabToFolder(tab: f2, folderId: m.foldersBySpace[space.id]![0].id)
    assert(m.regularGroupTabs(of: b).map { $0.id } == [a.id, b.id, c.id])
    assert(m.regularGroupTabs(of: f1).map { $0.id } == [f1.id, f2.id])
}
// Deleting a profile moves its favorites and spaces to a surviving profile, even when it is first.
do {
    let (m, _) = fixture()
    let doomed = m.browserManager!.currentProfile!, survivor = Profile()
    m.browserManager!.profileManager.profiles = [doomed, survivor]
    let fav = Tab(); fav.spaceId = m.spaces[0].id
    m.tabsBySpace[m.spaces[0].id] = [fav]
    m.pinTab(fav)
    let doomedSpace = Space(doomed.id)
    m.spaces.append(doomedSpace)
    m.cleanupProfileReferences(doomed.id)
    assert(m.essentialTabs(for: doomed.id).isEmpty && m.essentialTabs(for: survivor.id).map { $0.id } == [fav.id])
    assert(fav.profileId == survivor.id)
    validate(m)
}
print("PASS: 25 container transitions, folder/loose ordering, invalid destinations, cross-space selection, duplicate repair, no-space unpin, undo restore targets, bulk-close groups, profile deletion")
'''
with tempfile.TemporaryDirectory(prefix='nook-tab-transfer-') as tmp:
    path = Path(tmp) / 'main.swift'
    path.write_text(fixture + '\n'.join(declaration(m) for m in methods) + checks)
    subprocess.run(['swift', str(path)], check=True)
