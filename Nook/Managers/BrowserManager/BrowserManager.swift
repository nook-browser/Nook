//
//  BrowserManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import Combine
import CoreServices
import OSLog
import Sparkle
import SwiftData
import SwiftUI
import WebKit

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer

    // MARK: - Constants
    nonisolated private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Persistence")
    nonisolated private static let storeFileName = "default.store"
    nonisolated private static let backupPrefix = "default_backup_"
    // Backups now use a directory per snapshot: default_backup_<timestamp>/

    static let schema = Schema([
        SpaceEntity.self,
        ProfileEntity.self,
        TabEntity.self,
        FolderEntity.self,
        TabsStateEntity.self,
        HistoryEntity.self,
        ExtensionEntity.self,
    ])

    // MARK: - URLs
    nonisolated private static var appSupportURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "Nook"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error(
                "Failed to create Application Support directory: \(String(describing: error), privacy: .public)"
            )
        }
        return dir
    }

    nonisolated private static var storeURL: URL {
        appSupportURL.appendingPathComponent(storeFileName, isDirectory: false)
    }
    nonisolated private static var backupsDirectoryURL: URL {
        let dir = appSupportURL.appendingPathComponent("Backups", isDirectory: true)
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log.error(
                "Failed to create Backups directory: \(String(describing: error), privacy: .public)"
            )
        }
        return dir
    }

    // MARK: - Init
    private init() {
        do {
            let config = ModelConfiguration(url: Self.storeURL, cloudKitDatabase: .none)
            container = try ModelContainer(for: Self.schema, configurations: [config])
            Self.log.info("SwiftData container initialized successfully")
        } catch {
            let classification = Self.classifyStoreError(error)
            Self.log.error(
                "SwiftData container initialization failed. Classification=\(String(describing: classification)) error=\(String(describing: error), privacy: .public)"
            )

            switch classification {
            case .schemaMismatch:
                // Attempt a safe reset with optional backup
                var didCreateBackup = false
                do {
                    _ = try Self.createBackup()
                    didCreateBackup = true
                } catch let backupError as PersistenceBackupError {
                    switch backupError {
                    case .storeNotFound:
                        // Treat as recoverable: proceed without a backup
                        Self.log.notice("No existing store to back up. Proceeding with reset.")
                    case .noBackupsFound:
                        // Not expected here but log just in case
                        Self.log.notice("No backups found when attempting to create backup.")
                    }
                } catch {
                    // Never delete a store that could not be copied: the user's tabs live only there.
                    Self.log.fault(
                        "Backup attempt failed: \(String(describing: error), privacy: .public). Not deleting store."
                    )
                    fatalError("SwiftData store could not be opened or backed up; store left untouched: \(error)")
                }

                do {
                    try Self.deleteStore()
                    Self.log.notice(
                        "Deleted existing store (and sidecars) for schema-mismatch recovery")

                    let config = ModelConfiguration(url: Self.storeURL, cloudKitDatabase: .none)
                    container = try ModelContainer(for: Self.schema, configurations: [config])
                    Self.log.notice(
                        "Recreated SwiftData container after schema mismatch using configured URL")
                } catch {
                    // On any failure, attempt to restore backup (if one was made) and abort
                    if didCreateBackup {
                        do {
                            try Self.restoreFromBackup()
                            Self.log.fault(
                                "Restored store from latest backup after failed recovery attempt")
                        } catch {
                            Self.log.fault(
                                "Failed to restore store from backup: \(String(describing: error), privacy: .public)"
                            )
                        }
                    }
                    fatalError(
                        "Failed to recover from schema mismatch. Aborting to protect data integrity: \(error)"
                    )
                }

            case .diskSpace:
                Self.log.fault(
                    "Store initialization failed due to insufficient disk space. Not deleting store."
                )
                fatalError(
                    "SwiftData initialization failed due to insufficient disk space: \(error)")

            case .corruption:
                Self.log.fault(
                    "Store appears corrupted. Not deleting store. Please investigate backups manually."
                )
                fatalError("SwiftData initialization failed due to suspected corruption: \(error)")

            case .other:
                Self.log.error(
                    "Store initialization failed with unclassified error. Not deleting store.")
                fatalError("SwiftData initialization failed: \(error)")
            }
        }
    }

    // MARK: - Error Classification
    private enum StoreErrorType { case schemaMismatch, diskSpace, corruption, other }
    private static func classifyStoreError(_ error: Error) -> StoreErrorType {
        let ns = error as NSError
        let domain = ns.domain
        let code = ns.code
        let desc = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription
        let lower = (desc + " " + domain).lowercased()

        // Disk space: POSIX ENOSPC or clear full-disk wording
        if domain == NSPOSIXErrorDomain && code == 28 { return .diskSpace }
        if lower.contains("no space left") || lower.contains("disk full") { return .diskSpace }

        // Schema mismatch / migration issues
        if lower.contains("migration") || lower.contains("incompatible") || lower.contains("model")
            || lower.contains("version hash") || lower.contains("mapping model")
            || lower.contains("schema")
        {
            return .schemaMismatch
        }

        // Corruption indicators (SQLite/CoreData wording)
        if lower.contains("corrupt") || lower.contains("malformed")
            || lower.contains("database disk image is malformed")
            || lower.contains("file is encrypted or is not a database")
        {
            return .corruption
        }

        return .other
    }

    // MARK: - Backup / Restore
    private enum PersistenceBackupError: Error { case storeNotFound, noBackupsFound }

    // Include SQLite sidecars (-wal/-shm) and back up into a directory
    nonisolated private static func createBackup() throws -> URL {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let source = Self.storeURL
            guard fm.fileExists(atPath: source.path) else {
                Self.log.info(
                    "No existing store found to back up at \(source.path, privacy: .public)")
                throw PersistenceBackupError.storeNotFound
            }

            // Ensure backups root exists
            let backupsRoot = Self.backupsDirectoryURL

            // Create a timestamped backup directory
            let stamp = Self.makeBackupTimestamp()
            let dirName = "\(Self.backupPrefix)\(stamp)"
            let backupDir = backupsRoot.appendingPathComponent(dirName, isDirectory: true)
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

            // Gather store + sidecars
            let candidates = [source] + Self.sidecarURLs(for: source)
            for file in candidates {
                if fm.fileExists(atPath: file.path) {
                    let dest = backupDir.appendingPathComponent(
                        file.lastPathComponent, isDirectory: false)
                    do {
                        try fm.copyItem(at: file, to: dest)
                    } catch {
                        Self.log.error(
                            "Failed to copy \(file.lastPathComponent, privacy: .public) to backup: \(String(describing: error), privacy: .public)"
                        )
                        throw error
                    }
                }
            }

            return backupDir
        }
    }

    // Restore the latest backup directory by copying files back next to the store
    nonisolated private static func restoreFromBackup() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let root = Self.backupsDirectoryURL
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles])
            } catch {
                Self.log.error(
                    "Failed to list backups: \(String(describing: error), privacy: .public)")
                throw error
            }

            let backups = contents.filter { url in
                url.lastPathComponent.hasPrefix(Self.backupPrefix)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            guard !backups.isEmpty else { throw PersistenceBackupError.noBackupsFound }

            // Pick the most recently modified backup directory
            let latest = backups.max { lhs, rhs in
                let l =
                    (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                let r =
                    (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                return l < r
            }!

            // Remove current store files first
            try Self.deleteStore()

            // Copy all files from backup dir back to app support dir
            let backupFiles = try fm.contentsOfDirectory(
                at: latest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in backupFiles {
                let dest = Self.appSupportURL.appendingPathComponent(
                    file.lastPathComponent, isDirectory: false)
                do { try fm.copyItem(at: file, to: dest) } catch {
                    Self.log.error(
                        "Restore copy failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    throw error
                }
            }

            Self.log.notice(
                "Restored store from backup directory: \(latest.lastPathComponent, privacy: .public)"
            )
        }
    }

    // Deletes the base store and known SQLite sidecars if present
    nonisolated private static func deleteStore() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let base = Self.storeURL
            let files = [base] + Self.sidecarURLs(for: base)
            for file in files {
                if fm.fileExists(atPath: file.path) {
                    do { try fm.removeItem(at: file) } catch {
                        Self.log.error(
                            "Failed to remove \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                        throw error
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    nonisolated private static func sidecarURLs(for base: URL) -> [URL] {
        // SQLite commonly uses -wal and -shm sidecars when WAL journaling is active
        // Compose manually to append -wal/-shm
        let walURL = URL(fileURLWithPath: base.path + "-wal")
        let shmURL = URL(fileURLWithPath: base.path + "-shm")
        return [walURL, shmURL]
    }

    nonisolated private static func makeBackupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: Date())
    }

    // Run a throwing closure on a background utility queue and block until it finishes
    nonisolated private static func runBlockingOnUtilityQueue<T>(_ work: @escaping () throws -> T)
        throws -> T
    {
        let group = DispatchGroup()
        group.enter()
        var result: Result<T, Error>!
        DispatchQueue.global(qos: .utility).async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            group.leave()
        }
        group.wait()
        switch result! {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

extension BrowserManager.ProfileSwitchContext {
    fileprivate var shouldProvideFeedback: Bool {
        switch self {
        case .windowActivation:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }

    fileprivate var shouldAnimateTransition: Bool {
        switch self {
        case .windowActivation:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }
}

@MainActor
class BrowserManager: ObservableObject {
    // Legacy global state - kept for backward compatibility during transition
    /// Tracks which pinned tab tile is hovered (for middle-click → reset to pinned URL)
    @Published var hoveredPinnedTabId: UUID? = nil
    @Published var sidebarWidth: CGFloat = 250
    @Published var sidebarContentWidth: CGFloat = 234
    @Published var isSidebarVisible: Bool = true
    @Published var isCommandPaletteVisible: Bool = false
    // Frame of the URL bar within the window; used to anchor the mini palette precisely
    @Published var urlBarFrame: CGRect = .zero
    @Published var shouldShowZoomPopup: Bool = false
    var zoomPopupHideTimer: Timer?
    @Published var currentProfile: Profile?
    // Indicates an in-progress animated profile transition for coordinating UI
    @Published var isTransitioningProfile: Bool = false
    private var transitionEndTask: Task<Void, Never>?
    // Migration state
    @Published var migrationProgress: MigrationProgress?
    @Published var isMigrationInProgress: Bool = false

    // Tab closure undo notification
    @Published var showTabClosureToast: Bool = false
    @Published var tabClosureToastCount: Int = 0
    @Published var updateAvailability: UpdateAvailability?
    @Published var isExtensionPopupActive: Bool = false

    /// Track tabs currently being synced to prevent recursive sync calls
    private var isSyncingTab: Set<UUID> = []

    /// Reference to the app delegate for Sparkle integration
    weak var appDelegate: AppDelegate?

    var modelContext: ModelContext
    /// The tab model: tree, device state, window selection and live pages.
    let tabs: TabsController
    var profileManager: ProfileManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    var authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var cookieManager: CookieManager
    var cacheManager: CacheManager
    var extensionManager: ExtensionManager?
    var compositorManager: TabCompositorManager
    var splitManager: SplitViewManager
    var gradientColorManager: GradientColorManager
    var contentBlockerManager: ContentBlockerManager
    var sponsorBlockManager: SponsorBlockManager
    var findManager: FindManager
    var importManager: ImportManager
    var zoomManager = ZoomManager()
    var keyboardShortcutManager: KeyboardShortcutManager?
    weak var mcpManager: MCPManager?
    weak var tabOrganizerManager: TabOrganizerManager?
    weak var nookSettings: NookSettingsService?
    weak var aiService: AIService?
    weak var aiConfigService: AIConfigService?

    var siteRoutingManager = SiteRoutingManager()
    var externalMiniWindowManager = ExternalMiniWindowManager()
    @Published var peekManager = PeekManager()

    // TEMPORARY: Will be removed when cross-window coordination is eliminated
    weak var webViewCoordinator: WebViewCoordinator?
    weak var windowRegistry: WindowRegistry? {
        didSet {
            // Update PeekManager's windowRegistry reference when this changes
            peekManager.windowRegistry = windowRegistry
        }
    }

    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    var isSwitchingProfile: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    private func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        guard let targetProfileId = windowState.profileID else { return }
        guard !isSwitchingProfile else { return }
        guard currentProfile?.id != targetProfileId else { return }
        guard let targetProfile = profileManager.profiles.first(where: { $0.id == targetProfileId })
        else { return }
        Task { [weak self] in
            await self?.switchToProfile(targetProfile, context: context, in: windowState)
        }
    }


    init() {
        // Phase 1: initialize all stored properties
        self.modelContext = Persistence.shared.container.mainContext
        self.extensionManager = ExtensionManager.shared
        self.profileManager = ProfileManager(context: modelContext)
        // Ensure at least one profile exists and set current immediately for manager initialization
        self.profileManager.ensureDefaultProfile()
        let initialProfile = self.profileManager.profiles.first
        self.currentProfile = initialProfile
        self.tabs = TabsController(profileManager: self.profileManager)

        // settingsManager will be injected from NookApp
        self.dialogManager = DialogManager()
        self.downloadManager = DownloadManager.shared
        self.authenticationManager = AuthenticationManager()
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(context: modelContext, profileId: initialProfile?.id)
        self.cookieManager = CookieManager(dataStore: initialProfile?.dataStore)
        self.cacheManager = CacheManager(dataStore: initialProfile?.dataStore)
        self.compositorManager = TabCompositorManager()
        self.splitManager = SplitViewManager()
        self.gradientColorManager = GradientColorManager()
        self.contentBlockerManager = ContentBlockerManager()
        self.sponsorBlockManager = SponsorBlockManager()
        self.findManager = FindManager()
        self.importManager = ImportManager()

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.splitManager.browserManager = self
        self.splitManager.windowRegistry = self.windowRegistry
        // Note: settingsManager will be injected later, so we skip initialization here
        self.tabs.browserManager = self
        if let mgr = self.extensionManager {
            // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
            mgr.attach(browserManager: self)
            
            // Bind popup active state
            mgr.$isPopupActive
                .receive(on: RunLoop.main)
                .assign(to: &$isExtensionPopupActive)
        }
        self.gradientColorManager.setImmediate(.default)
        self.contentBlockerManager.attach(browserManager: self)
        self.sponsorBlockManager.browserManager = self
        // Note: tracking protection will be configured after settingsManager injection

        self.externalMiniWindowManager.attach(browserManager: self)
        self.peekManager.attach(browserManager: self)
        self.authenticationManager.attach(browserManager: self)
        // Migrate legacy history entries (with nil profile) to default profile to avoid cross-profile leakage
        self.migrateUnassignedDataToDefaultProfile()
        loadSidebarSettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabManagementModeChange),
            name: .tabManagementModeChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: .blockCrossSiteTrackingChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let enabled = note.userInfo?["enabled"] as? Bool else { return }
            Task { @MainActor [weak self] in
                self?.contentBlockerManager.setEnabled(enabled)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .adBlockerEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let enabled = note.userInfo?["enabled"] as? Bool else { return }
            Task { @MainActor [weak self] in
                self?.contentBlockerManager.setEnabled(enabled)
            }
        }

    }

    // MARK: - Startup Loading

    private var startupWaitedForContentBlocker = false
    private var startupWarmTasks: [UUID: Task<Void, Never>] = [:]

    /// Loads a newly registered window's selected page. With "Last Tab, Favorites & Space" the
    /// space's other tabs-section pages then warm one at a time; pinned tabs and favorites load
    /// when selected.
    private func applyStartupLoadMode(for windowState: BrowserWindowState) {
        // Content blocking should be active before the first navigation, otherwise the startup
        // page loads without scriptlets/cosmetics. Warm activation is ~0.3s (cache hit); a cold
        // compile after a list change is several seconds, so the wait is capped at 2s.
        if !startupWaitedForContentBlocker, !contentBlockerManager.isEnabled,
           let activation = contentBlockerManager.activationTask {
            startupWaitedForContentBlocker = true
            Task { @MainActor [weak self, weak windowState] in
                let interval = BrowserPerformance.signposter.beginInterval("StartupBlockerWait")
                _ = await TaskDeadline.wait(for: activation, timeout: .seconds(2))
                BrowserPerformance.signposter.endInterval("StartupBlockerWait", interval)
                guard let self, let windowState else { return }
                self.applyStartupLoadMode(for: windowState)
            }
            return
        }

        let selected = windowState.selectedItemID
        if let selected {
            tabs.select(selected, in: windowState)
        } else {
            windowState.refreshCompositor()
        }

        guard nookSettings?.startupLoadMode == .favoritesAndSpace, let spaceID = windowState.spaceID else { return }
        let warmIDs = tabs.rows(space: spaceID)
            .filter { $0.section == .tabs && !$0.item.isFolder && $0.item.id != selected }
            .map(\.item.id)
        startupWarmTasks[windowState.id]?.cancel()
        startupWarmTasks[windowState.id] = Task { @MainActor [weak self, weak windowState] in
            defer { if let windowState { self?.startupWarmTasks[windowState.id] = nil } }
            // Wait for the visible page before competing for WebKit and network resources.
            if let view = selected.flatMap({ self?.tabs.session(for: $0)?.webView }),
               !(await Self.waitForStartupNavigation(view)) { return }
            for id in warmIDs {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled, let self, let windowState,
                      self.windowRegistry?.windows[windowState.id] != nil,
                      self.compositorManager.allowsBackgroundWarming,
                      self.tabs.item(id) != nil,
                      let session = self.tabs.ensureSession(for: id) else { return }
                guard session.isUnloaded else { continue }
                self.compositorManager.load(session)
                if let view = session.webView,
                   !(await Self.waitForStartupNavigation(view)) { return }
            }
        }
    }

    /// Abort speculative warming after a slow page; other tabs remain available on demand.
    private static func waitForStartupNavigation(_ webView: WKWebView) async -> Bool {
        let completion = Task { @MainActor in
            for await loading in webView.publisher(for: \.isLoading, options: [.initial, .new]).values {
                if !loading || Task.isCancelled { return }
            }
        }
        let finished = await TaskDeadline.wait(for: completion, timeout: .seconds(10))
        completion.cancel()
        return finished
    }

    // MARK: - Profile Switching
    struct ProfileSwitchToast: Equatable {
        let fromProfile: Profile?
        let toProfile: Profile
        let timestamp: Date
    }

    enum ProfileSwitchContext {
        case userInitiated
        case spaceChange
        case windowActivation
        case recovery
    }

    actor ProfileOps { func run(_ body: @MainActor () async -> Void) async { await body() } }
    private let profileOps = ProfileOps()

    func switchToProfile(
        _ profile: Profile, context: ProfileSwitchContext = .userInitiated,
        in windowState: BrowserWindowState? = nil
    ) async {
        await profileOps.run { [weak self] in
            guard let self else { return }
            if self.isSwitchingProfile {
                #if DEBUG
                print("⏳ [BrowserManager] Ignoring concurrent profile switch request")
                #endif
                return
            }
            self.isSwitchingProfile = true
            defer { self.isSwitchingProfile = false }

            let previousProfile = self.currentProfile
            #if DEBUG
            print(
                "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")"
            )
            #endif
            let animateTransition = context.shouldAnimateTransition

            let performUpdates = {
                if animateTransition {
                    self.isTransitioningProfile = true
                } else {
                    self.isTransitioningProfile = false
                }
                self.currentProfile = profile
                // Switch data stores for cookie/cache
                self.cookieManager.switchDataStore(profile.dataStore, profileId: profile.id)
                self.cacheManager.switchDataStore(profile.dataStore, profileId: profile.id)
                // Update history filtering
                self.historyManager.switchProfile(profile.id)
                // A window's profile follows its space: an explicit switch shows that profile's first space.
                if context == .userInitiated || context == .recovery,
                   let window = windowState ?? self.windowRegistry?.activeWindow, !window.isIncognito,
                   window.profileID != profile.id,
                   let space = self.tabs.spaces(inProfile: profile.id).first {
                    self.tabs.setSpace(space.id, in: window)
                }
            }

            if animateTransition {
                withAnimation(.easeInOut(duration: 0.35)) {
                    performUpdates()
                }
            } else {
                performUpdates()
            }

            if context.shouldProvideFeedback {
                self.showProfileSwitchToast(
                    from: previousProfile, to: profile, in: windowState ?? self.windowRegistry?.activeWindow)
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .generic, performanceTime: .drawCompleted)
            }

            if animateTransition {
                transitionEndTask?.cancel()
                transitionEndTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.35))
                    guard !Task.isCancelled else { return }
                    self?.isTransitioningProfile = false
                }
            }
        }
    }

    func updateSidebarWidth(_ width: CGFloat) {
        if let activeWindow = windowRegistry?.activeWindow {
            updateSidebarWidth(width, for: activeWindow)
            return
        }
        sidebarWidth = width
        savedSidebarWidth = width
        sidebarContentWidth = max(width - 16, 0)
    }

    func updateSidebarWidth(_ width: CGFloat, for windowState: BrowserWindowState) {
        windowState.sidebarWidth = width
        windowState.savedSidebarWidth = width
        windowState.sidebarContentWidth = max(width - 16, 0)
        if windowRegistry?.activeWindow?.id == windowState.id {
            sidebarWidth = width
            savedSidebarWidth = width
            sidebarContentWidth = max(width - 16, 0)
        }
    }

    func saveSidebarWidthToDefaults() {
        saveSidebarSettings()
    }

    func toggleSidebar() {
        if let windowState = windowRegistry?.activeWindow {
            toggleSidebar(for: windowState)
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                isSidebarVisible.toggle()
                // Width stays the same whether visible or hidden
            }
            saveSidebarSettings()
        }
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        withAnimation(.easeInOut(duration: 0.1)) {
            windowState.isSidebarVisible.toggle()
            // Width stays the same whether visible or hidden
        }
        if windowRegistry?.activeWindow?.id == windowState.id {
            isSidebarVisible = windowState.isSidebarVisible
            sidebarWidth = windowState.sidebarWidth
            savedSidebarWidth = windowState.savedSidebarWidth
            sidebarContentWidth = windowState.sidebarContentWidth
        }
        saveSidebarSettings()
    }

    func toggleAISidebar() {
        guard nookSettings?.showAIAssistant == true else { return }
        if let windowState = windowRegistry?.activeWindow {
            toggleAISidebar(for: windowState)
        }
    }

    func toggleAISidebar(for windowState: BrowserWindowState) {
        guard nookSettings?.showAIAssistant == true else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            if windowState.isSidebarAIChatVisible {
                windowState.isSidebarAIChatVisible = false
            } else {
                windowState.isSidebarAIChatVisible = true
                windowState.isSidebarMenuVisible = false
            }
        }
    }

    // MARK: - Extension Library Panel

    /// Toggles the extension library panel for the active window via keyboard shortcut.
    func toggleExtensionLibrary() {
        guard let windowState = windowRegistry?.activeWindow,
              let window = windowState.window,
              let settings = nookSettings else { return }

        // Lazily create the panel controller if needed
        if windowState.extensionLibraryPanelController == nil {
            windowState.extensionLibraryPanelController = ExtensionLibraryPanelController()
        }
        guard let panelController = windowState.extensionLibraryPanelController else { return }

        let willShow = !panelController.isVisible
        windowState.isExtensionLibraryVisible = willShow

        panelController.toggle(
            anchorFrame: windowState.urlBarFrame,
            in: window,
            browserManager: self,
            windowState: windowState,
            settings: settings
        )
    }

    // MARK: - Sidebar width access for overlays
    /// Returns the last saved sidebar width (used when sidebar is collapsed to size hover overlay)
    func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        if let state = windowState {
            return state.savedSidebarWidth
        }
        if let active = windowRegistry?.activeWindow {
            return active.savedSidebarWidth
        }
        return savedSidebarWidth
    }


    func toggleTopBarAddressView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            nookSettings?.topBarAddressView.toggle()
        }
    }

    func showFindBar() {
        if findManager.isFindBarVisible {
            findManager.hideFindBar()
        } else {
            findManager.showFindBar(for: tabs.activeWindowSession)
        }
    }

    // MARK: - Dialog Methods

    func showQuitDialog() {
        if self.nookSettings?.askBeforeQuit == true {
            dialogManager.showQuitDialog(
                onAlwaysQuit: {
                    self.nookSettings?.askBeforeQuit = false
                    self.quitApplication()
                },
                onQuit: {
                    self.quitApplication()
                }
            )
        } else {
            NSApplication.shared.terminate(nil)
        }

    }

    func showDialog<Content: View>(_ dialog: Content) {
        dialogManager.showDialog(dialog)
    }

    func showDialog<Content: View>(@ViewBuilder builder: () -> Content) {
        dialogManager.showDialog(builder: builder)
    }

    // MARK: - Space Settings

    /// Opens Space Settings for the active window's space, or a notice when there is none.
    func showSpaceSettings() {
        guard let spaceID = windowRegistry?.activeWindow?.spaceID, tabs.space(spaceID) != nil else {
            dialogManager.showDialog {
                StandardDialog(
                    header: {
                        DialogHeader(
                            icon: "square.grid.2x2",
                            title: "No Space Available",
                            subtitle: "Create a space to change its settings."
                        )
                    },
                    content: { Color.clear.frame(height: 0) },
                    footer: {
                        DialogFooter(rightButtons: [
                            DialogButton(text: "OK", variant: .primary) { [weak self] in
                                self?.closeDialog()
                            }
                        ])
                    }
                )
            }
            return
        }
        SpaceEditDialog.present(spaceID: spaceID, tabs: tabs, dialogManager: dialogManager)
    }

    func closeDialog() {
        dialogManager.closeDialog()
    }

    private func quitApplication() {
        // AppDelegate saves the final tab snapshot. Do not close tabs first: a closed tab is
        // removed from the snapshot and therefore deleted from the store.
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private Methods
    private func loadSidebarSettings() {
        let savedWidth = userDefaults.double(forKey: "sidebarWidth")
        let savedVisibility = userDefaults.bool(forKey: "sidebarVisible")

        // Check if this is first launch (no saved width)
        let isFirstLaunch = savedWidth == 0

        if savedWidth > 0 {
            savedSidebarWidth = savedWidth
            sidebarWidth = savedVisibility ? savedWidth : 0
        } else {
            // First launch: ensure sidebar is visible with default width
            savedSidebarWidth = 250
            sidebarWidth = 250
        }
        sidebarContentWidth = max(sidebarWidth - 16, 0)

        // On first launch, default to visible sidebar
        isSidebarVisible = isFirstLaunch ? true : savedVisibility
    }

    private func saveSidebarSettings() {
        userDefaults.set(savedSidebarWidth, forKey: "sidebarWidth")
        userDefaults.set(isSidebarVisible, forKey: "sidebarVisible")
    }

    @objc private func handleTabManagementModeChange(_ notification: Notification) {
        if let modeRaw = notification.userInfo?["mode"] as? String,
           let mode = TabManagementMode(rawValue: modeRaw) {
            compositorManager.setMode(mode)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Privacy-Compliant Management

    func clearThirdPartyCookies() {
        Task {
            await cookieManager.deleteThirdPartyCookies()
        }
    }

    func clearHighRiskCookies() {
        Task {
            await cookieManager.deleteHighRiskCookies()
        }
    }

    func performPrivacyCleanup() {
        Task {
            await cookieManager.performPrivacyCleanup()
            await cacheManager.performPrivacyCompliantCleanup()
        }
    }

    // Profile-specific cleanup helpers
    func clearCurrentProfileCookies() {
        guard let pid = currentProfile?.id else { return }
        #if DEBUG
        print("🧹 [BrowserManager] Clearing cookies for current profile: \(pid.uuidString)")
        #endif
        Task { await cookieManager.deleteAllCookies() }
    }

    func clearCurrentProfileCache() {
        guard currentProfile?.id != nil else { return }
        #if DEBUG
        print("🧹 [BrowserManager] Clearing cache for current profile")
        #endif
        Task { await cacheManager.clearAllCache() }
    }

    func clearAllProfilesCookies() {
        #if DEBUG
        print("🧹 [BrowserManager] Clearing cookies for ALL profiles (sequential, isolated)")
        #endif
        let profiles = profileManager.profiles
        Task { @MainActor in
            for profile in profiles {
                let cm = CookieManager(dataStore: profile.dataStore)
                #if DEBUG
                print(
                    "   → Clearing cookies for profile=\(profile.id.uuidString) [\(profile.name)]")
                #endif
                await cm.deleteAllCookies()
            }
        }
    }

    func performPrivacyCleanupAllProfiles() {
        #if DEBUG
        print(
            "🧹 [BrowserManager] Performing privacy cleanup across ALL profiles (sequential, isolated)"
        )
        #endif
        let profiles = profileManager.profiles
        Task { @MainActor in
            for profile in profiles {
                #if DEBUG
                print("   → Cleaning profile=\(profile.id.uuidString) [\(profile.name)]")
                #endif
                let cm = CookieManager(dataStore: profile.dataStore)
                let cam = CacheManager(dataStore: profile.dataStore)
                await cm.performPrivacyCleanup()
                await cam.performPrivacyCompliantCleanup()
            }
        }
    }

    // MARK: - Migration Helpers
    /// Assign a default profile to any history entries without a profileId for backward compatibility
    func migrateUnassignedDataToDefaultProfile() {
        guard let defaultProfileId = profileManager.profiles.first?.id else { return }
        assignDefaultProfileToExistingData(defaultProfileId)
    }

    func assignDefaultProfileToExistingData(_ profileId: UUID) {
        do {
            let predicate = #Predicate<HistoryEntity> { $0.profileId == nil }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            var updated = 0
            for entity in entities {
                entity.profileId = profileId
                updated += 1
            }
            try modelContext.save()
            #if DEBUG
            print(
                "🔧 [BrowserManager] Assigned default profile to \(updated) legacy history entries")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [BrowserManager] Failed to assign default profile to existing data: \(error)")
            #endif
        }
    }

    func clearPersonalDataCache() {
        Task {
            await cacheManager.clearPersonalDataCache()
        }
    }

    func clearFaviconCache() {
        cacheManager.clearFaviconCache()
    }

    // MARK: - Extension Management

    func showExtensionInstallDialog() {
        extensionManager?.showExtensionInstallDialog()
    }

    func enableExtension(_ extensionId: String) {
        extensionManager?.enableExtension(extensionId)
    }

    func disableExtension(_ extensionId: String) {
        extensionManager?.disableExtension(extensionId)
    }

    func uninstallExtension(_ extensionId: String) {
        extensionManager?.uninstallExtension(extensionId)
    }

    // MARK: - Profile Switch Toast
    func showProfileSwitchToast(from: Profile?, to: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        let toast = ProfileSwitchToast(fromProfile: from, toProfile: to, timestamp: Date())
        let windowId = targetWindow.id
        targetWindow.profileSwitchToast = toast
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            targetWindow.isShowingProfileSwitchToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.hideProfileSwitchToast(forWindowId: windowId)
        }
    }

    func hideProfileSwitchToast(for windowState: BrowserWindowState? = nil) {
        guard let window = windowState ?? windowRegistry?.activeWindow else { return }
        hideProfileSwitchToast(forWindowId: window.id)
    }

    private func hideProfileSwitchToast(forWindowId windowId: UUID) {
        guard
            let window = windowRegistry?.windows[windowId]
                ?? (windowRegistry?.activeWindow?.id == windowId ? windowRegistry?.activeWindow : nil)
        else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            window.isShowingProfileSwitchToast = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
            window?.profileSwitchToast = nil
        }
    }

    // MARK: - Migration Utilities
    struct MigrationProgress {
        var currentStep: String
        var progress: Double
        var totalSteps: Int
        var currentStepIndex: Int
    }

    struct LegacyDataSummary {
        var hasCookies: Bool
        var hasCache: Bool
        var hasLocalStorage: Bool
        var cookieCount: Int
        var recordCount: Int
        var estimatedDescription: String
        var hasAny: Bool { hasCookies || hasCache || hasLocalStorage }
    }

    func detectLegacySharedData() async -> LegacyDataSummary {
        let defaultStore = WKWebsiteDataStore.default()
        var cookieCount = 0
        var recordCount = 0
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            defaultStore.httpCookieStore.getAllCookies { cookies in
                cookieCount = cookies.count
                cont.resume()
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
                recordCount = records.count
                cont.resume()
            }
        }

        let hasCookies = cookieCount > 0
        let hasCache = recordCount > 0
        // We cannot easily distinguish local storage vs caches without deeper inspection; approximate
        let hasLocalStorage = hasCache
        let estimated = "Cookies: \(cookieCount), Records: \(recordCount)"
        return LegacyDataSummary(
            hasCookies: hasCookies,
            hasCache: hasCache,
            hasLocalStorage: hasLocalStorage,
            cookieCount: cookieCount,
            recordCount: recordCount,
            estimatedDescription: estimated
        )
    }

    func migrateCookiesToCurrentProfile() async throws {
        guard let targetStore = currentProfile?.dataStore else { return }
        isMigrationInProgress = true
        migrationProgress = MigrationProgress(
            currentStep: "Copying cookies…", progress: 0.0, totalSteps: 3, currentStepIndex: 1)
        let defaultStore = WKWebsiteDataStore.default()

        let cookies = await withCheckedContinuation {
            (cont: CheckedContinuation<[HTTPCookie], Never>) in
            defaultStore.httpCookieStore.getAllCookies { cookies in cont.resume(returning: cookies)
            }
        }
        let total = max(1, cookies.count)
        var copied = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask { @MainActor in
                    if Task.isCancelled { return }
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        targetStore.httpCookieStore.setCookie(cookie) {
                            cont.resume()
                        }
                    }
                    copied += 1
                    self.migrationProgress?.progress = Double(copied) / Double(total) * (1.0 / 3.0)
                }
            }
            try await group.waitForAll()
            if Task.isCancelled { throw CancellationError() }
        }
    }

    func migrateCacheToCurrentProfile() async throws {
        // There is no public API to copy cached site data across stores.
        // We track progress for UX and attempt to prime the target store by visiting entries post-migration if needed.
        migrationProgress?.currentStep = "Migrating site data…"
        migrationProgress?.currentStepIndex = 2
        // Simulate progress for UX purposes
        for i in 1...10 {  // 10 ticks
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 80_000_000)  // 80ms per tick
            migrationProgress?.progress = (1.0 / 3.0) + Double(i) / 10.0 * (1.0 / 3.0)
        }
    }

    func clearSharedDataAfterMigration() async {
        migrationProgress?.currentStep = "Clearing shared data…"
        migrationProgress?.currentStepIndex = 3
        let allTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: .distantPast)
            {
                cont.resume()
            }
        }
        migrationProgress?.progress = 1.0
        isMigrationInProgress = false
    }

    func createFreshProfileStores() async {
        // Ensure each profile's dataStore is initialized and empty if requested
        for p in profileManager.profiles {
            // No-op if already created; optionally clear
            await p.clearAllData()
        }
    }

    @Published var migrationTask: Task<Void, Never>? = nil

    func startMigrationToCurrentProfile() {
        guard isMigrationInProgress == false else { return }
        isMigrationInProgress = true
        migrationProgress = MigrationProgress(
            currentStep: "Preparing…", progress: 0.0, totalSteps: 3, currentStepIndex: 0)
        migrationTask = Task { @MainActor in
            do {
                if Task.isCancelled {
                    self.resetMigrationState()
                    return
                }
                try await migrateCookiesToCurrentProfile()
                if Task.isCancelled {
                    self.resetMigrationState()
                    return
                }
                try await migrateCacheToCurrentProfile()
                if Task.isCancelled {
                    self.resetMigrationState()
                    return
                }
                await clearSharedDataAfterMigration()
                self.dialogManager.showDialog {
                    StandardDialog(
                        header: {
                            DialogHeader(
                                icon: "checkmark.seal",
                                title: "Migration Complete",
                                subtitle: currentProfile?.name ?? ""
                            )
                        },
                        content: {
                            Text("Your shared data has been migrated to the current profile.")
                                .font(.body)
                        },
                        footer: {
                            DialogFooter(rightButtons: [
                                DialogButton(text: "OK", variant: .primary) { [weak self] in
                                    self?.dialogManager.closeDialog()
                                }
                            ])
                        }
                    )
                }
            } catch is CancellationError {
                self.resetMigrationState()
            } catch {
                self.resetMigrationState()
                self.recoverFromProfileError(error, profile: self.currentProfile)
            }
            self.migrationTask = nil
        }
    }

    private func resetMigrationState() {
        self.isMigrationInProgress = false
        self.migrationProgress = nil
    }

    // MARK: - Validation & Recovery
    func validateProfileIntegrity() {
        // Ensure currentProfile is still valid
        if let cp = currentProfile, profileManager.profiles.first(where: { $0.id == cp.id }) == nil
        {
            #if DEBUG
            print("⚠️ [BrowserManager] Current profile invalid; falling back to first available")
            #endif
            currentProfile = profileManager.profiles.first
        }
    }

    func recoverFromProfileError(_ error: Error, profile: Profile?) {
        #if DEBUG
        print("❗️[BrowserManager] Profile operation failed: \(error)")
        #endif
        // Fallback to default/first profile
        if let first = profileManager.profiles.first {
            Task { await switchToProfile(first, context: .recovery) }
        }
        // Show dialog
        dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "exclamationmark.triangle",
                        title: "Profile Error",
                        subtitle: profile?.name ?? ""
                    )
                },
                content: {
                    Text(
                        "An error occurred while performing a profile operation. Your session has been switched to a safe profile."
                    )
                    .font(.body)
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "OK", variant: .primary) { [weak self] in
                            self?.dialogManager.closeDialog()
                        }
                    ])
                }
            )
        }
    }

    // MARK: - Profile Deletion Coordinator

    /// The one profile delete path: the current profile moves to `heir`, the profile's data is
    /// cleared, TabsController moves its spaces and favorites to `heir` and removes the app profile.
    func deleteProfile(_ profile: Profile, heir: Profile) {
        // Avoid deleting the last profile
        guard profileManager.profiles.count > 1 else {
            dialogManager.showDialog {
                StandardDialog(
                    header: {
                        DialogHeader(
                            icon: "exclamationmark.triangle",
                            title: "Cannot Delete Last Profile",
                            subtitle: profile.name
                        )
                    },
                    content: {
                        Text("At least one profile must remain.")
                            .font(.body)
                    },
                    footer: {
                        DialogFooter(rightButtons: [
                            DialogButton(text: "OK", variant: .primary) { [weak self] in
                                self?.dialogManager.closeDialog()
                            }
                        ])
                    }
                )
            }
            return
        }
        Task { @MainActor in
            if self.currentProfile?.id == profile.id {
                await self.switchToProfile(heir)
            }
            await profile.clearAllData()
            let ok = self.tabs.deleteProfile(profile.id, heir: heir.id)
            if !ok {
                self.dialogManager.showDialog {
                    StandardDialog(
                        header: {
                            DialogHeader(
                                icon: "exclamationmark.triangle",
                                title: "Couldn't Delete Profile",
                                subtitle: profile.name
                            )
                        },
                        content: {
                            Text("An error occurred while saving changes. Please try again.")
                                .font(.body)
                        },
                        footer: {
                            DialogFooter(rightButtons: [
                                DialogButton(text: "OK", variant: .primary) { [weak self] in
                                    self?.dialogManager.closeDialog()
                                }
                            ])
                        }
                    )
                }
            }
        }
    }

    /// Presents an external URL in a mini window popup (for URL events)
    func presentExternalURL(_ url: URL) {
        externalMiniWindowManager.present(url: url)
    }

    // MARK: - Window State Management

    /// A window registered: sidebar chrome from the active globals, then its space, selection and
    /// split from TabsController (an unclaimed saved window record when there is one), then its
    /// selected page. The first regular window also reopens the other saved windows.
    func setupWindowState(_ windowState: BrowserWindowState) {
        windowState.sidebarWidth = sidebarWidth
        windowState.sidebarContentWidth = max(sidebarWidth - 16, 0)
        windowState.isSidebarVisible = isSidebarVisible
        windowState.savedSidebarWidth = savedSidebarWidth
        windowState.isCommandPaletteVisible = false
        // NSWindow reference is set by WindowFocusBridge.attach in ContentView
        windowState.urlBarFrame = urlBarFrame

        tabs.attach(window: windowState)
        guard !windowState.isIncognito else { return }
        if windowRegistry?.activeWindow == nil || windowRegistry?.activeWindow?.id == windowState.id {
            adoptProfileIfNeeded(for: windowState, context: .windowActivation)
        }
        applyStartupLoadMode(for: windowState)
        restoreSavedWindows()
    }

    /// Set the active window state (called when a window gains focus)
    /// NOTE: This is called BY the WindowRegistry callback, so we don't call setActive again
    func setActiveWindowState(_ windowState: BrowserWindowState) {
        // DO NOT call windowRegistry?.setActive(windowState) here - that would cause infinite recursion!
        // This method is called FROM the onActiveWindowChange callback
        sidebarWidth = windowState.sidebarWidth
        savedSidebarWidth = windowState.savedSidebarWidth
        sidebarContentWidth = windowState.sidebarContentWidth
        isSidebarVisible = windowState.isSidebarVisible
        urlBarFrame = windowState.urlBarFrame
        // Regular windows get their space accent from WindowView; private windows keep their own look.
        if windowState.isIncognito {
            gradientColorManager.setImmediate(.incognito)
        }
        isCommandPaletteVisible = windowState.isCommandPaletteVisible
        adoptProfileIfNeeded(for: windowState, context: .windowActivation)
    }

    /// A window's space moved it to another profile. The active window adopts that profile
    /// (data stores, history, cookies), as the old space switch did.
    func windowProfileChanged(_ windowState: BrowserWindowState) {
        guard !windowState.isIncognito, windowRegistry?.activeWindow?.id == windowState.id else { return }
        adoptProfileIfNeeded(for: windowState, context: .spaceChange)
    }

    // MARK: - Window-Aware Tab Operations

    /// DEPRECATED: Use WebViewCoordinator.getWebView() directly via environment
    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewCoordinator?.getWebView(for: tabId, in: windowId)
    }

    func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {
        webViewCoordinator?.syncTab(tabId, to: url)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {
        webViewCoordinator?.setMuteState(muted, for: tabId, excludingWindow: originatingWindowId)
    }

    /// Opens a regular window. `frame` places a window restored from DeviceState.windows.
    func createNewWindow(frame: NSRect? = nil) {
        guard let windowRegistry = windowRegistry,
              let webViewCoordinator = webViewCoordinator else {
            #if DEBUG
            print("⚠️ [BrowserManager] Cannot create window - missing WindowRegistry or WebViewCoordinator")
            #endif
            return
        }

        let newWindow = makeBrowserNSWindow(title: "Nook")
        let contentView = windowContent(ContentView(), windowRegistry: windowRegistry, webViewCoordinator: webViewCoordinator)
        newWindow.contentView = NSHostingView(rootView: contentView)
        if let frame {
            newWindow.setFrame(frame, display: false)
        } else {
            newWindow.center()
        }
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func windowContent(_ content: ContentView, windowRegistry: WindowRegistry, webViewCoordinator: WebViewCoordinator) -> some View {
        content
            .background(BackgroundWindowModifier())
            .ignoresSafeArea(.all)
            .environmentObject(self)
            .environment(tabs)
            .environment(windowRegistry)
            .environment(webViewCoordinator)
            .environmentObject(gradientColorManager)
            .environment(\.nookSettings, nookSettings ?? NookSettingsService())
            .environment(aiService)
            .environment(aiConfigService)
            .environment(keyboardShortcutManager)
            .environment(mcpManager)
            .environment(tabOrganizerManager)
    }

    /// A browser window created in code, styled like the SwiftUI main window up front so the
    /// first frame already has the hidden, transparent title bar.
    private func makeBrowserNSWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // ARC owns this window. AppKit's default release on close over-releases it and crashes
        // in the next autorelease pool drain.
        window.isReleasedWhenClosed = false
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 470, height: 382)
        window.contentMinSize = NSSize(width: 470, height: 382)
        return window
    }

    /// Opens every saved window record no open window has claimed, once per launch.
    private var didRestoreSavedWindows = false

    private func restoreSavedWindows() {
        guard !didRestoreSavedWindows else { return }
        didRestoreSavedWindows = true
        for record in tabs.unclaimedWindowRecords() {
            createNewWindow(frame: record.frame.map(NSRectFromString))
        }
    }

    // MARK: - Incognito Window

    /// Create a new incognito/private browsing window
    func createIncognitoWindow() {
        guard let windowRegistry = windowRegistry,
              let webViewCoordinator = webViewCoordinator else {
            #if DEBUG
            print("⚠️ [BrowserManager] Cannot create incognito window - missing WindowRegistry or WebViewCoordinator")
            #endif
            return
        }

        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.ephemeralProfile = profileManager.createEphemeralProfile(for: windowState.id)

        // Registration gives the window its private tree (TabsController.attach). It must happen
        // before the hosting view exists: the sidebar's first render otherwise sees no private
        // tree, pages through the regular spaces, and keeps showing them.
        windowRegistry.register(windowState)
        tabs.open(url: TabsController.homeURL, in: windowState, placement: .newTab)

        let newWindow = makeBrowserNSWindow(title: "Private - Nook")
        let contentView = windowContent(ContentView(windowState: windowState), windowRegistry: windowRegistry, webViewCoordinator: webViewCoordinator)
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()

        windowState.window = newWindow
        windowRegistry.setActive(windowState)

        newWindow.makeKeyAndOrderFront(nil)
    }

    /// Destroys a closed incognito window's ephemeral profile and data store. Its pages were
    /// already ended by TabsController.detach.
    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        guard windowState.isIncognito else { return }
        await profileManager.removeEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = nil
        windowState.spaceID = nil
    }

    /// Close the active window
    func closeActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow?.window else { return }
        activeWindow.close()
    }

    /// Toggle full screen for the active window
    func toggleFullScreenForActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow?.window else { return }
        activeWindow.toggleFullScreen(nil)
    }

    /// Show the downloads panel in the sidebar
    func showDownloads() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            windowState.sidebarMenuSelectedTab = .downloads
            windowState.isSidebarMenuVisible = true
            windowState.isSidebarAIChatVisible = false
            windowState.savedSidebarWidth = windowState.sidebarWidth
            let newWidth: CGFloat = 400
            windowState.sidebarWidth = newWidth
            windowState.sidebarContentWidth = max(newWidth - 16, 0)
        }
    }

    /// Show the history panel in the sidebar
    func showHistory() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            windowState.sidebarMenuSelectedTab = .history
            windowState.isSidebarMenuVisible = true
            windowState.isSidebarAIChatVisible = false
            windowState.savedSidebarWidth = windowState.sidebarWidth
            let newWidth: CGFloat = 400
            windowState.sidebarWidth = newWidth
            windowState.sidebarContentWidth = max(newWidth - 16, 0)
        }
    }

    // MARK: - Tab Closure Undo Notification

    func showTabClosureToast(tabCount: Int) {
        tabClosureToastCount = tabCount
        showTabClosureToast = true

        // Auto-hide the toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.hideTabClosureToast()
        }
    }

    func hideTabClosureToast() {
        showTabClosureToast = false
        tabClosureToastCount = 0
    }

    func undoCloseTab() {
        guard let window = windowRegistry?.activeWindow else { return }
        tabs.reopenLastClosed(in: window)
    }
}

