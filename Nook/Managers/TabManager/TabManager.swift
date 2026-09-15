import AppKit
import Combine
import Observation
import SwiftData
import WebKit
import OSLog

// MARK: - Persistence Actor & Types

/// Serializes all SwiftData writes for Tab snapshots and provides
/// atomic saves using a fresh ModelContext for each attempt.
actor PersistenceActor {
    private let container: ModelContainer
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "TabPersistence")

    // Last snapshot committed atomically. Only this actor writes these entities, so an
    // identical snapshot has nothing to change on disk.
    private var lastCommittedJSON: Data?

    enum PersistenceError: Error, Sendable {
        case concurrencyConflict
        case dataCorruption
        case storageFailure
        case rollbackFailed
        case invalidModelState
    }

    enum SaveResult: Sendable {
        case committed
        case fallbackCommitted
        case stale
        case failed(PersistenceError)
    }

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Snapshot Types
    struct SnapshotTab: Codable {
        let id: UUID
        let urlString: String
        let name: String
        let index: Int
        let spaceId: UUID?
        let isPinned: Bool
        let isSpacePinned: Bool
        // Profile association for global pinned tabs; nil for space tabs
        let profileId: UUID?
        // Folder association for tabs within folders
        let folderId: UUID?
        // Display name override (user or AI-assigned custom tab name)
        let displayNameOverride: String?

        // Navigation state
        let currentURLString: String?
        let canGoBack: Bool
        let canGoForward: Bool

        // Pinned tab home URL
        let pinnedURLString: String?
    }

    struct SnapshotFolder: Codable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let spaceId: UUID
        let isOpen: Bool
        let index: Int
        let isRegular: Bool

        init(id: UUID, name: String, icon: String, color: String, spaceId: UUID, isOpen: Bool, index: Int, isRegular: Bool = false) {
            self.id = id
            self.name = name
            self.icon = icon
            self.color = color
            self.spaceId = spaceId
            self.isOpen = isOpen
            self.index = index
            self.isRegular = isRegular
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            icon = try container.decode(String.self, forKey: .icon)
            color = try container.decode(String.self, forKey: .color)
            spaceId = try container.decode(UUID.self, forKey: .spaceId)
            isOpen = try container.decode(Bool.self, forKey: .isOpen)
            index = try container.decode(Int.self, forKey: .index)
            isRegular = try container.decodeIfPresent(Bool.self, forKey: .isRegular) ?? false
        }
    }

    struct SnapshotSpace: Codable {
        let id: UUID
        let name: String
        let icon: String
        let index: Int
        let gradientData: Data?
        let activeTabId: UUID?
        let profileId: UUID?
    }

    struct SnapshotState: Codable {
        let currentTabID: UUID?
        let currentSpaceID: UUID?
    }

    struct Snapshot: Codable {
        let spaces: [SnapshotSpace]
        let tabs: [SnapshotTab]
        let folders: [SnapshotFolder]
        let state: SnapshotState
    }

    // Coalescing control
    private var latestGeneration: Int = 0

    // MARK: - Public API (Actor)
    func persist(snapshot: Snapshot, generation: Int) -> SaveResult {
        guard generation >= latestGeneration else { return .stale }
        let interval = BrowserPerformance.signposter.beginInterval("TabPersistence")
        defer { BrowserPerformance.signposter.endInterval("TabPersistence", interval) }
        let encoded: Data
        do {
            // Invalid snapshots must never reach a less strict recovery path.
            try validateInput(snapshot)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoded = try encoder.encode(snapshot)
        } catch {
            let failure = classify(error)
            Self.log.fault("[persist] Rejected snapshot: \(String(describing: failure), privacy: .public)")
            return .failed(failure)
        }
        // Only a valid snapshot supersedes older ones; a rejected one must not block them.
        latestGeneration = generation
        if encoded == lastCommittedJSON { return .committed }
        do {
            try performAtomicPersistence(snapshot)
            lastCommittedJSON = encoded
            return .committed
        } catch {
            let failure = classify(error)
            Self.log.error("[persist] Save failed: \(String(describing: failure), privacy: .public)")
            switch failure {
            case .concurrencyConflict, .storageFailure:
                // Retry the complete transaction in a fresh context. Never omit folders
                // or bypass validation, and leave the previous committed store intact.
                do {
                    try performAtomicPersistence(snapshot)
                    lastCommittedJSON = encoded
                    return .fallbackCommitted
                } catch {
                    let retryFailure = classify(error)
                    Self.log.error("[persist] Retry failed: \(String(describing: retryFailure), privacy: .public)")
                    return .failed(retryFailure)
                }
            case .invalidModelState, .dataCorruption, .rollbackFailed:
                return .failed(failure)
            }
        }
    }

    // MARK: - Atomic Transaction Helper
    private func performAtomicPersistence(_ snapshot: Snapshot) throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Validate inputs before writing
        try validateInput(snapshot)

        // Pre-fetch all entities into lookup dictionaries to avoid N+1 queries in upsert loops
        let allTabEntities: [TabEntity]
        let allFolderEntities: [FolderEntity]
        let allSpaceEntities: [SpaceEntity]
        do {
            allTabEntities = try ctx.fetch(FetchDescriptor<TabEntity>())
            allFolderEntities = try ctx.fetch(FetchDescriptor<FolderEntity>())
            allSpaceEntities = try ctx.fetch(FetchDescriptor<SpaceEntity>())
        } catch {
            throw classify(error)
        }

        // Ids are unique in the store today; never trap on a duplicate row regardless.
        let tabLookup = Dictionary(allTabEntities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let folderLookup = Dictionary(allFolderEntities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let spaceLookup = Dictionary(allSpaceEntities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 1) Cleanup orphan TabEntities
        let keepTabIDs = Set(snapshot.tabs.map { $0.id })
        for e in allTabEntities where !keepTabIDs.contains(e.id) { ctx.delete(e) }

        // 2) Upsert tabs: global pinned, space pinned, and regular
        for tab in snapshot.tabs {
            try upsertTab(in: ctx, tab, existing: tabLookup[tab.id])
        }

        // 3) Upsert folders and cleanup removed folders
        for folder in snapshot.folders {
            try upsertFolder(in: ctx, folder, existing: folderLookup[folder.id])
        }
        let keepFolderIDs = Set(snapshot.folders.map { $0.id })
        for e in allFolderEntities where !keepFolderIDs.contains(e.id) { ctx.delete(e) }

        // 4) Upsert spaces and cleanup removed spaces
        for space in snapshot.spaces {
            try upsertSpace(in: ctx, space, existing: spaceLookup[space.id])
        }
        let keepSpaceIDs = Set(snapshot.spaces.map { $0.id })
        for e in allSpaceEntities where !keepSpaceIDs.contains(e.id) { ctx.delete(e) }

        // 5) Upsert state
        do {
            let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first ?? {
                let s = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
                ctx.insert(s)
                return s
            }()
            state.currentTabID = snapshot.state.currentTabID
            state.currentSpaceID = snapshot.state.currentSpaceID
        } catch {
            throw classify(error)
        }

        // 6) Integrity validation before save (so failures abort atomically)
        try validateDataIntegrity(in: ctx, snapshot: snapshot)

        // 7) Save (commit atomic set). The pre-save check already read the pending state,
        // so a post-save re-fetch would only repeat it.
        do {
            try ctx.save()
        } catch {
            throw classify(error)
        }
    }

    // MARK: - Entity Ops
    private func upsertTab(in ctx: ModelContext, _ t: SnapshotTab, existing: TabEntity? = nil) throws {
        if let e = existing {
            e.urlString = t.urlString
            e.name = t.name
            e.isPinned = t.isPinned
            e.isSpacePinned = t.isSpacePinned
            e.index = t.index
            e.spaceId = t.spaceId
            e.profileId = t.profileId
            e.folderId = t.folderId
            e.displayNameOverride = t.displayNameOverride
            e.currentURLString = t.currentURLString
            e.canGoBack = t.canGoBack
            e.canGoForward = t.canGoForward
            e.pinnedURLString = t.pinnedURLString
        } else {
            let e = TabEntity(
                id: t.id,
                urlString: t.urlString,
                name: t.name,
                isPinned: t.isPinned,
                isSpacePinned: t.isSpacePinned,
                index: t.index,
                spaceId: t.spaceId,
                profileId: t.profileId,
                folderId: t.folderId,
                displayNameOverride: t.displayNameOverride,
                currentURLString: t.currentURLString,
                canGoBack: t.canGoBack,
                canGoForward: t.canGoForward,
                pinnedURLString: t.pinnedURLString
            )
            ctx.insert(e)
        }
    }

    private func upsertFolder(in ctx: ModelContext, _ f: SnapshotFolder, existing: FolderEntity? = nil) throws {
        if let e = existing {
            e.name = f.name
            e.icon = f.icon
            e.color = f.color
            e.spaceId = f.spaceId
            e.isOpen = f.isOpen
            e.index = f.index
            e.isRegular = f.isRegular
        } else {
            let e = FolderEntity(
                id: f.id,
                name: f.name,
                icon: f.icon,
                color: f.color,
                spaceId: f.spaceId,
                isOpen: f.isOpen,
                index: f.index,
                isRegular: f.isRegular
            )
            ctx.insert(e)
        }
    }

    private func upsertSpace(in ctx: ModelContext, _ s: SnapshotSpace, existing: SpaceEntity? = nil) throws {
        if let e = existing {
            e.name = s.name
            e.icon = s.icon
            e.index = s.index
            if let data = s.gradientData { e.gradientData = data }
            e.profileId = s.profileId
            e.activeTabId = s.activeTabId
        } else {
            let e = SpaceEntity(
                id: s.id,
                name: s.name,
                icon: s.icon,
                index: s.index,
                gradientData: s.gradientData ?? (SpaceGradient.default.encoded ?? Data()),
                profileId: s.profileId,
                activeTabId: s.activeTabId
            )
            ctx.insert(e)
        }
    }

    // MARK: - Validation
    private func validateInput(_ snapshot: Snapshot) throws {
        let tabs = Dictionary(snapshot.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let spaces = Dictionary(snapshot.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let folders = Dictionary(snapshot.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard tabs.count == snapshot.tabs.count,
              spaces.count == snapshot.spaces.count,
              folders.count == snapshot.folders.count,
              snapshot.tabs.allSatisfy({ $0.index >= 0 }),
              snapshot.spaces.allSatisfy({ $0.index >= 0 }),
              snapshot.folders.allSatisfy({ $0.index >= 0 }) else {
            throw PersistenceError.invalidModelState
        }
        for folder in snapshot.folders {
            guard spaces[folder.spaceId] != nil else { throw PersistenceError.invalidModelState }
        }
        for tab in snapshot.tabs {
            guard !(tab.isPinned && tab.isSpacePinned) else { throw PersistenceError.invalidModelState }
            if tab.isPinned {
                guard tab.spaceId == nil, tab.folderId == nil, tab.profileId != nil else {
                    throw PersistenceError.invalidModelState
                }
            } else {
                guard let sid = tab.spaceId, spaces[sid] != nil else { throw PersistenceError.invalidModelState }
            }
            if let fid = tab.folderId {
                guard let folder = folders[fid], folder.spaceId == tab.spaceId,
                      folder.isRegular == !tab.isSpacePinned else { throw PersistenceError.invalidModelState }
            }
        }
        func isVisible(_ tabID: UUID, in space: SnapshotSpace) -> Bool {
            guard let tab = tabs[tabID] else { return false }
            return tab.spaceId == space.id || (tab.isPinned && tab.profileId == space.profileId)
        }
        for space in snapshot.spaces {
            if let active = space.activeTabId, !isVisible(active, in: space) {
                throw PersistenceError.invalidModelState
            }
        }
        if let sid = snapshot.state.currentSpaceID, spaces[sid] == nil {
            throw PersistenceError.invalidModelState
        }
        if let active = snapshot.state.currentTabID {
            guard let sid = snapshot.state.currentSpaceID, let space = spaces[sid],
                  isVisible(active, in: space) else { throw PersistenceError.invalidModelState }
        }
    }

    private func validateDataIntegrity(in ctx: ModelContext, snapshot: Snapshot) throws {
        // Fetch back a small subset to ensure relationships look sane
        do {
            let tabs: [TabEntity] = try ctx.fetch(FetchDescriptor<TabEntity>())
            let spaces: [SpaceEntity] = try ctx.fetch(FetchDescriptor<SpaceEntity>())
            let spaceIDs = Set(spaces.map { $0.id })
            for t in tabs {
                if let sid = t.spaceId, !spaceIDs.contains(sid) {
                    throw PersistenceError.dataCorruption
                }
            }
        } catch {
            throw classify(error)
        }
    }

    // MARK: - Error Classification
    private func classify(_ error: Error) -> PersistenceError {
        if let failure = error as? PersistenceError { return failure }
        let ns = error as NSError
        let domain = ns.domain.lowercased()
        let desc = (ns.userInfo[NSLocalizedDescriptionKey] as? String)?.lowercased() ?? ns.localizedDescription.lowercased()

        if domain.contains("swiftdata") || domain.contains("coredata") {
            if desc.contains("conflict") || desc.contains("busy") || desc.contains("locked") { return .concurrencyConflict }
            if desc.contains("corrupt") || desc.contains("malformed") { return .dataCorruption }
            if desc.contains("rollback") { return .rollbackFailed }
            return .storageFailure
        }
        return .storageFailure
    }
}

@MainActor
class TabManager: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "TabManager")

    enum TabManagerError: LocalizedError {
        case spaceNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .spaceNotFound(let id):
                return "Space with id \(id.uuidString) was not found."
            }
        }
    }
    weak var browserManager: BrowserManager?
    weak var nookSettings: NookSettingsService?
    private let context: ModelContext
    private let persistence: PersistenceActor

    // Tab closure undo tracking - stores snapshot of tab state at closure time
    private var recentlyClosedTabs: [(tab: Tab, spaceId: UUID?, currentURL: URL?, canGoBack: Bool, canGoForward: Bool, timestamp: Date)] = []
    private let undoDuration: TimeInterval = 20.0 // 20 seconds
    private var undoTimer: Timer?

    // Toast notification cooldown
    private var lastTabClosureTime: Date?
    private let toastCooldown: TimeInterval = 2 * 60 * 60 // 2 hours in seconds

    // Spaces
    @Published public private(set) var spaces: [Space] = []
    @Published public private(set) var currentSpace: Space?

    // Normal tabs per space
    @Published var tabsBySpace: [UUID: [Tab]] = [:]

    // Space-level pinned tabs per space
    @Published private var spacePinnedTabs: [UUID: [Tab]] = [:]

    // Folders per space
    @Published private var foldersBySpace: [UUID: [TabFolder]] = [:]

    // Global pinned (essentials), isolated per profile
    @Published private var pinnedByProfile: [UUID: [Tab]] = [:]
    // Pinned tabs encountered during load that have no profile assignment yet
    private var pendingPinnedWithoutProfile: [Tab] = []
    // Space activation to resume after a deferred profile switch
    private var pendingSpaceActivation: UUID?
    
    // Essentials API - profile-filtered view of global pinned tabs
    var pinnedTabs: [Tab] {
        guard let pid = browserManager?.currentProfile?.id else { return [] }
        return pinnedByProfile[pid] ?? []
    }
    
    var essentialTabs: [Tab] { pinnedTabs }
    
    func essentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId = profileId else { return [] }
        return pinnedByProfile[profileId] ?? []
    }
    
    // Flattened pinned across all profiles for internal ops
    private var allPinnedTabsAllProfiles: [Tab] {
        pinnedByProfile.values.flatMap { $0 }
    }

    // Currently active tab
    private(set) var currentTab: Tab?

    // Per-space most-recently-used tab history (most recent last)
    private var tabMRU: [UUID: [UUID]] = [:]

    init(browserManager: BrowserManager? = nil, context: ModelContext) {
        self.browserManager = browserManager
        self.context = context
        self.persistence = PersistenceActor(container: context.container)
        // Load synchronously to prevent race condition where ensureDefaultSpaceIfNeeded()
        // creates a duplicate "Personal" space before DB data is loaded.
        loadFromStore()
    }

    deinit {
        // MEMORY LEAK FIX: Clean up all tab references and break potential cycles
        MainActor.assumeIsolated {
            tabsBySpace.removeAll()
            spacePinnedTabs.removeAll()
            foldersBySpace.removeAll()
            pinnedByProfile.removeAll()
            pendingPinnedWithoutProfile.removeAll()
            spaces.removeAll()
            currentTab = nil
            currentSpace = nil
            browserManager = nil
        }

    }

    // MARK: - Convenience

    var tabs: [Tab] {
        guard let s = currentSpace else { return [] }
        return tabsBySpace[s.id] ?? []
    }

    private func setTabs(_ items: [Tab], for spaceId: UUID) {
        var updated = tabsBySpace
        updated[spaceId] = items.sorted { $0.index < $1.index }
        tabsBySpace = updated
        invalidateTabCache()
    }

    private func setSpacePinnedTabs(_ items: [Tab], for spaceId: UUID) {
        var updated = spacePinnedTabs
        updated[spaceId] = items.sorted { $0.index < $1.index }
        spacePinnedTabs = updated
        invalidateTabCache()
    }

    private func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        var updated = foldersBySpace
        updated[spaceId] = items
        foldersBySpace = updated
    }

    private func setPinnedTabs(_ items: [Tab], for profileId: UUID) {
        var updated = pinnedByProfile
        updated[profileId] = items.sorted { $0.index < $1.index }
        pinnedByProfile = updated
        invalidateTabCache()
    }

    // MARK: - Tab Cache

    /// Cached dictionary mapping tab IDs to Tab objects for O(1) lookup.
    /// Invalidated whenever tabs are added, removed, or moved between containers.
    private var _allTabsById: [UUID: Tab]?

    /// Cached set of all known tab IDs for O(1) contains checks.
    private var _allTabIds: Set<UUID>?

    private func invalidateTabCache() {
        _allTabsById = nil
        _allTabIds = nil
    }

    /// O(1) tab lookup by ID, building the cache on first access after invalidation.
    func tabById(_ id: UUID) -> Tab? {
        if _allTabsById == nil {
            _allTabsById = Dictionary(allTabs().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return _allTabsById?[id]
    }

    /// O(1) check for whether a tab ID is known across all containers.
    private func allTabIdsSet() -> Set<UUID> {
        if _allTabIds == nil {
            _allTabIds = Set(allTabs().map { $0.id })
        }
        return _allTabIds!
    }

    private func attach(_ tab: Tab) {
        tab.browserManager = browserManager
        tab.nookSettings = nookSettings
    }

    private func allTabsAllSpaces() -> [Tab] {
        let normals = spaces.flatMap { tabsBySpace[$0.id] ?? [] }
        let spacePinned = spaces.flatMap { spacePinnedTabs[$0.id] ?? [] }
        return allPinnedTabsAllProfiles + spacePinned + normals
    }

    // Public accessor for managers that need to iterate tabs (e.g., privacy, rules updates)
    func allTabs() -> [Tab] {
        let normals = spaces.flatMap { tabsBySpace[$0.id] ?? [] }
        let spacePinned = spaces.flatMap { spacePinnedTabs[$0.id] ?? [] }
        return allPinnedTabsAllProfiles + spacePinned + normals
    }

    /// Profile-filtered union of pinned, space-pinned and regular tabs.
    func allTabsForCurrentProfile() -> [Tab] {
        guard let pid = browserManager?.currentProfile?.id else {
            return allTabs()
        }
        let spaceIds = Set(spaces.filter { $0.profileId == pid }.map { $0.id })
        // Create copies to prevent race conditions during sorting
        let pinned = Array(pinnedByProfile[pid] ?? []).sorted { $0.index < $1.index }
        let spacePinned = spaces
            .filter { spaceIds.contains($0.id) }
            .flatMap { Array(spacePinnedTabs[$0.id] ?? []).sorted { $0.index < $1.index } }
        let regular = spaces
            .filter { spaceIds.contains($0.id) }
            .flatMap { Array(tabsBySpace[$0.id] ?? []).sorted { $0.index < $1.index } }
        return pinned + spacePinned + regular
    }

    private func contains(_ tab: Tab) -> Bool {
        return allTabIdsSet().contains(tab.id)
    }

    // MARK: - Container Membership Helpers
    /// True if the tab is globally pinned (Essentials) in any profile.
    func isGlobalPinned(_ tab: Tab) -> Bool {
        return allPinnedTabsAllProfiles.contains { $0.id == tab.id }
    }

    /// True if the tab is pinned at the space level within its space.
    func isSpacePinned(_ tab: Tab) -> Bool {
        guard let sid = tab.spaceId, let arr = spacePinnedTabs[sid] else { return false }
        return arr.contains { $0.id == tab.id }
    }

    /// True if the tab is a regular (non-pinned) tab in its space.
    func isRegular(_ tab: Tab) -> Bool {
        guard let sid = tab.spaceId, let arr = tabsBySpace[sid] else { return false }
        return arr.contains { $0.id == tab.id }
    }

    /// Create a new regular tab duplicating the source tab's URL/name and insert near an anchor tab.
    /// - Parameters:
    ///   - source: The tab to duplicate (pinned/space-pinned or regular).
    ///   - anchor: A regular tab used to decide target space and placement. If nil, falls back to currentSpace.
    ///   - placeAfterAnchor: If true, insert right after the anchor's index; otherwise at the anchor's index.
    /// - Returns: The newly created regular Tab.
    @discardableResult
    func duplicateAsRegularForSplit(from source: Tab, anchor: Tab?, placeAfterAnchor: Bool = true) -> Tab {
        // Resolve target space: prefer the anchor's space, else currentSpace.
        let targetSpace: Space = {
            if let a = anchor, let sid = a.spaceId, let sp = spaces.first(where: { $0.id == sid }) { return sp }
            return currentSpace ?? ensureDefaultSpaceIfNeeded()
        }()

        // Build the duplicate with the same URL/name; favicon will refresh from URL.
        let newTab = Tab(
            url: source.url,
            name: source.name,
            favicon: "globe",
            spaceId: targetSpace.id,
            index: 0,
            browserManager: browserManager
        )
        
        // Add at end first, then reposition next to anchor if provided.
        addTab(newTab)

        if let a = anchor, let sid = a.spaceId, let arr = tabsBySpace[sid] {
            // Find indices in current ordering
            if let anchorIndex = arr.firstIndex(where: { $0.id == a.id }),
               let newIndex = arr.firstIndex(where: { $0.id == newTab.id })
            {
                // Compute desired position relative to anchor
                let desired = min(max(anchorIndex + (placeAfterAnchor ? 1 : 0), 0), arr.count)
                if newIndex != desired {
                    reorderRegularTabs(newTab, in: sid, to: desired)
                }
            }
        }

        return newTab
    }

    // MARK: - Space Management
    @discardableResult
    func createSpace(name: String, icon: String = "square.grid.2x2", gradient: SpaceGradient = .default) -> Space {
        // Always assign to a profile - prefer current profile, fallback to default profile
        let resolvedProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
        // Ensure we always have a profile to assign
        guard let profileId = resolvedProfileId else {
            fatalError("TabManager.createSpace requires at least one profile to exist")
        }
        let space = Space(
            name: name,
            icon: icon,
            gradient: gradient,
            profileId: profileId
        )
        spaces.append(space)
        setTabs([], for: space.id)
        setSpacePinnedTabs([], for: space.id)
        if currentSpace == nil { currentSpace = space } else { setActiveSpace(space) }

        // Create a new tab with the user's preferred search engine
        createNewTab(in: space)

        debouncedPersistSnapshot()
        return space
    }

    func removeSpace(_ id: UUID) {
        guard spaces.count > 1 else {
            return
        }
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else {
            return
        }
        // The dialog says the space's tabs are deleted. Release their webviews, splits and
        // extension state like any other close; there is nothing to undo into.
        let closing = (tabsBySpace[id] ?? []) + (spacePinnedTabs[id] ?? [])
        for t in closing {
            browserManager?.splitManager.handleTabClosure(t.id)
            browserManager?.compositorManager.unloadTab(t)
            browserManager?.webViewCoordinator?.removeAllWebViews(for: t)
            ExtensionManager.shared.notifyTabClosed(t)
            if currentTab?.id == t.id { currentTab = nil }
        }
        setTabs([], for: id)
        setSpacePinnedTabs([], for: id)
        setFolders([], for: id)
        if idx < spaces.count { spaces.remove(at: idx) }
        if currentSpace?.id == id, let next = spaces.first {
            // Selects that space's remembered or first tab instead of leaving no selection.
            setActiveSpace(next)
        }

        debouncedPersistSnapshot()

        // Validate window states after space removal
        browserManager?.validateWindowStates()
    }

    func setActiveSpace(_ space: Space) {
        guard spaces.contains(where: { $0.id == space.id }) else { return }

        // Edge case: assign space to current profile if missing
        if space.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                assign(spaceId: space.id, toProfile: pid)
            }
        }

        // Capture the previous state before switching
        let previousTab = currentTab
        let previousSpace = currentSpace

        // Always remember the active tab for the outgoing space
        if let prevSpace = previousSpace, let prevTab = previousTab {
            // Remember regardless of tab container (regular, space-pinned, or global pinned)
            prevSpace.activeTabId = prevTab.id
        }

        // Trigger gradient transition aware of window contexts
        browserManager?.refreshGradientsForSpace(space, animate: true)

        // Switch to the new space
        currentSpace = space

        // Tabs in this space
        let inSpace = tabsBySpace[space.id] ?? []
        let spacePinned = spacePinnedTabs[space.id] ?? []

        // Restore the last active tab for this space, including global pinned
        var targetTab: Tab?
        if let activeId = space.activeTabId {
            if let match = inSpace.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if let match = spacePinned.first(where: { $0.id == activeId }) {
                targetTab = match
            } else if let match = pinnedTabs.first(where: { $0.id == activeId }) {
                targetTab = match
            }
        }

        // Fallbacks
        if targetTab == nil {
            if let ct = currentTab {
                if let sid = ct.spaceId, sid == space.id {
                    targetTab = ct
                } else {
                    // Prefer something in the space; otherwise use a global pinned
                    targetTab = inSpace.first ?? spacePinned.first ?? pinnedTabs.first
                }
            } else {
                targetTab = inSpace.first ?? spacePinned.first ?? pinnedTabs.first
            }
        }

        // Decide if active tab actually changes
        let isTabChanging = (targetTab?.id != currentTab?.id)

        // Update active tab only if it changed
        if isTabChanging {
            currentTab = targetTab
        }

        debouncedPersistSnapshot()
        // Notify extensions only on real activation change
        if isTabChanging, let newActive = currentTab {
            ExtensionManager.shared.notifyTabActivated(newTab: newActive, previous: previousTab)
        }
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        guard let idx = spaces.firstIndex(where: { $0.id == spaceId }), idx < spaces.count else {
            throw TabManagerError.spaceNotFound(spaceId)
        }
        spaces[idx].name = newName

        if currentSpace?.id == spaceId {
            currentSpace?.name = newName
        }

        debouncedPersistSnapshot()
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        guard let idx = spaces.firstIndex(where: { $0.id == spaceId }), idx < spaces.count else {
            throw TabManagerError.spaceNotFound(spaceId)
        }
        spaces[idx].icon = icon

        if currentSpace?.id == spaceId {
            currentSpace?.icon = icon
        }

        debouncedPersistSnapshot()
    }

    // MARK: - Folder Management

    @discardableResult
    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        let folder = TabFolder(
            name: name,
            spaceId: spaceId,
            color: spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor,
            index: (foldersBySpace[spaceId]?.map { $0.index }.max() ?? -1) + 1
        )

        var folders = foldersBySpace[spaceId] ?? []
        folders.append(folder)
        setFolders(folders, for: spaceId)

        // Send notification for SpaceView folderChangeCount
        NotificationCenter.default.post(name: .init("TabFoldersDidChange"), object: nil)

        debouncedPersistSnapshot()
        return folder
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        for (_, folders) in foldersBySpace {
            if let folder = folders.first(where: { $0.id == folderId }) {
                folder.name = newName
                // SwiftUI will automatically detect changes to @Published foldersBySpace
                debouncedPersistSnapshot()
                break
            }
        }
    }

    func deleteFolder(_ folderId: UUID) {
        // Find and remove the folder
        for (spaceId, folders) in foldersBySpace {
            if let index = folders.firstIndex(where: { $0.id == folderId }) {
                let folder = folders[index]

                // Use the same membership rules as menu and drag transfers.
                for tab in allTabs() where tab.folderId == folderId {
                    transferTab(tab, to: .space(spaceId, pinned: !folder.isRegular))
                }

                // Remove the folder
                var mutableFolders = folders
                mutableFolders.remove(at: index)
                for (i, item) in mutableFolders.enumerated() { item.index = i }
                setFolders(mutableFolders, for: spaceId)

                // Send notification for SpaceView folderChangeCount
                NotificationCenter.default.post(name: .init("TabFoldersDidChange"), object: nil)

                debouncedPersistSnapshot()
                break
            }
        }
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        return foldersBySpace[spaceId] ?? []
    }

    func toggleFolder(_ folderId: UUID) {
        for (_, folders) in foldersBySpace {
            if let folder = folders.first(where: { $0.id == folderId }) {
                folder.isOpen.toggle()
                // SwiftUI will automatically detect changes to @Published foldersBySpace
                debouncedPersistSnapshot()
                break
            }
        }
    }

    // MARK: - Regular Folder Management

    /// Create a folder in the regular tab area (not space-pinned).
    @discardableResult
    func createRegularFolder(for spaceId: UUID, name: String) -> TabFolder {
        let folder = TabFolder(
            name: name,
            spaceId: spaceId,
            color: spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor,
            index: (foldersBySpace[spaceId]?.map { $0.index }.max() ?? -1) + 1,
            isRegular: true
        )

        var folders = foldersBySpace[spaceId] ?? []
        folders.append(folder)
        setFolders(folders, for: spaceId)

        NotificationCenter.default.post(name: .init("TabFoldersDidChange"), object: nil)
        debouncedPersistSnapshot()
        return folder
    }

    /// Get regular (non-space-pinned) tabs in a specific folder.
    func regularFolderTabs(for spaceId: UUID, folderId: UUID) -> [Tab] {
        return (tabsBySpace[spaceId] ?? [])
            .filter { $0.folderId == folderId }
            .sorted { $0.index < $1.index }
    }

    /// Get only loose regular tabs (no folder) for a space.
    func looseTabs(in space: Space) -> [Tab] {
        return tabs(in: space).filter { $0.folderId == nil }
    }

    /// Get regular folders for a space.
    func regularFolders(for spaceId: UUID) -> [TabFolder] {
        return (foldersBySpace[spaceId] ?? []).filter { $0.isRegular }
    }

    /// `index` is the position among the folder's tabs; nil appends.
    func moveTabToFolder(tab: Tab, folderId: UUID, index: Int? = nil) {
        transferTab(tab, to: .folder(folderId), index: index)
    }

    // MARK: - Tab Management (Normal within current space)

    func addTab(_ tab: Tab) {
        attach(tab)
        if contains(tab) { return }

        if tab.spaceId == nil || !spaces.contains(where: { $0.id == tab.spaceId }) {
            tab.spaceId = currentSpace?.id
        }
        guard let sid = tab.spaceId else {
            return
        }
        var arr = tabsBySpace[sid] ?? []
        arr.append(tab)
        setTabs(arr, for: sid)
        
        // Load the tab in compositor if it's the current tab
        if tab.id == currentTab?.id {
            browserManager?.compositorManager.loadTab(tab)
        }
        
        // Notify extension system about new tab
        ExtensionManager.shared.notifyTabOpened(tab)

        debouncedPersistSnapshot()
    }

    /// Removes a pinned tab, bypassing the normal guard that protects pinned tabs from removal.
    /// The pin state stays on the undo copy so Undo Close brings the pin back.
    func forceRemoveTab(_ id: UUID) {
        removeTab(id, force: true)
    }

    /// Every close goes through here. `track: false` is for bulk closes that record their own undo
    /// entry; `force` removes pinned tabs instead of deactivating them.
    func removeTab(_ id: UUID, track: Bool = true, force: Bool = false) {
        // Pinned/space-pinned tabs should not be removed — just deactivate them
        if !force, let tab = tabById(id),
           tab.isPinned || tab.isSpacePinned {
            deactivatePinnedTab(tab)
            return
        }

        // Notify SplitViewManager about tab closure to prevent zombie state
        browserManager?.splitManager.handleTabClosure(id)

        let wasCurrent = (currentTab?.id == id)
        var removed: Tab?
        var removedSpaceId: UUID?
        var removedIndexInCurrentSpace: Int?

        for space in spaces {
            // Check space-pinned tabs first
            if var spacePinned = spacePinnedTabs[space.id],
                let i = spacePinned.firstIndex(where: { $0.id == id })
            {
                if i < spacePinned.count { removed = spacePinned.remove(at: i) }
                removedSpaceId = space.id
                removedIndexInCurrentSpace =
                    (space.id == currentSpace?.id) ? i : nil
                setSpacePinnedTabs(spacePinned, for: space.id)
                break
            }
            // Then check regular tabs
            if var arr = tabsBySpace[space.id],
                let i = arr.firstIndex(where: { $0.id == id })
            {
                if i < arr.count { removed = arr.remove(at: i) }
                removedSpaceId = space.id
                removedIndexInCurrentSpace =
                    (space.id == currentSpace?.id) ? i : nil
                setTabs(arr, for: space.id)
                break
            }
        }
        if removed == nil {
            outer: for (pid, arr) in pinnedByProfile {
                if let i = arr.firstIndex(where: { $0.id == id }) {
                    var copy = arr
                    if i < copy.count { removed = copy.remove(at: i) }
                    setPinnedTabs(copy, for: pid)
                    break outer
                }
            }
        }

        guard let tab = removed else { return }

        // Add to recently closed tabs for undo functionality
        if track { trackRecentlyClosedTab(tab, spaceId: removedSpaceId) }

        // Force unload the tab from compositor before removing
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)

        ExtensionManager.shared.notifyTabClosed(tab)

        if wasCurrent {
            // Remove closed tab from MRU
            if let spaceId = removedSpaceId ?? currentSpace?.id {
                tabMRU[spaceId]?.removeAll { $0 == id }
            }

            // Try to activate the most recently used tab in the same space
            currentTab = findMRUTab(excludingId: id) ?? findFallbackTab(excludingId: id)

            // If no loaded tab found, clear window states so EmptyWebsiteView shows
            if currentTab == nil {
                for (_, windowState) in browserManager?.windowRegistry?.windows ?? [:] {
                    if windowState.currentTabId == id {
                        windowState.currentTabId = nil
                        windowState.refreshCompositor()
                    }
                }
            }
        } else {
            // Still remove from MRU even if it wasn't the current tab
            if let spaceId = removedSpaceId ?? currentSpace?.id {
                tabMRU[spaceId]?.removeAll { $0 == id }
            }
        }

        debouncedPersistSnapshot()

        // Validate window states after tab removal
        browserManager?.validateWindowStates()
    }

    /// Deactivates a pinned/space-pinned tab without removing it.
    /// Unloads the webview and switches to the MRU tab.
    private func deactivatePinnedTab(_ tab: Tab) {
        // Reset URL to the pinned home URL so next open starts fresh
        if let pinnedURL = tab.pinnedURL {
            tab.url = pinnedURL
        }
        deactivateTab(tab)
    }

    /// Unloads a tab without removing it. A tab still on screen hands selection to the most
    /// recent loaded tab first; any other window showing it falls back to the empty state
    /// rather than a blank pane that still claims the tab.
    private func deactivateTab(_ tab: Tab) {
        browserManager?.splitManager.handleTabClosure(tab.id)

        // Unload webview directly (bypasses TabManager.unloadTab which guards essentials)
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)

        if currentTab?.id == tab.id {
            if let nextTab = findMRUTab(excludingId: tab.id) ?? findFallbackTab(excludingId: tab.id) {
                // Use selectTab to properly update windowState.currentTabId and compositor
                browserManager?.selectTab(nextTab)
            } else {
                currentTab = nil
            }
        }
        for (_, windowState) in browserManager?.windowRegistry?.windows ?? [:] where windowState.currentTabId == tab.id {
            windowState.currentTabId = nil
            windowState.refreshCompositor()
        }
    }

    /// Find the most recently used tab in the current space, excluding a given tab ID
    private func findMRUTab(excludingId: UUID) -> Tab? {
        guard let spaceId = currentSpace?.id,
              let mru = tabMRU[spaceId] else { return nil }

        let spacePinned = spacePinnedTabs[spaceId] ?? []
        let regular = tabsBySpace[spaceId] ?? []
        let allSpaceTabs = spacePinned + regular

        // Walk MRU from most recent (end) backwards, skip unloaded tabs
        for tabId in mru.reversed() where tabId != excludingId {
            if let tab = allSpaceTabs.first(where: { $0.id == tabId && !$0.isUnloaded }) {
                return tab
            }
        }
        return nil
    }

    /// Positional fallback when MRU has no candidate, skip unloaded tabs
    private func findFallbackTab(excludingId: UUID) -> Tab? {
        if let cs = currentSpace {
            let spacePinned = spacePinnedTabs[cs.id] ?? []
            let regular = tabsBySpace[cs.id] ?? []
            let allSpaceTabs = spacePinned + regular
            if let tab = allSpaceTabs.last(where: { $0.id != excludingId && !$0.isUnloaded }) {
                return tab
            }
        }
        return pinnedTabs.last(where: { $0.id != excludingId && !$0.isUnloaded })
    }

    func setActiveTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }

        let previous = currentTab
        currentTab = tab

        // Track MRU for the tab's space
        if let spaceId = tab.spaceId ?? currentSpace?.id {
            var mru = tabMRU[spaceId] ?? []
            mru.removeAll { $0 == tab.id }
            mru.append(tab.id)
            // Cap at 20 entries to avoid unbounded growth
            if mru.count > 20 { mru.removeFirst(mru.count - 20) }
            tabMRU[spaceId] = mru
        }
        
        // Update website shortcut detector with the new tab's URL
        browserManager?.keyboardShortcutManager?.websiteShortcutDetector.updateCurrentURL(tab.url)
        
        // Do not auto-exit split when leaving split panes; preserve split state

        // Update active side in split view for all windows that contain this tab
        // Also update windowState.currentTabId for windows that have this tab in split view
        if let bm = browserManager {
            for (windowId, windowState) in bm.windowRegistry?.windows ?? [:] {
                // Check if this tab is in split view for this window
                if bm.splitManager.isSplit(for: windowId) {
                    let state = bm.splitManager.getSplitState(for: windowId)
                    // If tab is on left or right side, update active side and window's current tab
                    if state.leftTabId == tab.id || state.rightTabId == tab.id {
                        bm.splitManager.updateActiveSide(for: tab.id, in: windowId)
                        // Update window's current tab ID so other UI components work correctly
                        windowState.currentTabId = tab.id
                    }
                }
            }
        }

        // Save this tab as the active tab for the appropriate space
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            space.activeTabId = tab.id
            currentSpace = space
        } else if let cs = currentSpace {
            cs.activeTabId = tab.id
        }
        
        debouncedPersistSnapshot()
    }

    /// Update only the global tab state without triggering UI operations
    /// Used when BrowserManager.selectTab() has already handled all UI concerns
    func updateActiveTabState(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        currentTab = tab

        // Track MRU for the tab's space
        if let spaceId = tab.spaceId ?? currentSpace?.id {
            var mru = tabMRU[spaceId] ?? []
            mru.removeAll { $0 == tab.id }
            mru.append(tab.id)
            if mru.count > 20 { mru.removeFirst(mru.count - 20) }
            tabMRU[spaceId] = mru
        }

        // Save this tab as the active tab for the appropriate space
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            // Tab belongs to a specific space (regular or space-pinned)
            space.activeTabId = tab.id
            currentSpace = space
        } else if let cs = currentSpace {
            // Tab is globally pinned; remember it for the current space too
            cs.activeTabId = tab.id
        }
        
        // Persist the change
        debouncedPersistSnapshot()
    }

    @discardableResult
    func createNewTab(
        url: String = "https://www.google.com",
        in space: Space? = nil
    ) -> Tab {
        let settings = nookSettings ?? browserManager?.nookSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(url, queryTemplate: template)
        guard let validURL = URL(string: normalizedUrl)
        else {
            return createNewTab(in: space)
        }

        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                debouncedPersistSnapshot()
            }
        }
        let sid = targetSpace?.id

        // Get existing tabs and increment their indices to make room for new tab at top
        let existingTabs = sid.flatMap { tabsBySpace[$0] } ?? []
        let incrementedTabs = existingTabs.map { tab in
            tab.index += 1
            return tab
        }

        // Update the tabs array with incremented indices
        if let sid = sid {
            setTabs(incrementedTabs, for: sid)
        }

        let newTab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: 0, // New tabs get index 0 to appear at top
            browserManager: browserManager
        )
        addTab(newTab)
        setActiveTab(newTab)
        return newTab
    }

    // MARK: - Ephemeral Tab Creation (Incognito)

    /// Create a new ephemeral tab in an incognito window
    /// These tabs are NOT persisted and are stored in window state
    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0,
            browserManager: browserManager
        )
        newTab.profileId = profile.id

        // Add to window's ephemeral tabs (NOT to persistent tabs)
        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id

        return newTab
    }

    // Create a new tab with an existing WebView (used for Peek transfers)
    @discardableResult
    func createNewTabWithWebView(
        url: String = "https://www.google.com",
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        let settings = nookSettings ?? browserManager?.nookSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(url, queryTemplate: template)
        guard let validURL = URL(string: normalizedUrl)
        else {
            return createNewTab(in: space)
        }

        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                debouncedPersistSnapshot()
            }
        }
        let sid = targetSpace?.id

        // Get existing tabs and increment their indices to make room for new tab at top
        let existingTabs = sid.flatMap { tabsBySpace[$0] } ?? []
        let incrementedTabs = existingTabs.map { tab in
            tab.index += 1
            return tab
        }

        // Update the tabs array with incremented indices
        if let sid = sid {
            setTabs(incrementedTabs, for: sid)
        }

        // A handed-over web view has already loaded, so its title KVO will not fire again.
        let loadedTitle = existingWebView?.title.flatMap { $0.isEmpty ? nil : $0 }
        let newTab = Tab(
            url: validURL,
            name: loadedTitle ?? "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: 0, // New tabs get index 0 to appear at top
            browserManager: browserManager,
            existingWebView: existingWebView
        )
        addTab(newTab)
        setActiveTab(newTab)
        return newTab
    }

    // Create a new blank tab intended to host a popup window. The returned tab's
    // WKWebView is returned to WebKit so it can load popup content. No initial
    // navigation is performed to preserve window.opener scripting semantics.
    @discardableResult
    func createPopupTab(in space: Space? = nil) -> Tab {
        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure target space has a profile assignment
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                debouncedPersistSnapshot()
            }
        }
        let sid = targetSpace?.id
        let existingTabs = sid.flatMap { tabsBySpace[$0] } ?? []
        let nextIndex = (existingTabs.map { $0.index }.max() ?? -1) + 1

        let blankURL = URL(string: "about:blank") ?? URL(string: "https://example.com")!
        let newTab = Tab(
            url: blankURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            browserManager: browserManager
        )
        newTab.isPopupHost = true
        addTab(newTab)
        setActiveTab(newTab)
        return newTab
    }

    // Ensure a default space exists and is active; create a Personal space if needed
    private func ensureDefaultSpaceIfNeeded() -> Space {
        if let cs = currentSpace { return cs }
        if spaces.isEmpty {
            let resolvedProfileId = browserManager?.currentProfile?.id
            let personal = Space(name: "Personal", icon: "person.crop.circle", gradient: .default, profileId: resolvedProfileId)
            spaces.append(personal)
            setTabs([], for: personal.id)
            setSpacePinnedTabs([], for: personal.id)
            currentSpace = personal
            persistSnapshot()
            return personal
        } else {
            currentSpace = spaces.first
            return currentSpace!
        }
    }

    func closeActiveTab() {
        guard let currentTab else {
            return
        }
        removeTab(currentTab.id)
    }

    func clearRegularTabs(for spaceId: UUID) {
        // Clear counts and removes loose tabs only; folders keep their contents. Tabs on
        // screen in any window stay open.
        let visibleIds = Set((browserManager?.windowRegistry?.windows.values).map { $0.compactMap { $0.currentTabId } } ?? [])
            .union([currentTab?.id].compactMap { $0 })
        for tab in (tabsBySpace[spaceId] ?? []) where tab.folderId == nil && !visibleIds.contains(tab.id) {
            removeTab(tab.id)
        }
    }
    
    /// Automatic unloading (idle timer, budget, memory pressure). Callers only pass tabs that
    /// are not on screen.
    func unloadTab(_ tab: Tab) {
        // Never unload essentials tabs except on browser close/restart
        guard !allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else { return }
        browserManager?.compositorManager.unloadTab(tab)
    }

    /// User-requested unload from the sidebar. The tab may be the one on screen.
    func unloadTabMovingSelection(_ tab: Tab) {
        guard !allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else { return }
        deactivateTab(tab)
    }
    
    func unloadAllInactiveTabs() {
        guard let compositor = browserManager?.compositorManager else { return }
        for tab in tabs where compositor.canUnloadInactiveTab(tab) {
            unloadTab(tab)
        }
    }

    // MARK: - Drag & Drop Operations
    
    func handleDragOperation(_ operation: DragOperation) {
        let tab = operation.tab
        
        guard operation.fromContainer != .none else { return }
        let destination: TabTransferDestination
        switch operation.toContainer {
        case .essentials:
            guard let profileId = browserManager?.currentProfile?.id else { return }
            destination = .essentials(profileId)
        case .spacePinned(let spaceId):
            destination = .space(spaceId, pinned: true)
        case .spaceRegular(let spaceId):
            destination = .space(spaceId, pinned: false)
        case .folder(let folderId):
            destination = .folder(folderId)
        case .none:
            return
        }
        // Drag indices refer to the visible folder/loose-tab list, not its backing bucket.
        guard transferTab(tab, to: destination, index: operation.toIndex) else { return }
        // If the moved tab is currently part of an active split, dissolve the split.
        // Keep the opposite side focused so the remaining pane stays visible.
        if let sm = browserManager?.splitManager, let bm = browserManager {
            // Check all windows for split state
            for (windowId, _) in bm.windowRegistry?.windows ?? [:] {
                if sm.isSplit(for: windowId) {
                    if sm.leftTabId(for: windowId) == tab.id {
                        sm.exitSplit(keep: .right, for: windowId)
                    } else if sm.rightTabId(for: windowId) == tab.id {
                        sm.exitSplit(keep: .left, for: windowId)
                    }
                }
            }
        }
    }
    
    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) {
        guard let profileId = pinnedByProfile.first(where: { $0.value.contains(where: { $0.id == tab.id }) })?.key else { return }
        transferTab(tab, to: .essentials(profileId), index: index)
    }

    private func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        let destination: TabTransferDestination = tab.folderId.map { .folder($0) } ?? .space(spaceId, pinned: true)
        transferTab(tab, to: destination, index: index, indexWithinGroup: false)
    }

    private func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        let destination: TabTransferDestination = tab.folderId.map { .folder($0) } ?? .space(spaceId, pinned: false)
        transferTab(tab, to: destination, index: index, indexWithinGroup: false)
    }

    // MARK: - Tab Ordering

    /// Moves a tab to a different space
    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        guard let tab = tabById(tabId),
              let currentSpaceId = tab.spaceId,
              currentSpaceId != targetSpaceId else { return }

        // Move to target space at the end of regular tabs
        let targetTabs = tabsBySpace[targetSpaceId] ?? []
        guard transferTab(tab, to: .space(targetSpaceId, pinned: false), index: targetTabs.count) else { return }

        // A window showing the tab follows it to its new space, so the page on screen stays in
        // that window's sidebar. The tab can't stay in a split with a tab from the old space.
        // selectTab also moves the global current space when that window is active.
        browserManager?.splitManager.handleTabClosure(tabId)
        for (_, windowState) in browserManager?.windowRegistry?.windows ?? [:] where windowState.currentTabId == tabId {
            browserManager?.selectTab(tab, in: windowState)
        }
    }

    func moveTabUp(_ tabId: UUID) {
        guard let spaceId = findSpaceForTab(tabId) else { return }
        let tabs = tabsBySpace[spaceId] ?? []
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }

        // Can't move the first tab up
        guard currentIndex > 0 else { return }

        // Swap with the tab above
        let tab = tabs[currentIndex]
        let targetTab = tabs[currentIndex - 1]

        let tempIndex = tab.index
        tab.index = targetTab.index
        targetTab.index = tempIndex

        setTabs(tabs, for: spaceId)
        debouncedPersistSnapshot()
    }

    func moveTabDown(_ tabId: UUID) {
        guard let spaceId = findSpaceForTab(tabId) else { return }
        let tabs = tabsBySpace[spaceId] ?? []
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }

        // Can't move the last tab down
        guard currentIndex < tabs.count - 1 else { return }

        // Swap with the tab below
        let tab = tabs[currentIndex]
        let targetTab = tabs[currentIndex + 1]

        let tempIndex = tab.index
        tab.index = targetTab.index
        targetTab.index = tempIndex

        setTabs(tabs, for: spaceId)
        debouncedPersistSnapshot()
    }

    private func findSpaceForTab(_ tabId: UUID) -> UUID? {
        for (spaceId, tabs) in tabsBySpace {
            if tabs.contains(where: { $0.id == tabId }) {
                return spaceId
            }
        }
        return nil
    }

    // Helper to safely mutate current profile's pinned array with reindexing
    private func withCurrentProfilePinnedArray(_ mutate: (inout [Tab]) -> Void) {
        guard let pid = browserManager?.currentProfile?.id else { return }
        var arr = pinnedByProfile[pid] ?? []
        mutate(&arr)
        for (i, t) in arr.enumerated() { t.index = i }
        setPinnedTabs(arr, for: pid)
    }

    // MARK: - Pinned tabs (global)

    func pinTab(_ tab: Tab) {
        guard let profileId = browserManager?.currentProfile?.id else { return }
        if (pinnedByProfile[profileId] ?? []).contains(where: { $0.id == tab.id }) { return }
        transferTab(tab, to: .essentials(profileId))
    }

    func unpinTab(_ tab: Tab) {
        guard allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }),
              let spaceId = currentSpace?.id ?? spaces.first?.id else { return }
        transferTab(tab, to: .space(spaceId, pinned: false), index: 0)
    }

    func togglePin(_ tab: Tab) {
        if allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) {
            unpinTab(tab)
        } else {
            pinTab(tab)
        }
    }
    
    // MARK: - Essentials API (profile-aware)
    
    func addToEssentials(_ tab: Tab) {
        pinTab(tab)
    }
    
    func removeFromEssentials(_ tab: Tab) {
        unpinTab(tab)
    }
    
    func reorderEssential(_ tab: Tab, to index: Int) {
        reorderGlobalPinnedTabs(tab, to: index)
    }
    
    func reorderRegular(_ tab: Tab, in spaceId: UUID, to index: Int) {
        reorderRegularTabs(tab, in: spaceId, to: index)
    }
    
    func reorderSpacePinned(_ tab: Tab, in spaceId: UUID, to index: Int) {
        reorderSpacePinnedTabs(tab, in: spaceId, to: index)
    }
    
    // MARK: - Space-Level Pinned Tabs
    
    func spacePinnedTabs(for spaceId: UUID) -> [Tab] {
        // Create a copy of the array before sorting to prevent race conditions
        let tabs = Array(spacePinnedTabs[spaceId] ?? []).sorted { $0.index < $1.index }
        return tabs
    }
    
    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        transferTab(tab, to: .space(spaceId, pinned: true))
    }

    func unpinTabFromSpace(_ tab: Tab) {
        guard let spaceId = tab.spaceId,
              (spacePinnedTabs[spaceId] ?? []).contains(where: { $0.id == tab.id }) else { return }
        transferTab(tab, to: .space(spaceId, pinned: false))
    }

    private enum TabTransferDestination {
        case essentials(UUID)
        case space(UUID, pinned: Bool)
        case folder(UUID)
    }

    /// Validate before removal, then establish exactly one membership and normalize both buckets.
    /// An index is the final position after removing the source, matching the drag session contract.
    @discardableResult
    private func transferTab(_ tab: Tab, to destination: TabTransferDestination, index: Int? = nil, indexWithinGroup: Bool = true) -> Bool {
        guard contains(tab) || allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else { return false }
        let spaceId: UUID?
        let profileId: UUID?
        let folderId: UUID?
        let pinned: Bool
        switch destination {
        case .essentials(let id):
            guard browserManager?.currentProfile?.id == id || pinnedByProfile[id] != nil
                    || browserManager?.profileManager.profiles.contains(where: { $0.id == id }) == true else { return false }
            profileId = id
            spaceId = nil
            folderId = nil
            pinned = false
        case .space(let id, let isPinned):
            guard spaces.contains(where: { $0.id == id }) else { return false }
            spaceId = id
            profileId = nil
            folderId = nil
            pinned = isPinned
        case .folder(let id):
            guard let folder = foldersBySpace.values.flatMap({ $0 }).first(where: { $0.id == id }),
                  spaces.contains(where: { $0.id == folder.spaceId }),
                  (foldersBySpace[folder.spaceId] ?? []).contains(where: { $0.id == id }) else { return false }
            spaceId = folder.spaceId
            profileId = nil
            folderId = id
            pinned = !folder.isRegular
        }

        removeFromCurrentContainer(tab)
        tab.spaceId = spaceId
        tab.profileId = profileId
        tab.folderId = folderId
        tab.isPinned = profileId != nil
        tab.isSpacePinned = pinned
        if tab.isPinned || pinned {
            if tab.pinnedURL == nil { tab.pinnedURL = tab.url }
        } else {
            tab.pinnedURL = nil
        }

        var destinationTabs: [Tab]
        if let profileId {
            destinationTabs = pinnedByProfile[profileId] ?? []
        } else if let spaceId {
            destinationTabs = pinned ? (spacePinnedTabs[spaceId] ?? []) : (tabsBySpace[spaceId] ?? [])
        } else {
            return false // All validated destinations have a profile or space.
        }
        let insertionIndex: Int
        if indexWithinGroup {
            let members = destinationTabs.indices.filter { destinationTabs[$0].folderId == folderId }
            let position = max(0, min(index ?? members.count, members.count))
            insertionIndex = position < members.count ? members[position] : (members.last.map { $0 + 1 } ?? destinationTabs.count)
        } else {
            insertionIndex = max(0, min(index ?? destinationTabs.count, destinationTabs.count))
        }
        destinationTabs.insert(tab, at: insertionIndex)
        for (i, item) in destinationTabs.enumerated() { item.index = i }
        if let profileId {
            setPinnedTabs(destinationTabs, for: profileId)
        } else if let spaceId {
            if pinned { setSpacePinnedTabs(destinationTabs, for: spaceId) }
            else { setTabs(destinationTabs, for: spaceId) }
        }

        for space in spaces where space.activeTabId == tab.id {
            if space.id != spaceId && (profileId == nil || space.profileId != profileId) {
                space.activeTabId = nil
            }
        }
        debouncedPersistSnapshot()
        return true
    }

    private func removeFromCurrentContainer(_ tab: Tab) {
        // Search every bucket by identity, repairing any pre-existing duplicate memberships too.
        for (profileId, tabs) in pinnedByProfile where tabs.contains(where: { $0.id == tab.id }) {
            let remaining = tabs.filter { $0.id != tab.id }
            for (i, item) in remaining.enumerated() { item.index = i }
            setPinnedTabs(remaining, for: profileId)
        }
        for (spaceId, tabs) in spacePinnedTabs where tabs.contains(where: { $0.id == tab.id }) {
            let remaining = tabs.filter { $0.id != tab.id }
            for (i, item) in remaining.enumerated() { item.index = i }
            setSpacePinnedTabs(remaining, for: spaceId)
        }
        for (spaceId, tabs) in tabsBySpace where tabs.contains(where: { $0.id == tab.id }) {
            let remaining = tabs.filter { $0.id != tab.id }
            for (i, item) in remaining.enumerated() { item.index = i }
            setTabs(remaining, for: spaceId)
        }
    }

    // MARK: - Navigation (pinned + current space)

    func selectNextTab() {
        let inSpace = tabs
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        let all = pinnedTabs + spacePinned + inSpace
        guard !all.isEmpty, let current = currentTab else { return }
        guard let currentIndex = all.firstIndex(where: { $0.id == current.id })
        else { return }
        let nextIndex = (currentIndex + 1) % all.count
        if nextIndex < all.count { setActiveTab(all[nextIndex]) }
    }

    func selectPreviousTab() {
        let inSpace = tabs
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        let all = pinnedTabs + spacePinned + inSpace
        guard !all.isEmpty, let current = currentTab else { return }
        guard let currentIndex = all.firstIndex(where: { $0.id == current.id })
        else { return }
        let previousIndex = currentIndex == 0 ? all.count - 1 : currentIndex - 1
        if previousIndex < all.count { setActiveTab(all[previousIndex]) }
    }

    private func toRuntime(_ e: TabEntity) -> Tab {
        // Use the currentURLString for restoration, fallback to urlString for backward compatibility
        let urlString = e.currentURLString ?? e.urlString
        let url = URL(string: urlString) ?? URL(string: e.urlString) ?? URL(string: "https://www.google.com")!
        let t = Tab(
            id: e.id,
            url: url,
            name: e.name,
            favicon: "globe",
            spaceId: e.spaceId,
            index: e.index,
            browserManager: browserManager
        )
        t.folderId = e.folderId
        t.isPinned = e.isPinned
        t.profileId = e.isPinned ? e.profileId : nil
        t.isSpacePinned = e.isSpacePinned
        t.displayNameOverride = e.displayNameOverride

        // Restore pinned URL; default to current URL for legacy pinned tabs
        if let pinnedStr = e.pinnedURLString, let pURL = URL(string: pinnedStr) {
            t.pinnedURL = pURL
        } else if e.isPinned || e.isSpacePinned {
            t.pinnedURL = url
        }

        // Restore navigation state
        t.canGoBack = e.canGoBack
        t.canGoForward = e.canGoForward

        // Restore favicon from disk cache for instant display on startup
        t.restoreFaviconFromCache()

        return t
    }

    // MARK: - SwiftData load/save

    private func loadFromStore() {
        do {
            // Spaces
            let spaceEntities = try context.fetch(
                FetchDescriptor<SpaceEntity>()
            )
            let sortedSpaces = spaceEntities.sorted { $0.index < $1.index }
            self.spaces = sortedSpaces.map {
                let space = Space(
                    id: $0.id,
                    name: $0.name,
                    icon: $0.icon,
                    gradient: SpaceGradient.decode($0.gradientData),
                    profileId: $0.profileId
                )
                space.activeTabId = $0.activeTabId
                return space
            }

            // Names and icons are presentation, not identity. Preserve every stored UUID.
            for sp in spaces {
                setTabs([], for: sp.id)
                setSpacePinnedTabs([], for: sp.id)
            }

            // Ensure all spaces have profile assignments
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let dp = defaultProfileId {
                var didAssignProfiles = false
                for space in spaces where space.profileId == nil {
                    space.profileId = dp
                    didAssignProfiles = true
                }
                if didAssignProfiles { persistSnapshot() }
            }

            // Tabs
            let tabEntities = try context.fetch(FetchDescriptor<TabEntity>())
            let sortedTabs = tabEntities.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                if a.isSpacePinned != b.isSpacePinned { return a.isSpacePinned && !b.isSpacePinned }
                if a.spaceId != b.spaceId {
                    return (a.spaceId?.uuidString ?? "")
                        < (b.spaceId?.uuidString ?? "")
                }
                return a.index < b.index
            }

            let globalPinned = sortedTabs.filter { $0.isPinned }
            let spacePinned = sortedTabs.filter { $0.isSpacePinned && !$0.isPinned }
            let normals = sortedTabs.filter { !$0.isPinned && !$0.isSpacePinned }

            // Global pinned → group by profile
            var pinnedMap: [UUID: [Tab]] = [:]
            let fallbackProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            var __didAssignDefaultProfile = false
            var __pending: [Tab] = []
            for e in globalPinned {
                let t = toRuntime(e)
                if let stored = e.profileId {
                    var arr = pinnedMap[stored] ?? []
                    arr.append(t)
                    pinnedMap[stored] = arr
                } else if let fb = fallbackProfileId {
                    t.profileId = fb
                    __didAssignDefaultProfile = true
                    var arr = pinnedMap[fb] ?? []
                    arr.append(t)
                    pinnedMap[fb] = arr
                } else {
                    // No fallback available yet; defer until reattach when currentProfile is known
                    __pending.append(t)
                }
            }
            self.pinnedByProfile = pinnedMap
            self.pendingPinnedWithoutProfile = __pending
            
            // Load space-pinned tabs
            for e in spacePinned {
                let t = toRuntime(e)
                if let sid = e.spaceId {
                    var arr = spacePinnedTabs[sid] ?? []
                    arr.append(t)
                    setSpacePinnedTabs(arr, for: sid)
                }
            }

            // Load regular tabs
            for e in normals {
                let t = toRuntime(e)
                if let sid = e.spaceId {
                    var arr = tabsBySpace[sid] ?? []
                    arr.append(t)
                    setTabs(arr, for: sid)
                }
            }

            // Folders
            let folderEntities = try context.fetch(FetchDescriptor<FolderEntity>())
            for e in folderEntities.sorted(by: { $0.index < $1.index }) {
                let resolvedSpaceId = e.spaceId
                let folder = TabFolder(
                    id: e.id,
                    name: e.name,
                    spaceId: resolvedSpaceId,
                    icon: e.icon,
                    color: NSColor(hex: e.color) ?? .controlAccentColor,
                    index: e.index,
                    isRegular: e.isRegular
                )
                folder.isOpen = e.isOpen
                var folders = foldersBySpace[resolvedSpaceId] ?? []
                folders.append(folder)
                setFolders(folders, for: resolvedSpaceId)
            }

            // Repair orphan folder references left by older transfer code. Keep the tab
            // in its existing container and expose it as a loose tab instead of hiding it.
            for tab in allTabsAllSpaces() {
                if let fid = tab.folderId {
                    let folder = tab.spaceId.flatMap { foldersBySpace[$0]?.first { $0.id == fid } }
                    if folder == nil || tab.isPinned || folder?.isRegular != !tab.isSpacePinned {
                        tab.folderId = nil
                    }
                }
            }
            for space in spaces {
                space.activeTabId = validActiveTabID(space.activeTabId, in: space)
            }

            // Attach browser manager
            for t in allTabsAllSpaces() {
                t.browserManager = browserManager
            }

            // State
            let states = try context.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first
            // Ensure there's always at least one space
            if spaces.isEmpty {
                let personalSpace = Space(name: "Personal", icon: "person.crop.circle", gradient: .default)
                spaces.append(personalSpace)
                setTabs([], for: personalSpace.id)
                self.currentSpace = personalSpace
                persistSnapshot() // Save the initial space
            } else {
                if let sid = state?.currentSpaceID,
                    let match = spaces.first(where: { $0.id == sid })
                {
                    self.currentSpace = match
                } else {
                    self.currentSpace = spaces.first
                }
            }

            let spacePinnedForSelection = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
            let allForSelection =
                self.essentialTabs(for: currentSpace?.profileId)
                + spacePinnedForSelection
                + (currentSpace.flatMap { tabsBySpace[$0.id] } ?? [])
            if let id = state?.currentTabID,
                let match = allForSelection.first(where: { $0.id == id })
            {
                self.currentTab = match
            } else {
                self.currentTab = allForSelection.first
            }
            
            // If no tabs exist, create a default tab with Google.com
            if self.currentTab == nil {
                let defaultTab = createNewTab(url: "https://www.google.com", in: currentSpace)
                self.currentTab = defaultTab
            }

            // Ensure the window background uses the startup space's gradient.
            // Use an immediate set to avoid an initial animation.
            if let bm = self.browserManager, let space = self.currentSpace {
                bm.refreshGradientsForSpace(space, animate: false)
            }
            // Capture legacy profile assignments.
            if __didAssignDefaultProfile { persistSnapshot() }
            
            // Notify that initial data load is complete so window states can be updated
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        } catch {
            // A partial load would make the next full snapshot delete everything not loaded.
            // Keep the store untouched for this session.
            persistenceDisabled = true
            Self.log.fault("[loadFromStore] SwiftData load error; persistence disabled for this session: \(String(describing: error), privacy: .public)")
        }
    }

    // Set when the store failed to load or the final quit snapshot was written.
    private var persistenceDisabled = false
    private var snapshotGeneration: Int = 0
    private var persistDebounceTask: Task<Void, Never>?

    /// Debounced persistence — coalesces rapid mutations into a single write after 100ms of inactivity.
    func debouncedPersistSnapshot() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.persistSnapshot()
        }
    }

    public nonisolated func persistSnapshot() {
        Task { [weak self] in
            _ = await self?.persistSnapshotAwaitingResult()
        }
    }

    /// Termination only: writes the final snapshot before the process exits and then stops
    /// further writes, so teardown work cannot save a half-closed state. The persistence actor
    /// never hops to the main actor, so blocking the main thread here cannot deadlock.
    func persistFinalSnapshotBlocking(timeout: TimeInterval = 5) {
        persistDebounceTask?.cancel()
        guard !persistenceDisabled else { return }
        persistenceDisabled = true
        snapshotGeneration &+= 1
        let generation = snapshotGeneration
        let snapshot = _buildSnapshot()
        let persistence = self.persistence
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let result = await persistence.persist(snapshot: snapshot, generation: generation)
            Self.log.notice("[terminate] Final tab snapshot: \(String(describing: result), privacy: .public)")
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            Self.log.fault("[terminate] Final tab snapshot did not finish within \(timeout)s")
        }
    }

    // Reports whether the snapshot committed, retried, was superseded, or failed.
    public nonisolated func persistSnapshotAwaitingResult() async -> PersistenceActor.SaveResult {
        // Build snapshot and capture a generation on MainActor
        let payload: (PersistenceActor.Snapshot, Int)? = await MainActor.run { [weak self] in
            guard let strong = self, !strong.persistenceDisabled else { return nil }
            strong.snapshotGeneration &+= 1
            let gen = strong.snapshotGeneration
            let snap = strong._buildSnapshot()
            return (snap, gen)
        }
        guard let (snapshot, generation) = payload else {
            // Deallocated while switching actors, or the store failed to load
            return .failed(.invalidModelState)
        }
        return await persistence.persist(snapshot: snapshot, generation: generation)
    }

    private func validActiveTabID(_ id: UUID?, in space: Space) -> UUID? {
        guard let id else { return nil }
        let localTabs = (tabsBySpace[space.id] ?? []) + (spacePinnedTabs[space.id] ?? [])
        let essentials = essentialTabs(for: space.profileId)
        return (localTabs + essentials).contains { $0.id == id } ? id : nil
    }

    // Build a persistence snapshot from the current in-memory state (MainActor)
    private func _buildSnapshot() -> PersistenceActor.Snapshot {
        // Determine which profile IDs are ephemeral so we can exclude their data from persistence
        let profileManager = browserManager?.profileManager

        // Filter out ephemeral spaces — they belong to incognito sessions and must not persist
        let persistableSpaces = spaces.filter { !$0.isEphemeral }
        let persistableSpaceIds = Set(persistableSpaces.map { $0.id })

        // Spaces in order
        var spaceSnapshots: [PersistenceActor.SnapshotSpace] = []
        spaceSnapshots.reserveCapacity(persistableSpaces.count)
        for (sIndex, sp) in persistableSpaces.enumerated() {
            let ss = PersistenceActor.SnapshotSpace(
                id: sp.id,
                name: sp.name,
                icon: sp.icon,
                index: sIndex,
                gradientData: sp.gradient.encoded,
                activeTabId: validActiveTabID(sp.activeTabId, in: sp),
                profileId: sp.profileId
            )
            spaceSnapshots.append(ss)
        }

        // A tab whose folder is gone, in another space, or of the other type would be hidden
        // from every sidebar list and reject the whole snapshot. Repair it to a loose tab.
        var folderTypes: [UUID: (spaceId: UUID, isRegular: Bool)] = [:]
        for (spaceId, folders) in foldersBySpace {
            for folder in folders { folderTypes[folder.id] = (spaceId, folder.isRegular) }
        }
        func repairedFolderId(_ tab: Tab, spaceId: UUID?, isRegular: Bool) -> UUID? {
            guard let fid = tab.folderId else { return nil }
            if let spaceId, let folder = folderTypes[fid], folder.spaceId == spaceId, folder.isRegular == isRegular {
                return fid
            }
            Self.log.error("[snapshot] Cleared invalid folder reference on tab \(tab.id.uuidString, privacy: .public)")
            tab.folderId = nil
            return nil
        }

        // Tabs: global pinned, space pinned, and regular, with indices normalized per container
        var tabSnapshots: [PersistenceActor.SnapshotTab] = []
        // Global pinned (across profiles) — skip ephemeral profiles
        for (pid, arr) in pinnedByProfile {
            if profileManager?.isEphemeralProfile(pid) == true { continue }
            // Create copy to prevent race conditions during sorting
            let ordered = Array(arr).sorted { $0.index < $1.index }
            for (i, t) in ordered.enumerated() {
                tabSnapshots.append(.init(
                    id: t.id,
                    urlString: t.url.absoluteString,
                    name: t.name,
                    index: i,
                    spaceId: nil,
                    isPinned: true,
                    isSpacePinned: false,
                    profileId: pid,
                    folderId: repairedFolderId(t, spaceId: nil, isRegular: false),
                    displayNameOverride: t.displayNameOverride,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward,
                    pinnedURLString: t.pinnedURL?.absoluteString
                ))
            }
        }
        // Per-space collections — only persistable (non-ephemeral) spaces
        for sp in persistableSpaces {
            // Space-pinned for this space
            // Create copy to prevent race conditions during sorting
            let spPinned = Array(spacePinnedTabs[sp.id] ?? []).sorted { $0.index < $1.index }
            for (i, t) in spPinned.enumerated() {
                tabSnapshots.append(.init(
                    id: t.id,
                    urlString: t.url.absoluteString,
                    name: t.name,
                    index: i,
                    spaceId: sp.id,
                    isPinned: false,
                    isSpacePinned: true,
                    profileId: nil,
                    folderId: repairedFolderId(t, spaceId: sp.id, isRegular: false),
                    displayNameOverride: t.displayNameOverride,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward,
                    pinnedURLString: t.pinnedURL?.absoluteString
                ))
            }
            // Regular tabs for this space
            // Create copy to prevent race conditions during sorting
            let regs = Array(tabsBySpace[sp.id] ?? []).sorted { $0.index < $1.index }
            for (i, t) in regs.enumerated() {
                tabSnapshots.append(.init(
                    id: t.id,
                    urlString: t.url.absoluteString,
                    name: t.name,
                    index: i,
                    spaceId: sp.id,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    folderId: repairedFolderId(t, spaceId: sp.id, isRegular: true),
                    displayNameOverride: t.displayNameOverride,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward,
                    pinnedURLString: t.pinnedURL?.absoluteString
                ))
            }
        }

        // Folders — only for persistable spaces
        var folderSnapshots: [PersistenceActor.SnapshotFolder] = []
        for (spaceId, folders) in foldersBySpace {
            guard persistableSpaceIds.contains(spaceId) else { continue }
            let ordered = folders.sorted { $0.index < $1.index }
            for (i, folder) in ordered.enumerated() {
                folderSnapshots.append(.init(
                    id: folder.id,
                    name: folder.name,
                    icon: folder.icon,
                    color: folder.color.toHexString() ?? "#000000",
                    spaceId: spaceId,
                    isOpen: folder.isOpen,
                    index: i,
                    isRegular: folder.isRegular
                ))
            }
        }

        let selectedSpace = currentSpace.flatMap { space in
            persistableSpaceIds.contains(space.id) ? space : nil
        }
        let state = PersistenceActor.SnapshotState(
            currentTabID: selectedSpace.flatMap { validActiveTabID(currentTab?.id, in: $0) },
            currentSpaceID: selectedSpace?.id
        )

        return PersistenceActor.Snapshot(spaces: spaceSnapshots, tabs: tabSnapshots, folders: folderSnapshots, state: state)
    }
}

