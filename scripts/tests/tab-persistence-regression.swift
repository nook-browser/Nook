import Foundation
import SwiftData

@main
struct TabPersistenceRegression {
    static let spaceA = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let spaceB = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let profileA = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let profileB = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let container = try ModelContainer(
            for: TabEntity.self, FolderEntity.self, SpaceEntity.self, TabsStateEntity.self,
            configurations: ModelConfiguration(url: url)
        )
#if LEGACY_SCHEMA
        let context = ModelContext(container)
        context.insert(SpaceEntity(id: spaceA, name: "Personal", icon: "house", index: 0, profileId: profileA))
        context.insert(SpaceEntity(id: spaceB, name: "Personal", icon: "house", index: 1, profileId: profileB))
        try context.save()
        print("Seeded pre-activeTabId schema")
#else
        if CommandLine.arguments.contains("verify-restart") {
            let context = ModelContext(container)
            let spaces = try context.fetch(FetchDescriptor<SpaceEntity>())
            let tabs = try context.fetch(FetchDescriptor<TabEntity>())
            let folders = try context.fetch(FetchDescriptor<FolderEntity>())
            precondition(spaces.count == 2 && tabs.count == 3 && folders.count == 1)
            for space in spaces {
                precondition(space.activeTabId != nil)
                precondition(tabs.contains { $0.id == space.activeTabId && $0.spaceId == space.id })
            }
            precondition(folders[0].index == 2 && !folders[0].isRegular)
            precondition(tabs.first { $0.spaceId == spaceB }?.folderId == folders[0].id)
            precondition(tabs.first { $0.spaceId == spaceA }?.folderId == nil)
            print("PASS: persisted selections and folder removal survive a fresh process")
        } else {
            try RestorationFixture.check()
            try await checkPersistence(container)
        }
#endif
    }