// MARK: - Update Handling

extension BrowserManager {
    struct UpdateAvailability: Equatable {
        let version: String
        let shortVersion: String
        let releaseNotesURL: URL?
        var isDownloaded: Bool

        init(version: String, shortVersion: String, releaseNotesURL: URL?, isDownloaded: Bool) {
            self.version = version
            self.shortVersion = shortVersion
            self.releaseNotesURL = releaseNotesURL
            self.isDownloaded = isDownloaded
        }

        init(item: SUAppcastItem, isDownloaded: Bool) {
            self.init(
                version: item.versionString,
                shortVersion: item.displayVersionString,
                releaseNotesURL: item.releaseNotesURL,
                isDownloaded: isDownloaded
            )
        }
    }

    func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem) {
        updateAvailability = UpdateAvailability(
            item: item,
            isDownloaded: updateAvailability?.isDownloaded ?? false
        )
    }

    func handleUpdaterFinishedDownloading(_ item: SUAppcastItem) {
        if var availability = updateAvailability {
            availability.isDownloaded = true
            updateAvailability = availability
        } else {
            updateAvailability = UpdateAvailability(item: item, isDownloaded: true)
        }
    }

    func handleUpdaterDidNotFindUpdate() {
        updateAvailability = nil
    }

    func handleUpdaterAbortedUpdate() {
        updateAvailability = nil
    }

    func handleUpdaterWillInstallOnQuit(_ item: SUAppcastItem) {
        handleUpdaterFinishedDownloading(item)
    }

    func installPendingUpdateIfAvailable() {
        appDelegate?.updaterController.checkForUpdates(nil)
    }

    // MARK: - Default Browser

    /// Sets Nook as the default browser for HTTP and HTTPS schemes
    func setAsDefaultBrowser() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        LSSetDefaultHandlerForURLScheme("http" as CFString, bundleIdentifier as CFString)
        LSSetDefaultHandlerForURLScheme("https" as CFString, bundleIdentifier as CFString)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