extension TabManager {
    /// Synchronous reattach — sets browserManager on all tabs immediately.
    /// Must be called from @MainActor context (e.g., BrowserManager.init).
    func reattachBrowserManager(_ bm: BrowserManager) {
        self.browserManager = bm
        // Use allTabs() to cover ALL tabs across ALL spaces, not just the current space
        for t in allTabs() {
            t.browserManager = bm
        }
        // Assign any pinned tabs that were loaded without a profile once currentProfile is known
        if browserManager?.currentProfile?.id != nil, !pendingPinnedWithoutProfile.isEmpty {
            // Set browserManager on those tabs
            for t in pendingPinnedWithoutProfile {
                t.browserManager = bm
                t.profileId = bm.currentProfile?.id
            }
            withCurrentProfilePinnedArray { arr in
                arr.append(contentsOf: pendingPinnedWithoutProfile)
            }
            pendingPinnedWithoutProfile.removeAll()
            persistSnapshot()
        }
        if let current = self.currentTab {
            if let match = allTabs().first(where: { $0.id == current.id }) {
                self.currentTab = match
            }
        }

        // Inform the extension controller about existing tabs and the active tab.
        // Only notify tabs that have webviews — tabs without webviews (lazy loaded)
        // will self-register via notifyTabOpened() when their webview is created in
        // Tab.setupWebView(). Registering tabs with nil webviews causes the controller
        // to cache stale state, breaking chrome.runtime messaging.
        for t in allTabs() where t.didNotifyOpenToExtensions == false && !t.isUnloaded {
            ExtensionManager.shared.notifyTabOpened(t)
            t.didNotifyOpenToExtensions = true
        }
        if let current = self.currentTab, !current.isUnloaded {
            ExtensionManager.shared.notifyTabActivated(newTab: current, previous: nil)
        }

        // After reattaching, ensure gradient matches the restored current space.
        if let space = self.currentSpace {
            bm.refreshGradientsForSpace(space, animate: false)
        }

        // After reattaching BrowserManager, backfill any missing space.profileId
        reconcileSpaceProfilesIfNeeded()
    }
}

