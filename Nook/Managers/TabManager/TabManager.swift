import AppKit
import Combine
import Observation
import SwiftData
import WebKit
import OSLog

// MARK: - Persistence Actor & Types

/// Serializes all SwiftData writes for Tab snapshots and provides
/// a best-effort atomic save using a child ModelContext pattern.
    actor PersistenceActor {
    private let container: ModelContainer
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "TabPersistence")

    // Lightweight, in-memory backup of the most recent snapshot
    // to allow quick recovery if atomic operations fail mid-flight.
    private var lastBackupJSON: Data?

    enum PersistenceError: Error {
        case concurrencyConflict
        case dataCorruption
        case storageFailure
        case rollbackFailed
        case invalidModelState
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

        // Navigation state
        let currentURLString: String?
        let canGoBack: Bool
        let canGoForward: Bool
    }

    struct SnapshotFolder: Codable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let spaceId: UUID
        let isOpen: Bool
        let index: Int
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
    // Returns true if the atomic path succeeded. False if a fallback or staleness short-circuit occurred.
    func persist(snapshot: Snapshot, generation: Int) async -> Bool {
        // Coalesce stale generations
        if generation < self.latestGeneration {
            Self.log.debug("[persist] Skipping stale snapshot generation=\(generation) < latest=\(self.latestGeneration)")
            return false
        }
        self.latestGeneration = generation
        let start = Date()
        Self.log.debug("[persist] Starting atomic persistence…")
        do {
            // Backup current intent/state to JSON first
            try createDataSnapshot(snapshot)
            try await performAtomicPersistence(snapshot)
            Self.log.notice("[persist] Atomic persistence completed in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            return true
        } catch {
            let classified = classify(error)
            Self.log.error("[persist] Atomic persistence failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)")

            // Attempt graceful recovery: try best-effort fallback, else restore
            do {
                try await performBestEffortPersistence(snapshot)
                Self.log.notice("[persist] Fallback persistence succeeded after atomic failure")
                return false
            } catch {
                Self.log.fault("[persist] Fallback persistence failed: \(String(describing: error), privacy: .public). Attempting recovery from backup…")
                do {
                    try await recoverFromBackup()
                    Self.log.notice("[persist] Recovered from in-memory backup snapshot")
                    return false
                } catch {
                    Self.log.fault("[persist] Backup recovery failed: \(String(describing: error), privacy: .public)")
                    return false
                }
            }
        }
    }

    // MARK: - Atomic Transaction Helper
    private func performAtomicPersistence(_ snapshot: Snapshot) async throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Validate inputs before writing
        try validateInput(snapshot)

        // 1) Cleanup orphans for TabEntity
        do {
            let all = try ctx.fetch(FetchDescriptor<TabEntity>())
            let keepIDs = Set(snapshot.tabs.map { $0.id })
            for e in all where !keepIDs.contains(e.id) { ctx.delete(e) }
        } catch {
            throw classify(error)
        }

        // 2) Upsert tabs: global pinned, space pinned, and regular
        for tab in snapshot.tabs {
            try upsertTab(in: ctx, tab)
        }

        // 3) Upsert folders and cleanup removed folders
        for folder in snapshot.folders {
            try upsertFolder(in: ctx, folder)
        }
        do {
            let allFolders = try ctx.fetch(FetchDescriptor<FolderEntity>())
            let keep = Set(snapshot.folders.map { $0.id })
            for e in allFolders where !keep.contains(e.id) { ctx.delete(e) }
        } catch {
            throw classify(error)
        }

        // 4) Upsert spaces and cleanup removed spaces
        for space in snapshot.spaces {
            try upsertSpace(in: ctx, space)
        }
        do {
            let allSpaces = try ctx.fetch(FetchDescriptor<SpaceEntity>())
            let keep = Set(snapshot.spaces.map { $0.id })
            for e in allSpaces where !keep.contains(e.id) { ctx.delete(e) }
        } catch {
            throw classify(error)
        }

        // 4) Upsert state
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

        // 5) Integrity validation before save (so failures abort atomically)
        try validateDataIntegrity(in: ctx, snapshot: snapshot)

        // 6) Save (commit atomic set)
        do {
            try ctx.save()
        } catch {
            throw classify(error)
        }

        // 7) Post-save integrity check (non-fatal)
        do {
            try validateDataIntegrity(in: ctx, snapshot: snapshot)
        } catch {
            Self.log.error("[persist] Post-save integrity validation reported issues: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Entity Ops
    private func upsertTab(in ctx: ModelContext, _ t: SnapshotTab) throws {
        let predicate = #Predicate<TabEntity> { $0.id == t.id }
        let existing = try ctx.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
        if let e = existing {
            e.urlString = t.urlString
            e.name = t.name
            e.isPinned = t.isPinned
            e.isSpacePinned = t.isSpacePinned
            e.index = t.index
            e.spaceId = t.spaceId
            e.profileId = t.profileId
            e.folderId = t.folderId
            e.currentURLString = t.currentURLString
            e.canGoBack = t.canGoBack
            e.canGoForward = t.canGoForward
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
                currentURLString: t.currentURLString,
                canGoBack: t.canGoBack,
                canGoForward: t.canGoForward
            )
            ctx.insert(e)
        }
    }

    private func upsertFolder(in ctx: ModelContext, _ f: SnapshotFolder) throws {
        let predicate = #Predicate<FolderEntity> { $0.id == f.id }
        let existing = try ctx.fetch(FetchDescriptor<FolderEntity>(predicate: predicate)).first
        if let e = existing {
            e.name = f.name
            e.icon = f.icon
            e.color = f.color
            e.spaceId = f.spaceId
            e.isOpen = f.isOpen
            e.index = f.index
        } else {
            let e = FolderEntity(
                id: f.id,
                name: f.name,
                icon: f.icon,
                color: f.color,
                spaceId: f.spaceId,
                isOpen: f.isOpen,
                index: f.index
            )
            ctx.insert(e)
        }
    }

    private func upsertSpace(in ctx: ModelContext, _ s: SnapshotSpace) throws {
        let predicate = #Predicate<SpaceEntity> { $0.id == s.id }
        let existing = try ctx.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate)).first
        if let e = existing {
            e.name = s.name
            e.icon = s.icon
            e.index = s.index
            if let data = s.gradientData { e.gradientData = data }
            e.profileId = s.profileId
        } else {
            let e = SpaceEntity(
                id: s.id,
                name: s.name,
                icon: s.icon,
                index: s.index,
                gradientData: s.gradientData ?? (SpaceGradient.default.encoded ?? Data()),
                profileId: s.profileId
            )
            ctx.insert(e)
        }
    }

    // MARK: - Backup & Recovery
    private func createDataSnapshot(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.lastBackupJSON = try encoder.encode(snapshot)
    }

    private func recoverFromBackup() async throws {
        guard let data = lastBackupJSON else { return }
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        try await performBestEffortPersistence(snapshot)
    }

    // Best-effort non-atomic writes on the main context. Used only as a fallback.
    private func performBestEffortPersistence(_ snapshot: Snapshot) async throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        // Cleanup tabs
        do {
            let all = try ctx.fetch(FetchDescriptor<TabEntity>())
            let keepIDs = Set(snapshot.tabs.map { $0.id })
            for e in all where !keepIDs.contains(e.id) { ctx.delete(e) }
        } catch {
            throw classify(error)
        }
        // Upserts
        for t in snapshot.tabs {
            do { try upsertTab(in: ctx, t) } catch { throw classify(error) }
        }
        for s in snapshot.spaces {
            do { try upsertSpace(in: ctx, s) } catch { throw classify(error) }
        }
        do {
            let allSpaces = try ctx.fetch(FetchDescriptor<SpaceEntity>())
            let keep = Set(snapshot.spaces.map { $0.id })
            for e in allSpaces where !keep.contains(e.id) { ctx.delete(e) }
        } catch {
            throw classify(error)
        }
        do {
            let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>())
            let st = states.first ?? {
                let s = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
                ctx.insert(s)
                return s
            }()
            st.currentTabID = snapshot.state.currentTabID
            st.currentSpaceID = snapshot.state.currentSpaceID
        } catch {
            throw classify(error)
        }
        do {
            try ctx.save()
        } catch {
            throw classify(error)
        }
    }

    // MARK: - Validation
    private func validateInput(_ snapshot: Snapshot) throws {
        // Basic invariants: indices non-negative, ids unique
        if snapshot.tabs.contains(where: { $0.index < 0 }) { throw PersistenceError.invalidModelState }
        let tabIDs = Set(snapshot.tabs.map { $0.id })
        if tabIDs.count != snapshot.tabs.count { throw PersistenceError.invalidModelState }
        let spaceIDs = Set(snapshot.spaces.map { $0.id })
        if spaceIDs.count != snapshot.spaces.count { throw PersistenceError.invalidModelState }
        // Ensure all spaceIds referenced by tabs exist (or are nil) and flag invariants
        for t in snapshot.tabs {
            if let sid = t.spaceId, !spaceIDs.contains(sid) { throw PersistenceError.invalidModelState }
            // Mutual exclusivity of pinned flags
            if t.isPinned && t.isSpacePinned { throw PersistenceError.invalidModelState }
            // Global pinned cannot have a spaceId
            if t.isPinned && t.spaceId != nil { throw PersistenceError.invalidModelState }
            // Space-pinned must have a spaceId
            if t.isSpacePinned && t.spaceId == nil { throw PersistenceError.invalidModelState }
        }

        // TODO: Once profiles participate in snapshots, validate that each space.profileId
        // corresponds to a known Profile. For now, log missing profile assignments after migration.
        for s in snapshot.spaces {
            if s.profileId == nil {
                Self.log.debug("[validate] Space missing profileId: \(s.id.uuidString, privacy: .public)")
            }
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

    // Tab closure undo tracking
    private var recentlyClosedTabs: [(tab: Tab, spaceId: UUID?, timestamp: Date)] = []
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
        // Always present pinned in sorted order by index - create copy to prevent race conditions
        return Array(pinnedByProfile[pid] ?? []).sorted { $0.index < $1.index }
    }
    
    var essentialTabs: [Tab] { pinnedTabs }
    
    func essentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId = profileId else { return [] }
        // Create copy to prevent race conditions during sorting
        return Array(pinnedByProfile[profileId] ?? []).sorted { $0.index < $1.index }
    }
    
    // Flattened pinned across all profiles for internal ops
    private var allPinnedTabsAllProfiles: [Tab] {
        pinnedByProfile.values.flatMap { $0 }
    }

    // Currently active tab
    private(set) var currentTab: Tab?

    init(browserManager: BrowserManager? = nil, context: ModelContext) {
        self.browserManager = browserManager
        self.context = context
        self.persistence = PersistenceActor(container: context.container)
        Task { @MainActor in
            loadFromStore()
        }
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

        print("🧹 [TabManager] Cleaned up all tab resources")
    }

    // MARK: - Convenience

    var tabs: [Tab] {
        guard let s = currentSpace else { return [] }
        // Create copy to prevent race conditions during sorting
        return Array(tabsBySpace[s.id] ?? []).sorted { $0.index < $1.index }
    }

    private func setTabs(_ items: [Tab], for spaceId: UUID) {
        var updated = tabsBySpace
        updated[spaceId] = items
        tabsBySpace = updated
    }

    private func setSpacePinnedTabs(_ items: [Tab], for spaceId: UUID) {
        var updated = spacePinnedTabs
        updated[spaceId] = items
        spacePinnedTabs = updated
    }

    private func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        var updated = foldersBySpace
        updated[spaceId] = items
        foldersBySpace = updated
    }

    private func setPinnedTabs(_ items: [Tab], for profileId: UUID) {
        var updated = pinnedByProfile
        updated[profileId] = items
        pinnedByProfile = updated
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
        print("🔍 contains() checking tab: \(tab.name)")
        print("   - tab.id: \(tab.id)")
        print("   - tab.spaceId: \(tab.spaceId?.uuidString ?? "nil")")
        print("   - tab.folderId: \(tab.folderId?.uuidString ?? "nil")")
        print("   - tab.isPinned: \(tab.isPinned)")
        print("   - tab.isSpacePinned: \(tab.isSpacePinned)")

        // Check global pinned tabs
        if allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) {
            print("✅ Found tab in allPinnedTabsAllProfiles")
            return true
        }

        // Check space-specific tabs
        if let sid = tab.spaceId {
            print("🔍 Checking space-specific tabs for spaceId: \(sid)")

            // Check space pinned tabs
            if let spacePinned = spacePinnedTabs[sid] {
                print("   - spacePinnedTabs[\(sid)] has \(spacePinned.count) tabs")
                let foundInSpacePinned = spacePinned.contains(where: { $0.id == tab.id })
                print("   - found in spacePinnedTabs: \(foundInSpacePinned)")
                if foundInSpacePinned { return true }
            } else {
                print("   - spacePinnedTabs[\(sid)] is nil")
            }

            // Check regular tabs
            if let arr = tabsBySpace[sid] {
                print("   - tabsBySpace[\(sid)] has \(arr.count) tabs")
                let foundInRegular = arr.contains(where: { $0.id == tab.id })
                print("   - found in tabsBySpace: \(foundInRegular)")
                if foundInRegular { return true }
            } else {
                print("   - tabsBySpace[\(sid)] is nil")
            }
        } else {
            print("❌ tab.spaceId is nil")
        }

        print("❌ Tab not found in any container")
        return false
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

        persistSnapshot()
        return space
    }

    func removeSpace(_ id: UUID) {
        guard spaces.count > 1 else {
            return
        }
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else {
            return
        }
        // Move tabs out or close them; here we close normal tabs of the space
        let closing = tabsBySpace[id] ?? []
        let spacePinnedClosing = spacePinnedTabs[id] ?? []
        for t in closing + spacePinnedClosing {
            if currentTab?.id == t.id { currentTab = nil }
        }
        setTabs([], for: id)
        setSpacePinnedTabs([], for: id)
        if idx < spaces.count { spaces.remove(at: idx) }
        if currentSpace?.id == id {
            currentSpace = spaces.first
        }

        persistSnapshot()

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
            } else {
                print("⚠️ [TabManager] No profiles available to assign to space")
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

        persistSnapshot()
        // Notify extensions only on real activation change
        if isTabChanging, #available(macOS 15.5, *), let newActive = currentTab {
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

        persistSnapshot()
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        guard let idx = spaces.firstIndex(where: { $0.id == spaceId }), idx < spaces.count else {
            throw TabManagerError.spaceNotFound(spaceId)
        }
        spaces[idx].icon = icon

        if currentSpace?.id == spaceId {
            currentSpace?.icon = icon
        }

        persistSnapshot()
    }

    // MARK: - Folder Management

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        print("📁 Creating folder for spaceId: \(spaceId.uuidString)")
        let folder = TabFolder(
            name: name,
            spaceId: spaceId,
            color: spaces.first(where: { $0.id == spaceId })?.color ?? .controlAccentColor
        )
        print("   Created folder: \(folder.name) (id: \(folder.id.uuidString.prefix(8))...)")

        var folders = foldersBySpace[spaceId] ?? []
        folders.append(folder)
        setFolders(folders, for: spaceId)

        // Send notification for SpaceView folderChangeCount
        NotificationCenter.default.post(name: .init("TabFoldersDidChange"), object: nil)

        persistSnapshot()
        return folder
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        for (_, folders) in foldersBySpace {
            if let folder = folders.first(where: { $0.id == folderId }) {
                folder.name = newName
                // SwiftUI will automatically detect changes to @Published foldersBySpace
                persistSnapshot()
                break
            }
        }
    }

    func deleteFolder(_ folderId: UUID) {
        print("🗑️ Deleting folder: \(folderId.uuidString)")
        // Find and remove the folder
        for (spaceId, folders) in foldersBySpace {
            if let index = folders.firstIndex(where: { $0.id == folderId }) {
                let folder = folders[index]
                print("   Found folder '\(folder.name)' in space \(spaceId.uuidString.prefix(8))...")

                // Move all tabs in folder to space pinned area
                var movedTabsCount = 0
                for tab in allTabs() {
                    if tab.folderId == folderId {
                        tab.folderId = nil
                        tab.isSpacePinned = true
                        movedTabsCount += 1
                    }
                }
                print("   Moved \(movedTabsCount) tabs out of folder")

                // Remove the folder
                var mutableFolders = folders
                mutableFolders.remove(at: index)
                setFolders(mutableFolders, for: spaceId)

                // Send notification for SpaceView folderChangeCount
                NotificationCenter.default.post(name: .init("TabFoldersDidChange"), object: nil)

                persistSnapshot()
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
                persistSnapshot()
                break
            }
        }
    }
    func moveTabToFolder(tab: Tab, folderId: UUID) {
        let newTab = tab
        removeFromCurrentContainer(newTab)
        newTab.folderId = folderId
        newTab.isSpacePinned = true
        var sp = spacePinnedTabs[tab.spaceId!] ?? []
        sp.append(tab)
        // Reindex
        for (i, t) in sp.enumerated() { t.index = i }
        setSpacePinnedTabs(sp, for: tab.spaceId!)
    }

    // MARK: - Tab Management (Normal within current space)

    func addTab(_ tab: Tab) {
        attach(tab)
        if contains(tab) { return }

        if tab.spaceId == nil {
            tab.spaceId = currentSpace?.id
        }
        guard let sid = tab.spaceId else {
            print("Cannot add normal tab without a spaceId")
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
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabOpened(tab)
        }
        
        print("Added tab: \(tab.name) to space \(sid)")
        persistSnapshot()
    }

    func removeTab(_ id: UUID) {
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
        trackRecentlyClosedTab(tab, spaceId: removedSpaceId)

        // Force unload the tab from compositor before removing
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)

        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabClosed(tab)
        }

        if wasCurrent {
            if tab.spaceId == nil {
                // Tab was global pinned
                if !pinnedTabs.isEmpty {
                    currentTab = pinnedTabs.last
                } else if let cs = currentSpace {
                    let spacePinned = spacePinnedTabs[cs.id] ?? []
                    let arr = tabsBySpace[cs.id] ?? []
                    currentTab = spacePinned.last ?? arr.last
                } else {
                    currentTab = nil
                }
            } else if let cs = currentSpace {
                // Tab was in a space
                let spacePinned = spacePinnedTabs[cs.id] ?? []
                let arr = tabsBySpace[cs.id] ?? []
                
                if let i = removedIndexInCurrentSpace {
                    // Try to select adjacent tab
                    let allSpaceTabs = spacePinned + arr
                    if !allSpaceTabs.isEmpty {
                        let newIndex = min(i, allSpaceTabs.count - 1)
                        currentTab = allSpaceTabs.indices.contains(newIndex) 
                            ? allSpaceTabs[newIndex] 
                            : allSpaceTabs.first
                    } else if !pinnedTabs.isEmpty {
                        currentTab = pinnedTabs.last
                    } else {
                        currentTab = nil
                    }
                } else {
                    // Fallback to last tab
                    currentTab = arr.last ?? spacePinned.last ?? pinnedTabs.last
                }
            }
        }

        persistSnapshot()
        
        // Validate window states after tab removal
        browserManager?.validateWindowStates()
    }

    func setActiveTab(_ tab: Tab) {
        print("🎯 setActiveTab called for: \(tab.name)")
        print("   - tab.id: \(tab.id)")
        print("   - tab.spaceId: \(tab.spaceId?.uuidString ?? "nil")")
        print("   - tab.folderId: \(tab.folderId?.uuidString ?? "nil")")
        print("   - tab.isPinned: \(tab.isPinned)")
        print("   - tab.isSpacePinned: \(tab.isSpacePinned)")
        print("   - currentSpace.id: \(currentSpace?.id.uuidString ?? "nil")")

        // Show current data structure state
        if let currentSpace = currentSpace {
            print("🔍 Current data structure state:")
            print("   - spacePinnedTabs[\(currentSpace.id)]: \(spacePinnedTabs[currentSpace.id]?.count ?? 0) tabs")
            print("   - tabsBySpace[\(currentSpace.id)]: \(tabsBySpace[currentSpace.id]?.count ?? 0) tabs")

            // List what's in spacePinnedTabs for this space
            if let spacePinned = spacePinnedTabs[currentSpace.id] {
                print("   - spacePinned tabs: \(spacePinned.map { "\($0.name) (id: \($0.id.uuidString.prefix(8))...)" })")
            }
        }

        guard contains(tab) else {
            print("❌ setActiveTab failed: tab not found in contains() check")
            return
        }
        print("✅ contains() check passed - tab found in data structures")

        let previous = currentTab
        print("🔄 Setting currentTab from \(previous?.name ?? "nil") to \(tab.name)")
        currentTab = tab
        print("✅ currentTab set successfully to: \(currentTab?.name ?? "nil")")
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
        print("💾 Saving tab as active for space...")
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            print("   - Found space: \(space.name)")
            print("   - Setting space.activeTabId to: \(tab.id)")
            space.activeTabId = tab.id
            print("   - Setting currentSpace to: \(space.name)")
            currentSpace = space
            print("   - ✅ Space activation complete")
        } else if let cs = currentSpace {
            print("   - Using currentSpace: \(cs.name)")
            print("   - Setting cs.activeTabId to: \(tab.id)")
            cs.activeTabId = tab.id
            print("   - ✅ Current space activation complete")
        } else {
            print("   - ❌ No space found for tab activation")
        }
        
        persistSnapshot()
    }
    
    /// Update only the global tab state without triggering UI operations
    /// Used when BrowserManager.selectTab() has already handled all UI concerns
    func updateActiveTabState(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        currentTab = tab
        
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
        persistSnapshot()
    }

    @discardableResult
    func createNewTab(
        url: String = "https://www.google.com",
        in space: Space? = nil
    ) -> Tab {
        let engine = nookSettings?.searchEngine ?? .google
        let normalizedUrl = normalizeURL(url, provider: engine)
        guard let validURL = URL(string: normalizedUrl)
        else {
            print("Invalid URL: \(url). Falling back to default.")
            return createNewTab(in: space)
        }
        
        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                persistSnapshot()
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

    // Create a new tab with an existing WebView (used for Peek transfers)
    @discardableResult
    func createNewTabWithWebView(
        url: String = "https://www.google.com",
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        let engine = nookSettings?.searchEngine ?? .google
        let normalizedUrl = normalizeURL(url, provider: engine)
        guard let validURL = URL(string: normalizedUrl)
        else {
            print("Invalid URL: \(url). Falling back to default.")
            return createNewTab(in: space)
        }

        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                persistSnapshot()
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
                persistSnapshot()
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
            print("No active tab to close")
            return
        }
        removeTab(currentTab.id)
    }

    func clearRegularTabs(for spaceId: UUID) {
        guard let tabs = tabsBySpace[spaceId] else { return }

        print("🧹 [TabManager] Clearing \(tabs.count) regular tabs for space \(spaceId)")

        // Remove all regular tabs for this space
        for tab in tabs {
            if(tab.id != self.currentTab?.id) {
                removeTab(tab.id)
            }
        }

        persistSnapshot()
    }
    
    func unloadTab(_ tab: Tab) {
        // Never unload essentials tabs except on browser close/restart
        guard !allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else { return }
        browserManager?.compositorManager.unloadTab(tab)
    }
    
    func unloadAllInactiveTabs() {
        // Only unload regular tabs, never essentials (pinned) tabs
        for tab in tabs {
            if tab.id != currentTab?.id {
                unloadTab(tab)
            }
        }
    }

    // MARK: - Drag & Drop Operations
    
    func handleDragOperation(_ operation: DragOperation) {
        let tab = operation.tab
        
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            reorderGlobalPinnedTabs(tab, to: operation.toIndex)
            
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)):
            if fromSpaceId == toSpaceId {
                reorderSpacePinnedTabs(tab, in: toSpaceId, to: operation.toIndex)
            } else {
                moveTabBetweenSpaces(tab, from: fromSpaceId, to: toSpaceId, asSpacePinned: true, toIndex: operation.toIndex)
            }
            
        case (.spaceRegular(let fromSpaceId), .spaceRegular(let toSpaceId)):
            if fromSpaceId == toSpaceId {
                reorderRegularTabs(tab, in: toSpaceId, to: operation.toIndex)
            } else {
                moveTabBetweenSpaces(tab, from: fromSpaceId, to: toSpaceId, asSpacePinned: false, toIndex: operation.toIndex)
            }
            
        case (.spaceRegular(let spaceId), .spacePinned(let targetSpaceId)):
            // Regular tab to space pinned
            if spaceId == targetSpaceId {
                pinTabToSpace(tab, spaceId: spaceId)
                reorderSpacePinnedTabs(tab, in: spaceId, to: operation.toIndex)
            } else {
                moveTabBetweenSpaces(tab, from: spaceId, to: targetSpaceId, asSpacePinned: true, toIndex: operation.toIndex)
            }
            
        case (.spacePinned(let spaceId), .spaceRegular(let targetSpaceId)):
            // Space pinned to regular tab
            if spaceId == targetSpaceId {
                unpinTabFromSpace(tab)
                reorderRegularTabs(tab, in: spaceId, to: operation.toIndex)
            } else {
                moveTabBetweenSpaces(tab, from: spaceId, to: targetSpaceId, asSpacePinned: false, toIndex: operation.toIndex)
            }
            
        case (.spaceRegular(_), .essentials):
            // Regular -> Essentials: ensure a valid profile before removing from source
            guard browserManager?.currentProfile?.id != nil else { return }
            // Now safe to move
            removeFromCurrentContainer(tab)
            tab.spaceId = nil
            withCurrentProfilePinnedArray { arr in
                let safeIndex = max(0, min(operation.toIndex, arr.count))
                arr.insert(tab, at: safeIndex)
            }
            persistSnapshot()
            
        case (.spacePinned(_), .essentials):
            // SpacePinned -> Essentials: ensure a valid profile before removing from source
            guard browserManager?.currentProfile?.id != nil else { return }
            // Now safe to move
            removeFromCurrentContainer(tab)
            tab.spaceId = nil
            withCurrentProfilePinnedArray { arr in
                let safeIndex = max(0, min(operation.toIndex, arr.count))
                arr.insert(tab, at: safeIndex)
            }
            persistSnapshot()
            
        case (.essentials, .spaceRegular(let spaceId)):
            // Essentials -> Regular (specific space): direct transfer without side-effect moves
            removeFromCurrentContainer(tab) // remove from global pinned
            tab.spaceId = spaceId
            var arr = tabsBySpace[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, arr.count))
            arr.insert(tab, at: safeIndex)
            // Reindex
            for (i, t) in arr.enumerated() { t.index = i }
            setTabs(arr, for: spaceId)
            persistSnapshot()
            
        case (.essentials, .spacePinned(let spaceId)):
            // Essentials -> Space Pinned (specific space): direct transfer
            removeFromCurrentContainer(tab) // remove from global pinned
            tab.spaceId = spaceId
            var sp = spacePinnedTabs[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, sp.count))
            sp.insert(tab, at: safeIndex)
            // Reindex
            for (i, t) in sp.enumerated() { t.index = i }
            setSpacePinnedTabs(sp, for: spaceId)
            persistSnapshot()

        // MARK: - Folder Operations

        case (.folder(let fromFolderId), .folder(let toFolderId)):
            guard let spaceId = tab.spaceId else { return }
            var spacePinned = spacePinnedTabs[spaceId] ?? []

            if let currentIndex = spacePinned.firstIndex(where: { $0.id == tab.id }) {
                if currentIndex < spacePinned.count { spacePinned.remove(at: currentIndex) }

                if fromFolderId != toFolderId {
                    tab.folderId = toFolderId
                    tab.isSpacePinned = true
                }

                let safeIndex = max(0, min(operation.toIndex, spacePinned.count))
                spacePinned.insert(tab, at: safeIndex)

                for (idx, pinnedTab) in spacePinned.enumerated() {
                    pinnedTab.index = idx
                }

                setSpacePinnedTabs(spacePinned, for: spaceId)
                persistSnapshot()
            }

        case (.folder(_), .essentials):
            // Move from folder to essentials
            guard browserManager?.currentProfile?.id != nil else { return }
            guard let originalSpaceId = tab.spaceId else { return }

            // Remove from spacePinnedTabs since it's no longer a folder tab
            if var sp = spacePinnedTabs[originalSpaceId] {
                if let index = sp.firstIndex(where: { $0.id == tab.id }) {
                    sp.remove(at: index)
                    // Reindex remaining tabs
                    for (i, t) in sp.enumerated() { t.index = i }
                    setSpacePinnedTabs(sp, for: originalSpaceId)
                }
            }

            tab.folderId = nil
            tab.spaceId = nil
            tab.isSpacePinned = false
            withCurrentProfilePinnedArray { arr in
                let safeIndex = max(0, min(operation.toIndex, arr.count))
                arr.insert(tab, at: safeIndex)
            }
            persistSnapshot()

        case (.folder(_), .spacePinned(let spaceId)):
            let originalSpaceId = tab.spaceId

            if let originalSpaceId,
               var originalSp = spacePinnedTabs[originalSpaceId],
               let currentIndex = originalSp.firstIndex(where: { $0.id == tab.id }) {
                if currentIndex < originalSp.count { originalSp.remove(at: currentIndex) }
                for (idx, existing) in originalSp.enumerated() { existing.index = idx }
                setSpacePinnedTabs(originalSp, for: originalSpaceId)
            }

            tab.folderId = nil
            tab.spaceId = spaceId
            tab.isSpacePinned = true

            var destination = spacePinnedTabs[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, destination.count))
            destination.insert(tab, at: safeIndex)
            for (idx, pinnedTab) in destination.enumerated() { pinnedTab.index = idx }
            setSpacePinnedTabs(destination, for: spaceId)
            persistSnapshot()

        case (.folder(_), .spaceRegular(let spaceId)):
            // Move from folder to regular space
            guard let originalSpaceId = tab.spaceId else { return }

            // Remove from spacePinnedTabs since it's no longer a folder tab
            if var sp = spacePinnedTabs[originalSpaceId] {
                if let index = sp.firstIndex(where: { $0.id == tab.id }) {
                    sp.remove(at: index)
                    // Reindex remaining tabs
                    for (i, t) in sp.enumerated() { t.index = i }
                    setSpacePinnedTabs(sp, for: originalSpaceId)
                }
            }

            tab.folderId = nil
            tab.spaceId = spaceId
            tab.isSpacePinned = false
            var arr = tabsBySpace[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, arr.count))
            arr.insert(tab, at: safeIndex)
            // Reindex
            for (i, t) in arr.enumerated() { t.index = i }
            setTabs(arr, for: spaceId)
            persistSnapshot()

        case (.spaceRegular(let spaceId), .folder(let toFolderId)):
            // Move from regular space to folder
            removeFromCurrentContainer(tab)
            tab.folderId = toFolderId
            tab.spaceId = spaceId
            tab.isSpacePinned = true
            // Add to spacePinnedTabs since folder tabs are now space-pinned
            var sp = spacePinnedTabs[spaceId] ?? []
            let safeIndex = max(0, min(operation.toIndex, sp.count))
            sp.insert(tab, at: safeIndex)
            // Reindex
            for (i, t) in sp.enumerated() { t.index = i }
            setSpacePinnedTabs(sp, for: spaceId)
            persistSnapshot()

        case (.spacePinned(let spaceId), .folder(let toFolderId)):
            var spacePinned = spacePinnedTabs[spaceId] ?? []

            if let currentIndex = spacePinned.firstIndex(where: { $0.id == tab.id }) {
                if currentIndex < spacePinned.count { spacePinned.remove(at: currentIndex) }
            }

            tab.folderId = toFolderId
            tab.spaceId = spaceId
            tab.isSpacePinned = true

            let safeIndex = max(0, min(operation.toIndex, spacePinned.count))
            spacePinned.insert(tab, at: safeIndex)

            for (idx, pinnedTab) in spacePinned.enumerated() {
                pinnedTab.index = idx
            }

            setSpacePinnedTabs(spacePinned, for: spaceId)
            persistSnapshot()

        case (.essentials, .folder(_)):
            // Prevent global pinned (essentials) tabs from being moved to folders
            print("⚠️ Cannot move global pinned tabs to folders")
            return

        case (.none, _), (_, .none):
            print("⚠️ Invalid drag operation: \(operation)")
        }
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
        withCurrentProfilePinnedArray { arr in
            guard let currentIndex = arr.firstIndex(where: { $0.id == tab.id }) else { return }
            guard index != currentIndex else { return }
            if currentIndex < arr.count { arr.remove(at: currentIndex) }
            let safeIndex = max(0, min(index, arr.count))
            arr.insert(tab, at: safeIndex)
        }
        persistSnapshot()
    }
    
    private func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        guard var spacePinned = spacePinnedTabs[spaceId],
              let currentIndex = spacePinned.firstIndex(where: { $0.id == tab.id }) else { return }
        guard index != currentIndex else { return }
        
        if currentIndex < spacePinned.count { spacePinned.remove(at: currentIndex) }
        let clampedIndex = min(max(index, 0), spacePinned.count)
        spacePinned.insert(tab, at: clampedIndex)
        
        // Update indices
        for (i, pinnedTab) in spacePinned.enumerated() {
            pinnedTab.index = i
        }
        
        setSpacePinnedTabs(spacePinned, for: spaceId)
        persistSnapshot()
    }
    
    private func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        guard var regularTabs = tabsBySpace[spaceId],
              let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        guard index != currentIndex else { return }
        
        if currentIndex < regularTabs.count { regularTabs.remove(at: currentIndex) }
        let clampedIndex = min(max(index, 0), regularTabs.count)
        regularTabs.insert(tab, at: clampedIndex)
        
        // Update indices
        for (i, regularTab) in regularTabs.enumerated() {
            regularTab.index = i
        }
        
        setTabs(regularTabs, for: spaceId)
        persistSnapshot()
    }
    
    private func moveTabBetweenSpaces(_ tab: Tab, from fromSpaceId: UUID, to toSpaceId: UUID, asSpacePinned: Bool, toIndex: Int) {
        // Remove from source space
        removeFromCurrentContainer(tab)
        
        // Add to target space
        tab.spaceId = toSpaceId
        if asSpacePinned {
            var spacePinned = spacePinnedTabs[toSpaceId] ?? []
            tab.index = toIndex
            let safeIndex = max(0, min(toIndex, spacePinned.count))
            spacePinned.insert(tab, at: safeIndex)
            // Update indices
            for (i, pinnedTab) in spacePinned.enumerated() {
                pinnedTab.index = i
            }
            setSpacePinnedTabs(spacePinned, for: toSpaceId)
        } else {
            var regularTabs = tabsBySpace[toSpaceId] ?? []
            tab.index = toIndex
            let safeIndex = max(0, min(toIndex, regularTabs.count))
            regularTabs.insert(tab, at: safeIndex)
            // Update indices
            for (i, regularTab) in regularTabs.enumerated() {
                regularTab.index = i
            }
            setTabs(regularTabs, for: toSpaceId)
        }

        persistSnapshot()
    }

    // MARK: - Tab Ordering

    /// Moves a tab to a different space
    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        guard let tab = allTabs().first(where: { $0.id == tabId }),
              let currentSpaceId = tab.spaceId,
              currentSpaceId != targetSpaceId else { return }

        // Move to target space at the end of regular tabs
        let targetTabs = tabsBySpace[targetSpaceId] ?? []
        moveTabBetweenSpaces(tab, from: currentSpaceId, to: targetSpaceId, asSpacePinned: false, toIndex: targetTabs.count)
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
        persistSnapshot()
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
        persistSnapshot()
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
        guard contains(tab) || allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else {
            return
        }
        guard let pid = browserManager?.currentProfile?.id else { return }
        // Already pinned for this profile?
        if (pinnedByProfile[pid] ?? []).contains(where: { $0.id == tab.id }) { return }

        // Remove from its current container (regular or space-pinned)
        removeFromCurrentContainer(tab)

        // CRITICAL: Clear ALL conflicting properties to prevent duplication
        tab.spaceId = nil
        tab.isSpacePinned = false  // Clear space-pinned status
        tab.folderId = nil         // Clear folder reference
        tab.isPinned = true        // CRITICAL: Explicitly set global pin status

        withCurrentProfilePinnedArray { arr in
            // Append to end; index normalized after mutation
            let nextIndex = (arr.map { $0.index }.max() ?? -1) + 1
            tab.index = nextIndex
            arr.append(tab)
        }
        if currentTab?.id == tab.id { currentTab = tab }
        persistSnapshot()
    }

    func unpinTab(_ tab: Tab) {
        // Find and remove from whichever profile bucket contains it
        var moved: Tab? = nil
        for (pid, arr) in pinnedByProfile {
            if let idx = arr.firstIndex(where: { $0.id == tab.id }) {
                var copy = arr
                if idx < copy.count { moved = copy.remove(at: idx) }
                setPinnedTabs(copy, for: pid)
                break
            }
        }
        guard let moved = moved else { return }
        let targetSpaceId = currentSpace?.id ?? spaces.first?.id
        guard let sid = targetSpaceId else {
            print("No space to place unpinned tab")
            return
        }
        moved.isPinned = false
        moved.spaceId = sid
        var arr = tabsBySpace[sid] ?? []
        arr.insert(moved, at: 0)
        setTabs(arr, for: sid)
        print("Unpinned tab: \(moved.name) -> space \(sid)")
        if currentTab?.id == moved.id { currentTab = moved }

        persistSnapshot()
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
        guard contains(tab) else { return }
        guard let space = spaces.first(where: { $0.id == spaceId }) else { return }

        // Remove from current location
        removeFromCurrentContainer(tab)

        // Add to space pinned tabs
        tab.spaceId = spaceId
        tab.isSpacePinned = true   // CRITICAL: Explicitly set space-pinned status
        tab.isPinned = false       // CRITICAL: Clear global pin status
        var spacePinned = spacePinnedTabs[spaceId] ?? []
        let nextIndex = (spacePinned.map { $0.index }.max() ?? -1) + 1
        tab.index = nextIndex
        spacePinned.append(tab)
        setSpacePinnedTabs(spacePinned, for: spaceId)

        print("Pinned tab '\(tab.name)' to space '\(space.name)'")

        persistSnapshot()
    }
    
    func unpinTabFromSpace(_ tab: Tab) {
        guard let spaceId = tab.spaceId,
              var spacePinned = spacePinnedTabs[spaceId],
              let index = spacePinned.firstIndex(where: { $0.id == tab.id }) else { return }

        // Remove from space pinned tabs
        guard index < spacePinned.count else { return }
        let unpinned = spacePinned.remove(at: index)
        setSpacePinnedTabs(spacePinned, for: spaceId)

        // Add to regular tabs in the same space
        var regularTabs = tabsBySpace[spaceId] ?? []
        let nextIndex = (regularTabs.map { $0.index }.max() ?? -1) + 1
        unpinned.index = nextIndex
        regularTabs.append(unpinned)
        setTabs(regularTabs, for: spaceId)

        print("Unpinned tab '\(tab.name)' from space")

        persistSnapshot()
    }

    private func removeFromCurrentContainer(_ tab: Tab) {
        // Remove from global pinned (search across profiles)
        for (pid, arr) in pinnedByProfile {
            if let index = arr.firstIndex(where: { $0.id == tab.id }) {
                var copy = arr
                if index < copy.count { copy.remove(at: index) }
                setPinnedTabs(copy, for: pid)
                return
            }
        }

        // Remove from space pinned
        if let spaceId = tab.spaceId,
           var spacePinned = spacePinnedTabs[spaceId],
           let index = spacePinned.firstIndex(where: { $0.id == tab.id }) {
            if index < spacePinned.count { spacePinned.remove(at: index) }
            setSpacePinnedTabs(spacePinned, for: spaceId)
            return
        }

        // Remove from regular tabs
        if let spaceId = tab.spaceId,
           var regularTabs = tabsBySpace[spaceId],
           let index = regularTabs.firstIndex(where: { $0.id == tab.id }) {
            if index < regularTabs.count { regularTabs.remove(at: index) }
            setTabs(regularTabs, for: spaceId)
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
        t.isSpacePinned = e.isSpacePinned

        // Restore navigation state
        t.canGoBack = e.canGoBack
        t.canGoForward = e.canGoForward

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
                Space(
                    id: $0.id,
                    name: $0.name,
                    icon: $0.icon,
                    gradient: SpaceGradient.decode($0.gradientData),
                    profileId: $0.profileId
                )
            }
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
            } else {
                print("⚠️ [TabManager] No profiles available to assign to spaces")
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
            let normals = sortedTabs.filter { !$0.isPinned && !$0.isSpacePinned && $0.folderId == nil }

            print("📊 Tab loading statistics:")
            print("   - Total sortedTabs: \(sortedTabs.count)")
            print("   - globalPinned: \(globalPinned.count)")
            print("   - spacePinned: \(spacePinned.count)")
            print("   - normals: \(normals.count)")

            print("🔍 Space-pinned tabs being loaded:")
            for e in spacePinned {
                print("   - \(e.name) (id: \(e.id.uuidString.prefix(8))...)")
                print("     spaceId: \(e.spaceId?.uuidString ?? "nil")")
                print("     folderId: \(e.folderId?.uuidString ?? "nil")")
                print("     isPinned: \(e.isPinned)")
                print("     isSpacePinned: \(e.isSpacePinned)")
            }

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
            print("🔄 Processing space-pinned tabs for spacePinnedTabs dictionary:")
            for e in spacePinned {
                print("   Creating runtime tab for: \(e.name)")
                let t = toRuntime(e)
                print("   After toRuntime - \(t.name):")
                print("     - folderId: \(t.folderId?.uuidString ?? "nil")")
                print("     - isSpacePinned: \(t.isSpacePinned)")
                if let sid = e.spaceId {
                    var arr = spacePinnedTabs[sid] ?? []
                    let oldCount = arr.count
                    arr.append(t)
                    setSpacePinnedTabs(arr, for: sid)
                    print("   Added to spacePinnedTabs[\(sid.uuidString.prefix(8))...]: \(oldCount) → \(arr.count) tabs")
                } else {
                    print("   ❌ No spaceId for tab: \(e.name)")
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
            print("📁 Loading \(folderEntities.count) folders:")
            for e in folderEntities {
                print("   - Folder: \(e.name) (spaceId: \(e.spaceId.uuidString.prefix(8))...)")
                let folder = TabFolder(
                    id: e.id,
                    name: e.name,
                    spaceId: e.spaceId,
                    icon: e.icon,
                    color: NSColor(hex: e.color) ?? .controlAccentColor
                )
                folder.isOpen = e.isOpen
                var folders = foldersBySpace[e.spaceId] ?? []
                folders.append(folder)
                setFolders(folders, for: e.spaceId)
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
                self.pinnedTabs
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
                print("🆕 [TabManager] No tabs found, creating default Google tab")
                let defaultTab = createNewTab(url: "https://www.google.com", in: currentSpace)
                self.currentTab = defaultTab
            }

            if let ct = self.currentTab { _ = ct.webView }
            print(
                "Current Space: \(currentSpace?.name ?? "None"), Tab: \(currentTab?.name ?? "None")"
            )

            // Ensure the window background uses the startup space's gradient.
            // Use an immediate set to avoid an initial animation.
            if let bm = self.browserManager, let space = self.currentSpace {
                bm.refreshGradientsForSpace(space, animate: false)
            }
            // If we assigned default profile to legacy pinned tabs, persist to capture migrations
            if __didAssignDefaultProfile { persistSnapshot() }
            
            // Notify that initial data load is complete so window states can be updated
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        } catch {
            print("SwiftData load error: \(error)")
        }
    }

    private var snapshotGeneration: Int = 0

    public nonisolated func persistSnapshot() {
        Task { [weak self] in
            _ = await self?.persistSnapshotAwaitingResult()
        }
    }

    // Returns true if atomic path succeeded; false if fallback was used or stale
    public nonisolated func persistSnapshotAwaitingResult() async -> Bool {
        // Build snapshot and capture a generation on MainActor
        let payload: (PersistenceActor.Snapshot, Int)? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            strong.snapshotGeneration &+= 1
            let gen = strong.snapshotGeneration
            let snap = strong._buildSnapshot()
            return (snap, gen)
        }
        guard let (snapshot, generation) = payload else {
            // In case self was deallocated while switching actors
            return false
        }
        return await persistence.persist(snapshot: snapshot, generation: generation)
    }

    // Build a persistence snapshot from the current in-memory state (MainActor)
    private func _buildSnapshot() -> PersistenceActor.Snapshot {
        // Spaces in order
        var spaceSnapshots: [PersistenceActor.SnapshotSpace] = []
        spaceSnapshots.reserveCapacity(spaces.count)
        for (sIndex, sp) in spaces.enumerated() {
            let ss = PersistenceActor.SnapshotSpace(
                id: sp.id,
                name: sp.name,
                icon: sp.icon,
                index: sIndex,
                gradientData: sp.gradient.encoded,
                activeTabId: sp.activeTabId,
                profileId: sp.profileId
            )
            spaceSnapshots.append(ss)
        }

        // Tabs: global pinned, space pinned, and regular, with indices normalized per container
        var tabSnapshots: [PersistenceActor.SnapshotTab] = []
        // Global pinned (across profiles)
        for (pid, arr) in pinnedByProfile {
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
                    folderId: t.folderId,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward
                ))
            }
        }
        // Per-space collections
        for sp in spaces {
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
                    folderId: t.folderId,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward
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
                    folderId: t.folderId,
                    currentURLString: t.url.absoluteString,
                    canGoBack: t.canGoBack,
                    canGoForward: t.canGoForward
                ))
            }
        }

        // Folders
        var folderSnapshots: [PersistenceActor.SnapshotFolder] = []
        for (spaceId, folders) in foldersBySpace {
            let ordered = folders.sorted { $0.index < $1.index }
            for (i, folder) in ordered.enumerated() {
                folderSnapshots.append(.init(
                    id: folder.id,
                    name: folder.name,
                    icon: folder.icon,
                    color: folder.color.toHexString() ?? "#000000",
                    spaceId: spaceId,
                    isOpen: folder.isOpen,
                    index: i
                ))
            }
        }

        let state = PersistenceActor.SnapshotState(
            currentTabID: currentTab?.id,
            currentSpaceID: currentSpace?.id
        )

        return PersistenceActor.Snapshot(spaces: spaceSnapshots, tabs: tabSnapshots, folders: folderSnapshots, state: state)
    }
}

