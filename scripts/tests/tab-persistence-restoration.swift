import Foundation
import SwiftData
import AppKit

// Lightweight runtime stand-ins let the exact production restoration sections run
// without constructing WebKit views, profiles or windows. Extraction lives in the shell runner.
final class Space {
    let id: UUID
    let name: String
    let icon: String
    let profileId: UUID?
    var activeTabId: UUID?
    init(id: UUID, name: String, icon: String, gradient: SpaceGradient, profileId: UUID?) {
        self.id = id; self.name = name; self.icon = icon; self.profileId = profileId
    }
}
final class Tab {
    let id: UUID
    let spaceId: UUID?
    let isPinned: Bool
    let isSpacePinned: Bool
    var folderId: UUID?
    init(_ entity: TabEntity) {
        id = entity.id; spaceId = entity.spaceId; isPinned = entity.isPinned
        isSpacePinned = entity.isSpacePinned; folderId = entity.folderId
    }
}
final class TabFolder {
    let id: UUID
    let spaceId: UUID
    let index: Int
    let isRegular: Bool
    var isOpen = false
    init(id: UUID, name: String, spaceId: UUID, icon: String, color: NSColor, index: Int = 0, isRegular: Bool) {
        self.id = id; self.spaceId = spaceId; self.index = index; self.isRegular = isRegular
    }
}
extension NSColor {
    convenience init?(hex: String) { self.init(red: 0, green: 0, blue: 0, alpha: 1) }
}
final class RestorationFixture {
    let context: ModelContext
    var spaces: [Space] = []
    var tabsBySpace: [UUID: [Tab]] = [:]
    var spacePinnedTabs: [UUID: [Tab]] = [:]
    var foldersBySpace: [UUID: [TabFolder]] = [:]
    var pinnedByProfile: [UUID: [Tab]] = [:]
    init(context: ModelContext) { self.context = context }
    func setTabs(_ tabs: [Tab], for id: UUID) { tabsBySpace[id] = tabs }
    func setSpacePinnedTabs(_ tabs: [Tab], for id: UUID) { spacePinnedTabs[id] = tabs }
    func setFolders(_ folders: [TabFolder], for id: UUID) { foldersBySpace[id] = folders }
    func essentialTabs(for id: UUID?) -> [Tab] { id.flatMap { pinnedByProfile[$0] } ?? [] }
    func allTabsAllSpaces() -> [Tab] {
        Array(tabsBySpace.values).flatMap { $0 } + Array(spacePinnedTabs.values).flatMap { $0 } + Array(pinnedByProfile.values).flatMap { $0 }
    }
    static func check() throws {
        let container = try ModelContainer(for: TabEntity.self, SpaceEntity.self, FolderEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let profile = UUID(), otherProfile = UUID()
        let a = UUID(), b = UUID(), c = UUID(), regular = UUID(), pinned = UUID(), wrongSection = UUID(), essential = UUID()
        for (index, id) in [a, b, c].enumerated() {
            context.insert(SpaceEntity(id: id, name: "Personal", icon: "house", index: index, profileId: index == 2 ? otherProfile : profile, activeTabId: essential))
        }
        let folder1 = UUID(), folder2 = UUID()
        context.insert(FolderEntity(id: folder1, name: "Later", icon: "folder", color: "blue", spaceId: a, isOpen: true, index: 7, isRegular: true))
        context.insert(FolderEntity(id: folder2, name: "Earlier", icon: "folder", color: "blue", spaceId: a, isOpen: false, index: 2))
        let entities = [
            TabEntity(id: regular, urlString: "https://example.com", name: "Valid", isPinned: false, index: 0, spaceId: a, folderId: folder1),
            TabEntity(id: pinned, urlString: "https://example.com", name: "Foreign folder", isPinned: false, isSpacePinned: true, index: 0, spaceId: b, folderId: folder2),
            TabEntity(id: wrongSection, urlString: "https://example.com", name: "Wrong section", isPinned: false, isSpacePinned: true, index: 1, spaceId: a, folderId: folder1),
            TabEntity(id: essential, urlString: "https://example.com", name: "Essential", isPinned: true, index: 0, spaceId: nil, profileId: profile)
        ]
        for entity in entities { context.insert(entity) }
        try context.save()
        let fixture = RestorationFixture(context: context)
        try fixture.loadSpaces()
        precondition(fixture.spaces.map(\.id) == [a, b, c], "Same-name spaces must survive startup within and across profiles")
        precondition(fixture.spaces.allSatisfy { $0.activeTabId == essential }, "Stored per-space selections must load")
        for entity in entities {
            let tab = Tab(entity)
            if entity.isPinned { fixture.pinnedByProfile[profile, default: []].append(tab) }
            else if entity.isSpacePinned { fixture.spacePinnedTabs[entity.spaceId!, default: []].append(tab) }
            else { fixture.tabsBySpace[entity.spaceId!, default: []].append(tab) }
        }
        try fixture.loadFoldersAndRepair()
        precondition(fixture.foldersBySpace[a]?.map(\.index) == [2, 7], "Runtime folders must retain stored order and indices")
        precondition(fixture.foldersBySpace[a]?.map(\.isOpen) == [false, true])
        precondition(fixture.allTabsAllSpaces().first { $0.id == regular }?.folderId == folder1)
        precondition(fixture.allTabsAllSpaces().first { $0.id == pinned }?.folderId == nil)
        precondition(fixture.allTabsAllSpaces().first { $0.id == wrongSection }?.folderId == nil)
        precondition(fixture.spaces[0].activeTabId == essential && fixture.spaces[1].activeTabId == essential)
        precondition(fixture.spaces[2].activeTabId == nil, "Restoration must reject another profile's essential")
        precondition(fixture.validActiveTabID(regular, in: fixture.spaces[0]) == regular)
        precondition(fixture.validActiveTabID(regular, in: fixture.spaces[1]) == nil)
        print("PASS: production startup sections preserve duplicate-named spaces, folder ordering and profile-valid selections; repair invalid folder references")
    }
}