// MARK: - Profile Cleanup & Stats
extension TabManager {
    /// Reassigns spaces from a deleted profile to a fallback profile and cleans up state.
    func cleanupProfileReferences(_ deletedProfileId: UUID) {
        // Called before the profile is removed, so it may still be first in the list.
        guard let fallback = browserManager?.profileManager.profiles.first(where: { $0.id != deletedProfileId }) else { return }
        var didChange = false
        for i in spaces.indices where spaces[i].profileId == deletedProfileId {
            spaces[i].profileId = fallback.id
            if currentSpace?.id == spaces[i].id { currentSpace?.profileId = fallback.id }
            didChange = true
        }
        // Favorites are unlinked like spaces: move them to the fallback profile, never orphan them.
        for tab in essentialTabs(for: deletedProfileId) {
            transferTab(tab, to: .essentials(fallback.id))
            didChange = true
        }
        if didChange { persistSnapshot() }
        handleProfileSwitch()
    }

    func tabCount(for profileId: UUID) -> Int {
        let spaceIds = Set(spaces.filter { $0.profileId == profileId }.map { $0.id })
        let regular = spaces.filter { spaceIds.contains($0.id) }.flatMap { tabsBySpace[$0.id] ?? [] }
        let spacePinned = spaces.filter { spaceIds.contains($0.id) }.flatMap { spacePinnedTabs[$0.id] ?? [] }
        let pinned = pinnedByProfile[profileId] ?? []
        return regular.count + spacePinned.count + pinned.count
    }