extension TabManager {
    nonisolated func reattachBrowserManager(_ bm: BrowserManager) {
        Task { @MainActor in
            await _reattachBrowserManager(bm)
        }
    }
    
    private func _reattachBrowserManager(_ bm: BrowserManager) async {
        self.browserManager = bm
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        for t in (self.pinnedTabs + spacePinned + self.tabs) {
            t.browserManager = bm
        }
        // Assign any pinned tabs that were loaded without a profile once currentProfile is known
        if browserManager?.currentProfile?.id != nil, !pendingPinnedWithoutProfile.isEmpty {
            // Set browserManager on those tabs
            for t in pendingPinnedWithoutProfile { t.browserManager = bm }
            withCurrentProfilePinnedArray { arr in
                arr.append(contentsOf: pendingPinnedWithoutProfile)
            }
            pendingPinnedWithoutProfile.removeAll()
            persistSnapshot()
        }
        if let current = self.currentTab {
            let all = self.pinnedTabs + spacePinned + self.tabs
            if let match = all.first(where: { $0.id == current.id }) {
                self.currentTab = match
            }
        }
        if let ct = self.currentTab { _ = ct.webView }
        // Inform the extension controller about existing tabs and the active tab
        if #available(macOS 15.5, *) {
            for t in (self.pinnedTabs + spacePinned + self.tabs) where t.didNotifyOpenToExtensions == false {
                ExtensionManager.shared.notifyTabOpened(t)
                t.didNotifyOpenToExtensions = true
            }
            if let current = self.currentTab {
                ExtensionManager.shared.notifyTabActivated(newTab: current, previous: nil)
            }
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
        guard let fallback = browserManager?.profileManager.profiles.first else { return }
        var didChange = false
        for i in spaces.indices where spaces[i].profileId == deletedProfileId {
            spaces[i].profileId = fallback.id
            if currentSpace?.id == spaces[i].id { currentSpace?.profileId = fallback.id }
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
        (tabsBySpace[space.id] ?? []).sorted { $0.index < $1.index }
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
            persistSnapshot()
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
            print("⚠️ [TabManager] No profiles available for space reconciliation")
            return
        }
        var didAssign = false
        for space in spaces where space.profileId == nil {
            space.profileId = pid
            didAssign = true
        }
        if didAssign { persistSnapshot() }
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

        if didFix { persistSnapshot() }
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
                print("⚠️ [TabManager] Attempted to assign space to unknown profile: \(profileId)")
                return
            }
            spaces[idx].profileId = profileId
            if currentSpace?.id == spaceId {
                currentSpace?.profileId = profileId
            }
            persistSnapshot()
        }
    }

    // MARK: - Tab Closure Undo

    private func trackRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        let now = Date()

        // Check if we should show toast notification (2-hour cooldown)
        let shouldShowToast = shouldShowTabClosureToast(now: now)

        // Update last tab closure time
        lastTabClosureTime = now

        // Create a deep copy of the tab for restoration
        let tabCopy = Tab(
            id: UUID(), // New ID for the restored tab
            url: tab.url,
            name: tab.name,
            favicon: "globe", // Default icon, will be updated when tab loads
            spaceId: spaceId,
            index: tab.index
        )
        tabCopy.browserManager = browserManager

        // Copy additional properties
        tabCopy.isPinned = tab.isPinned
        tabCopy.isSpacePinned = tab.isSpacePinned
        tabCopy.folderId = tab.folderId

        recentlyClosedTabs.append((tab: tabCopy, spaceId: spaceId, timestamp: now))

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

        // Create deep copies of all tabs for restoration
        for (tab, spaceId) in tabs {
            let tabCopy = Tab(
                id: UUID(), // New ID for the restored tab
                url: tab.url,
                name: tab.name,
                favicon: "globe", // Default icon, will be updated when tab loads
                spaceId: spaceId,
                index: tab.index
            )
            tabCopy.browserManager = browserManager

            // Copy additional properties
            tabCopy.isPinned = tab.isPinned
            tabCopy.isSpacePinned = tab.isSpacePinned
            tabCopy.folderId = tab.folderId

            recentlyClosedTabs.append((tab: tabCopy, spaceId: spaceId, timestamp: now))
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

        // Restore the tab
        addTab(mostRecent.tab)
        setActiveTab(mostRecent.tab)

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
            addTab(tabInfo.tab)
        }

        // Set the most recently restored tab as active
        if let lastTab = restoredTabs.last {
            setActiveTab(lastTab)
        }

        // Clear the timer if no more tabs to undo
        if recentlyClosedTabs.isEmpty {
            clearUndoTimer()
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
        // Schedule a persistence update to save the current navigation state
        Task { @MainActor in
            persistSnapshot()
        }
    }

    // MARK: - Bulk Tab Operations

    func closeAllTabsBelow(_ tab: Tab) {
        guard let spaceId = tab.spaceId else { return }
        guard let tabs = tabsBySpace[spaceId] else { return }

        // Find the current tab's index
        guard tabs.firstIndex(where: { $0.id == tab.id }) != nil else { return }

        // Get all tabs below the current tab (higher index values)
        let tabsBelow = tabs.filter { $0.index > tab.index }

        // Return early if no tabs below
        if tabsBelow.isEmpty { return }

        // Prepare tabs for tracking
        let tabsToTrack = tabsBelow.map { (tab: $0, spaceId: spaceId) }

        // Close all tabs below
        for tabToClose in tabsBelow {
            // Close the tab without tracking (we'll do bulk tracking)
            closeTabWithoutTracking(tabToClose.id)
        }

        // Track all closed tabs for undo and show toast
        trackRecentlyClosedTabs(tabsToTrack, count: tabsBelow.count)
    }

    private func closeTabWithoutTracking(_ id: UUID) {
        // This is a copy of removeTab but without the tracking call
        let wasCurrent = (currentTab?.id == id)
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        for space in spaces {
            // Check space-pinned tabs first
            if var spacePinned = spacePinnedTabs[space.id],
                let i = spacePinned.firstIndex(where: { $0.id == id })
            {
                if i < spacePinned.count { removed = spacePinned.remove(at: i) }
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

        // Force unload the tab from compositor before removing
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)

        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabClosed(tab)
        }

        if wasCurrent {
            if tab.spaceId == nil {
                // Tab was global pinned
                let tabs = essentialTabs(for: browserManager?.currentProfile?.id)
                if !tabs.isEmpty {
                    setActiveTab(tabs[0])
                }
            } else {
                // Tab was in a space
                if let spaceTabs = tabsBySpace[tab.spaceId!], !spaceTabs.isEmpty {
                    // Try to select the tab at the same index, or the one before
                    let targetIndex = min(removedIndexInCurrentSpace ?? 0, spaceTabs.count - 1)
                    setActiveTab(spaceTabs[targetIndex])
                }
            }
        }

        persistSnapshot()
    }
}