#if !LEGACY_SCHEMA
    typealias Snapshot = PersistenceActor.Snapshot
    typealias SnapshotTab = PersistenceActor.SnapshotTab
    typealias SnapshotFolder = PersistenceActor.SnapshotFolder
    typealias SnapshotSpace = PersistenceActor.SnapshotSpace

    static func checkPersistence(_ container: ModelContainer) async throws {
        let migrated = try ModelContext(container).fetch(FetchDescriptor<SpaceEntity>())
        precondition(migrated.count == 2 && migrated.allSatisfy { $0.activeTabId == nil }, "Old stores must migrate without losing spaces")
        precondition(Set(migrated.compactMap(\.profileId)) == [profileA, profileB], "Identical space names must retain profile identity")

        let actor = PersistenceActor(container: container)
        let first = UUID(), second = UUID(), essential = UUID()
        let folderA = UUID(), folderB = UUID()
        let spaces = [
            SnapshotSpace(id: spaceA, name: "Personal", icon: "house", index: 0, gradientData: nil, activeTabId: first, profileId: profileA),
            SnapshotSpace(id: spaceB, name: "Personal", icon: "house", index: 1, gradientData: nil, activeTabId: second, profileId: profileB)
        ]
        let folders = [
            SnapshotFolder(id: folderA, name: "Regular", icon: "folder", color: "blue", spaceId: spaceA, isOpen: true, index: 7, isRegular: true),
            SnapshotFolder(id: folderB, name: "Pinned", icon: "folder", color: "red", spaceId: spaceB, isOpen: false, index: 2)
        ]
        func tab(_ id: UUID, space: UUID?, folder: UUID? = nil, pinned: Bool = false, spacePinned: Bool = false, index: Int = 0) -> SnapshotTab {
            SnapshotTab(id: id, urlString: "https://example.com", name: "Test", index: index, spaceId: space,
                        isPinned: pinned, isSpacePinned: spacePinned, profileId: pinned ? profileA : nil,
                        folderId: folder, displayNameOverride: "Custom", currentURLString: "https://example.com/current",
                        canGoBack: true, canGoForward: false, pinnedURLString: nil)
        }
        let tabs = [tab(first, space: spaceA, folder: folderA), tab(second, space: spaceB, folder: folderB, spacePinned: true), tab(essential, space: nil, pinned: true)]
        func snapshot(tabs replacementTabs: [SnapshotTab]? = nil, folders replacementFolders: [SnapshotFolder]? = nil, spaces replacementSpaces: [SnapshotSpace]? = nil, state: PersistenceActor.SnapshotState? = nil) -> Snapshot {
            Snapshot(spaces: replacementSpaces ?? spaces, tabs: replacementTabs ?? tabs, folders: replacementFolders ?? folders,
                     state: state ?? .init(currentTabID: first, currentSpaceID: spaceA))
        }
        let original = snapshot()
        guard case .committed = await actor.persist(snapshot: original, generation: 1) else { fatalError("Valid snapshot must commit atomically") }
        guard case .committed = await actor.persist(snapshot: original, generation: 2) else { fatalError("Identical snapshot must count as committed") }
        guard case .stale = await actor.persist(snapshot: original, generation: 1) else { fatalError("Older generations must be reported as stale") }

        func verifyOriginal() throws {
            let context = ModelContext(container)
            let storedSpaces = try context.fetch(FetchDescriptor<SpaceEntity>())
            precondition(storedSpaces.count == 2)
            precondition(storedSpaces.first { $0.id == spaceA }?.activeTabId == first)
            precondition(storedSpaces.first { $0.id == spaceB }?.activeTabId == second)
            let storedFolders = try context.fetch(FetchDescriptor<FolderEntity>())
            precondition(storedFolders.count == 2)
            precondition(storedFolders.first { $0.id == folderA }?.index == 7)
            precondition(storedFolders.first { $0.id == folderB }?.index == 2)
            let storedTabs = try context.fetch(FetchDescriptor<TabEntity>())
            precondition(storedTabs.count == 3)
            precondition(storedTabs.first { $0.id == first }?.folderId == folderA)
            precondition(storedTabs.first { $0.id == first }?.currentURLString == "https://example.com/current")
        }
        try verifyOriginal()

        let invalid: [(String, Snapshot)] = [
            ("space selects missing tab", snapshot(spaces: [SnapshotSpace(id: spaceA, name: "Personal", icon: "house", index: 0, gradientData: nil, activeTabId: UUID(), profileId: profileA), spaces[1]])),
            ("space selects other space tab", snapshot(spaces: [SnapshotSpace(id: spaceA, name: "Personal", icon: "house", index: 0, gradientData: nil, activeTabId: second, profileId: profileA), spaces[1]])),
            ("space selects other profile essential", snapshot(spaces: [spaces[0], SnapshotSpace(id: spaceB, name: "Personal", icon: "house", index: 1, gradientData: nil, activeTabId: essential, profileId: profileB)])),
            ("state selects other profile essential", snapshot(state: .init(currentTabID: essential, currentSpaceID: spaceB))),
            ("state selects missing space", snapshot(state: .init(currentTabID: nil, currentSpaceID: UUID()))),
            ("state selects tab without space", snapshot(state: .init(currentTabID: first, currentSpaceID: nil))),
            ("duplicate tab", snapshot(tabs: tabs + [tabs[0]])),
            ("duplicate folder", snapshot(folders: folders + [folders[0]])),
            ("duplicate space", snapshot(spaces: spaces + [spaces[0]])),
            ("missing folder", snapshot(tabs: [tab(first, space: spaceA, folder: UUID()), tabs[1], tabs[2]])),
            ("folder in another space", snapshot(tabs: [tab(first, space: spaceA, folder: folderB), tabs[1], tabs[2]])),
            ("wrong folder section", snapshot(tabs: [tab(first, space: spaceA, folder: folderA, spacePinned: true), tabs[1], tabs[2]])),
            ("essential in folder", snapshot(tabs: [tabs[0], tabs[1], tab(essential, space: nil, folder: folderA, pinned: true)])),
            ("folder references missing space", snapshot(folders: [SnapshotFolder(id: folderA, name: "Bad", icon: "folder", color: "blue", spaceId: UUID(), isOpen: true, index: 0, isRegular: true), folders[1]])),
            ("negative space index", snapshot(spaces: [SnapshotSpace(id: spaceA, name: "Personal", icon: "house", index: -1, gradientData: nil, activeTabId: first, profileId: profileA), spaces[1]])),
            ("negative tab index", snapshot(tabs: [tab(first, space: spaceA, folder: folderA, index: -1), tabs[1], tabs[2]])),
            ("negative folder index", snapshot(folders: [SnapshotFolder(id: folderA, name: "Bad", icon: "folder", color: "blue", spaceId: spaceA, isOpen: true, index: -1, isRegular: true), folders[1]]))
        ]
        for (offset, entry) in invalid.enumerated() {
            guard case .failed(.invalidModelState) = await actor.persist(snapshot: entry.1, generation: offset + 3) else {
                fatalError("Invalid snapshot must be rejected before fallback: \(entry.0)")
            }
            try verifyOriginal()
        }
        // A rejected snapshot must not supersede an older valid one that arrives after it.
        guard case .failed = await actor.persist(snapshot: invalid[0].1, generation: 80) else { fatalError("Invalid snapshot must be rejected") }
        guard case .committed = await actor.persist(snapshot: original, generation: 79) else {
            fatalError("A rejected newer snapshot must not make a valid older one stale")
        }
        let essentialSelection = snapshot(spaces: [SnapshotSpace(id: spaceA, name: "Personal", icon: "house", index: 0, gradientData: nil, activeTabId: essential, profileId: profileA), spaces[1]], state: .init(currentTabID: essential, currentSpaceID: spaceA))
        guard case .committed = await actor.persist(snapshot: essentialSelection, generation: 90) else {
            fatalError("A space must be allowed to select an essential from its own profile")
        }
        let removedFolder = snapshot(tabs: [tab(first, space: spaceA), tabs[1], tabs[2]], folders: [folders[1]])
        guard case .committed = await actor.persist(snapshot: removedFolder, generation: 100) else { fatalError("Folder removal must commit") }
        let afterRemoval = ModelContext(container)
        let remainingFolders = try afterRemoval.fetch(FetchDescriptor<FolderEntity>())
        let remainingTabs = try afterRemoval.fetch(FetchDescriptor<TabEntity>())
        precondition(remainingFolders.count == 1)
        precondition(remainingTabs.first { $0.id == first }?.folderId == nil)
        print("PASS: optional-field migration, profile identity, active selections, folder order, navigation state, atomic validation, stale generations, rejected-generation recovery and folder removal")
    }
#endif
}