    func spaceCount(for profileId: UUID) -> Int {
        spaces.filter { $0.profileId == profileId }.count
    }
}
extension TabManager {
    func tabs(in space: Space) -> [Tab] {
        tabsBySpace[space.id] ?? []
    }
}

// MARK: - Profile Change Handling
extension TabManager {
    /// Notify TabManager that the active profile changed.
    /// Ensures the currentTab is visible for the new profile and updates compositor.
    func handleProfileSwitch() {
        // Resume any pending space activation scheduled prior to the profile switch
        if let id = pendingSpaceActivation {
            pendingSpaceActivation = nil
            if let target = spaces.first(where: { $0.id == id }) {
                setActiveSpace(target)
            }
        }

        // Build the set of visible tabs under the new profile
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        let visible = pinnedTabs + spacePinned + tabs
        if currentTab == nil || !(visible.contains { $0.id == currentTab!.id }) {
            currentTab = visible.first
            browserManager?.compositorManager.updateTabVisibility(currentTabId: currentTab?.id)
            debouncedPersistSnapshot()
        } else {
            // Still notify compositor to update visibility based on new filter
            browserManager?.compositorManager.updateTabVisibility(currentTabId: currentTab?.id)
        }
    }
}

// MARK: - Profile Assignment Helpers
extension TabManager {
    fileprivate func reconcileSpaceProfilesIfNeeded() {
        let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
        guard let pid = defaultProfileId else {
            return
        }
        var didAssign = false
        for space in spaces where space.profileId == nil {
            space.profileId = pid
            didAssign = true
        }
        if didAssign { debouncedPersistSnapshot() }
    }
}

// MARK: - Profile Validation
extension TabManager {
    /// Ensures all tabs resolve to a valid profile via their space association.
    /// If a space lacks a profile, assigns the current profile as a fallback.
    func validateTabProfileAssignments() {
        guard let fallbackPid = browserManager?.currentProfile?.id else { return }
        var didFix = false

        // For each space that has any tabs, ensure it has a profileId
        for sp in spaces {
            let hasTabs = !(tabsBySpace[sp.id] ?? []).isEmpty || !(spacePinnedTabs[sp.id] ?? []).isEmpty
            if hasTabs && sp.profileId == nil {
                sp.profileId = fallbackPid
                didFix = true
            }
        }

        if didFix { debouncedPersistSnapshot() }
    }

    /// Backward-compatible alias for validation used by BrowserManager
    func validateProfileAssignments() {
        validateTabProfileAssignments()
    }
}

// MARK: - Profile Assignment API
extension TabManager {
    /// Centralized helper to assign a space to a profile and persist.
    /// Always assigns to a valid profile (no nil assignments allowed).
    func assign(spaceId: UUID, toProfile profileId: UUID) {
        if let idx = spaces.firstIndex(where: { $0.id == spaceId }) {
            let exists = browserManager?.profileManager.profiles.contains(where: { $0.id == profileId }) ?? false
            if !exists {
                return
            }
            spaces[idx].profileId = profileId
            if currentSpace?.id == spaceId {
                currentSpace?.profileId = profileId
            }
            debouncedPersistSnapshot()
        }
    }

    // MARK: - Tab Closure Undo

    private func trackRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        let now = Date()

        // Check if we should show toast notification (2-hour cooldown)
        let shouldShowToast = shouldShowTabClosureToast(now: now)

        // Update last tab closure time
        lastTabClosureTime = now

        // Capture the ACTUAL current state at closure time
        // This ensures undo restores to the same page as browser restart would
        let canGoBack = tab.canGoBack
        let canGoForward = tab.canGoForward

        // Use tab.url which is reliably updated via didCommit/didFinish navigation delegates
        // Note: tab.webView?.url can be stale/incorrect, especially after SPA navigation
        let urlToRestore = tab.url
        let currentURL = tab.url  // For consistency in storage tuple

        // Capture current title for restoration (favicon will be re-fetched)
        let titleToRestore = tab.name


        // Create a deep copy of the tab for restoration
        let tabCopy = Tab(
            id: UUID(), // New ID for the restored tab
            url: urlToRestore,
            name: titleToRestore,
            favicon: "globe", // Default favicon, will be updated when tab loads
            spaceId: spaceId,
            index: tab.index
        )
        tabCopy.browserManager = browserManager

        // Copy additional properties
        tabCopy.isPinned = tab.isPinned
        tabCopy.isSpacePinned = tab.isSpacePinned
        tabCopy.folderId = tab.folderId
        tabCopy.profileId = tab.profileId
        tabCopy.pinnedURL = tab.pinnedURL
        tabCopy.displayNameOverride = tab.displayNameOverride

        // Store snapshot with navigation state for accurate restoration
        recentlyClosedTabs.append((
            tab: tabCopy,
            spaceId: spaceId,
            currentURL: currentURL,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            timestamp: now
        ))

        // Schedule cleanup of expired tabs
        scheduleUndoTimerCleanup()

        // Show toast notification only if cooldown has passed
        if shouldShowToast {
            browserManager?.showTabClosureToast(tabCount: 1)
        }
    }

    private func trackRecentlyClosedTabs(_ tabs: [(tab: Tab, spaceId: UUID?)], count: Int) {
        let now = Date()

        // Update last tab closure time for cooldown
        lastTabClosureTime = now

        // Create deep copies of all tabs for restoration with current state snapshot
        for (tab, spaceId) in tabs {
            // Capture the ACTUAL current state at closure time
            let canGoBack = tab.canGoBack
            let canGoForward = tab.canGoForward

            // Use tab.url which is reliably updated via didCommit/didFinish navigation delegates
            // Note: tab.webView?.url can be stale/incorrect, especially after SPA navigation
            let urlToRestore = tab.url
            let currentURL = tab.url  // For consistency in storage tuple

            // Capture current title for restoration (favicon will be re-fetched)
            let titleToRestore = tab.name

            let tabCopy = Tab(
                id: UUID(), // New ID for the restored tab
                url: urlToRestore,
                name: titleToRestore,
                favicon: "globe", // Default favicon, will be updated when tab loads
                spaceId: spaceId,
                index: tab.index
            )
            tabCopy.browserManager = browserManager

            // Copy additional properties
            tabCopy.isPinned = tab.isPinned
            tabCopy.isSpacePinned = tab.isSpacePinned
            tabCopy.folderId = tab.folderId
            tabCopy.profileId = tab.profileId
            tabCopy.pinnedURL = tab.pinnedURL
            tabCopy.displayNameOverride = tab.displayNameOverride

            // Store snapshot with navigation state for accurate restoration
            recentlyClosedTabs.append((
                tab: tabCopy,
                spaceId: spaceId,
                currentURL: currentURL,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                timestamp: now
            ))
        }

        // Schedule cleanup of expired tabs
        scheduleUndoTimerCleanup()

        // Always show toast for bulk operations (bypass cooldown)
        browserManager?.showTabClosureToast(tabCount: count)
    }

    private func shouldShowTabClosureToast(now: Date) -> Bool {
        guard let lastClosure = lastTabClosureTime else {
            // First tab closure, show the toast
            return true
        }

        // Check if at least 2 hours have passed since last tab closure
        return now.timeIntervalSince(lastClosure) >= toastCooldown
    }

    func undoCloseTab() {
        guard !recentlyClosedTabs.isEmpty else { return }

        let mostRecent = recentlyClosedTabs.removeLast()

        // The copy is a fresh web view with no history; don't restore Back/Forward state it can't honor.
        // Restore the tab with its navigation state from when it was closed
        restoreClosedTab(mostRecent.tab)
        selectRestoredTab(mostRecent.tab)

        // Clear the timer if no more tabs to undo
        if recentlyClosedTabs.isEmpty {
            clearUndoTimer()
        }
    }

    func undoCloseMultipleTabs(count: Int) {
        let actualCount = min(count, recentlyClosedTabs.count)
        var restoredTabs: [Tab] = []

        for _ in 0..<actualCount {
            guard !recentlyClosedTabs.isEmpty else { break }
            let tabInfo = recentlyClosedTabs.removeLast()
            restoredTabs.append(tabInfo.tab)

            restoreClosedTab(tabInfo.tab)
        }

        // Set the most recently restored tab as active
        if let lastTab = restoredTabs.last {
            selectRestoredTab(lastTab)
        }

        // Clear the timer if no more tabs to undo
        if recentlyClosedTabs.isEmpty {
            clearUndoTimer()
        }
    }

    /// Puts an undo copy back through the normal transfer rules. Its space or folder may have
    /// been deleted since it closed; it then lands as a loose tab in the current space.
    private func restoreClosedTab(_ tab: Tab) {
        let wasEssential = tab.isPinned
        let wasSpacePinned = tab.isSpacePinned
        let folderId = tab.folderId
        let profileId = tab.profileId
        let formerIndex = tab.index
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.folderId = nil
        tab.profileId = nil
        addTab(tab)
        guard contains(tab), let spaceId = tab.spaceId else { return }

        // Final placement always goes through transferTab, which renumbers the bucket.
        if wasEssential, let pid = profileId ?? browserManager?.currentProfile?.id,
           transferTab(tab, to: .essentials(pid), index: formerIndex) {
            return
        }
        if let folderId, transferTab(tab, to: .folder(folderId), index: formerIndex) { return }
        transferTab(tab, to: .space(spaceId, pinned: wasSpacePinned), index: formerIndex)
    }

    private func selectRestoredTab(_ tab: Tab) {
        if let browserManager, browserManager.windowRegistry?.activeWindow != nil {
            browserManager.selectTab(tab)
        } else {
            setActiveTab(tab)
        }
    }

    private func scheduleUndoTimerCleanup() {
        // Clear any existing timer
        clearUndoTimer()

        // Schedule a new timer to clean up expired tabs
        undoTimer = Timer.scheduledTimer(withTimeInterval: undoDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredTabs()
            }
        }
    }

    private func cleanupExpiredTabs() {
        let now = Date()
        recentlyClosedTabs.removeAll { tabInfo in
            now.timeIntervalSince(tabInfo.timestamp) >= undoDuration
        }

        if recentlyClosedTabs.isEmpty {
            clearUndoTimer()
        }
    }

    private func clearUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = nil
    }

    func clearRecentlyClosedTabs() {
        recentlyClosedTabs.removeAll()
        clearUndoTimer()

        // Reset toast cooldown timer when no more tabs to undo
        // This allows the toast to appear again on next tab closure after 2 hours
        lastTabClosureTime = nil
    }

    func hasRecentlyClosedTabs() -> Bool {
        return !recentlyClosedTabs.isEmpty
    }

    // MARK: - Navigation State Management

    /// Called when a tab's navigation state changes to ensure it's persisted
    func updateTabNavigationState(_ tab: Tab) {
        debouncedPersistSnapshot()
    }

    // MARK: - Bulk Tab Operations

    /// Regular tabs shown in the same sidebar group as `tab`: its folder, or the loose tabs.
    private func regularGroupTabs(of tab: Tab) -> [Tab] {
        guard let spaceId = tab.spaceId else { return [] }
        return (tabsBySpace[spaceId] ?? []).filter { $0.folderId == tab.folderId }.sorted { $0.index < $1.index }
    }

    func closeOtherTabs(_ tab: Tab) {
        guard let spaceId = tab.spaceId else { return }
        let group = regularGroupTabs(of: tab)
        guard group.contains(where: { $0.id == tab.id }) else { return }

        let otherTabs = group.filter { $0.id != tab.id }

        if otherTabs.isEmpty { return }

        let tabsToTrack = otherTabs.map { (tab: $0, spaceId: spaceId) }

        for tabToClose in otherTabs {
            removeTab(tabToClose.id, track: false)
        }

        trackRecentlyClosedTabs(tabsToTrack, count: otherTabs.count)
    }

    func closeAllTabsBelow(_ tab: Tab) {
        guard let spaceId = tab.spaceId else { return }
        let group = regularGroupTabs(of: tab)
        guard group.contains(where: { $0.id == tab.id }) else { return }

        // Tabs below within the same visible group
        let tabsBelow = group.filter { $0.index > tab.index }

        // Return early if no tabs below
        if tabsBelow.isEmpty { return }

        // Prepare tabs for tracking
        let tabsToTrack = tabsBelow.map { (tab: $0, spaceId: spaceId) }

        // Close all tabs below
        for tabToClose in tabsBelow {
            // Close the tab without tracking (we'll do bulk tracking)
            removeTab(tabToClose.id, track: false)
        }

        // Track all closed tabs for undo and show toast
        trackRecentlyClosedTabs(tabsToTrack, count: tabsBelow.count)
    }
}
