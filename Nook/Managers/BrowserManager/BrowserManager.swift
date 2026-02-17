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
            let config = ModelConfiguration(url: Self.storeURL)
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
                    // Unexpected backup failure — continue but warn
                    Self.log.error(
                        "Backup attempt failed: \(String(describing: error), privacy: .public). Proceeding with cautious reset."
                    )
                }

                do {
                    try Self.deleteStore()
                    Self.log.notice(
                        "Deleted existing store (and sidecars) for schema-mismatch recovery")

                    let config = ModelConfiguration(url: Self.storeURL)
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
    @Published var sidebarWidth: CGFloat = 250
    @Published var sidebarContentWidth: CGFloat = 234
    @Published var isSidebarVisible: Bool = true
    @Published var isCommandPaletteVisible: Bool = false
    // Frame of the URL bar within the window; used to anchor the mini palette precisely
    @Published var urlBarFrame: CGRect = .zero
    @Published var shouldShowZoomPopup: Bool = false
    private var zoomPopupHideTimer: Timer?
    @Published var currentProfile: Profile?
    // Indicates an in-progress animated profile transition for coordinating UI
    @Published var isTransitioningProfile: Bool = false
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
    var tabManager: TabManager
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
    var trackingProtectionManager: TrackingProtectionManager
    var findManager: FindManager
    var importManager: ImportManager
    var zoomManager = ZoomManager()
    var boostsManager = BoostsManager()
    var keyboardShortcutManager: KeyboardShortcutManager?
    weak var nookSettings: NookSettingsService?
    weak var aiService: AIService?
    weak var aiConfigService: AIConfigService?

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

    /// DEPRECATED: Audio enforcement is an antipattern - should be managed per-window
    private func enforceExclusiveAudio(
        for tab: Tab, activeWindowId: UUID, desiredMuteState: Bool? = nil
    ) {
        guard let coordinator = webViewCoordinator else { return }
        let clones = coordinator.getAllWebViews(for: tab.id)
        let activeMute = desiredMuteState ?? tab.isAudioMuted
        for webView in clones {
            // Find which window this webView belongs to
            // For now, assume the webView in the active window gets the active mute state
            // This needs proper window tracking in WebViewCoordinator
            webView.isMuted = true
            webView.evaluateJavaScript(
                "document.querySelectorAll('video,audio').forEach(function(el){try{el.pause();}catch(e){}});",
                completionHandler: { _, _ in })
        }
    }

    /// Updates the gradient for a window, animating the transition if requested
    private func updateGradient(
        for windowState: BrowserWindowState, to newGradient: SpaceGradient, animate: Bool
    ) {
        // Skip gradient updates for incognito windows - they use their own dark gradient
        guard !windowState.isIncognito else { return }
        // Only animate if this is the active window (to avoid animating all windows simultaneously)
        let isActiveWindow = windowRegistry?.activeWindow?.id == windowState.id
        if animate && isActiveWindow {
            gradientColorManager.transition(to: newGradient, duration: 0.45)
        } else {
            gradientColorManager.setImmediate(newGradient)
        }
    }

    /// Updates gradients for all windows using the specified space
    func refreshGradientsForSpace(_ space: Space, animate: Bool) {
        guard let windowRegistry = windowRegistry else { return }
        let activeWindowId = windowRegistry.activeWindow?.id
        
        // Update gradients for all windows using this space (skip incognito)
        for (_, windowState) in windowRegistry.windows {
            // Skip incognito windows
            guard !windowState.isIncognito else { continue }
            if windowState.currentSpaceId == space.id {
                let isActiveWindow = windowState.id == activeWindowId
                if animate && isActiveWindow {
                    gradientColorManager.transition(to: space.gradient, duration: 0.45)
                } else {
                    gradientColorManager.setImmediate(space.gradient)
                }
            }
        }
    }

    private func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        guard let targetProfileId = windowState.currentProfileId else { return }
        guard !isSwitchingProfile else { return }
        guard currentProfile?.id != targetProfileId else { return }
        guard let targetProfile = profileManager.profiles.first(where: { $0.id == targetProfileId })
        else { return }
        Task { [weak self] in
            await self?.switchToProfile(targetProfile, context: context, in: windowState)
            await MainActor.run {
                if let activeId = self?.windowRegistry?.activeWindow?.id, activeId == windowState.id {
                    self?.windowRegistry?.activeWindow?.currentProfileId = targetProfileId
                }
            }
        }
    }


    // MARK: - OAuth Assist Banner
    struct OAuthAssist: Equatable {
        let host: String
        let url: URL
        let tabId: UUID
        let timestamp: Date
    }
    @Published var oauthAssist: OAuthAssist?
    private var oauthAssistCooldown: [String: Date] = [:]

    init() {
        // Phase 1: initialize all stored properties
        self.modelContext = Persistence.shared.container.mainContext
        if #available(macOS 15.5, *) {
            self.extensionManager = ExtensionManager.shared
        } else {
            self.extensionManager = nil
        }
        self.profileManager = ProfileManager(context: modelContext)
        // Ensure at least one profile exists and set current immediately for manager initialization
        self.profileManager.ensureDefaultProfile()
        let initialProfile = self.profileManager.profiles.first
        self.currentProfile = initialProfile

        self.tabManager = TabManager(browserManager: nil, context: modelContext)
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
        self.trackingProtectionManager = TrackingProtectionManager()
        self.findManager = FindManager()
        self.importManager = ImportManager()

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.splitManager.browserManager = self
        self.splitManager.windowRegistry = self.windowRegistry
        // Note: settingsManager will be injected later, so we skip initialization here
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
        bindTabManagerUpdates()
        if #available(macOS 15.5, *), let mgr = self.extensionManager {
            // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
            mgr.attach(browserManager: self)
            if let pid = currentProfile?.id {
                mgr.switchProfile(pid)
            }
            
            // Bind popup active state
            mgr.$isPopupActive
                .receive(on: RunLoop.main)
                .assign(to: &$isExtensionPopupActive)
        }
        if let g = self.tabManager.currentSpace?.gradient {
            self.gradientColorManager.setImmediate(g)
        } else {
            self.gradientColorManager.setImmediate(.default)
        }
        self.trackingProtectionManager.attach(browserManager: self)
        // Note: tracking protection will be configured after settingsManager injection

        self.externalMiniWindowManager.attach(browserManager: self)
        self.peekManager.attach(browserManager: self)
        bindPeekManagerUpdates()
        self.authenticationManager.attach(browserManager: self)
        // Migrate legacy history entries (with nil profile) to default profile to avoid cross-profile leakage
        self.migrateUnassignedDataToDefaultProfile()
        loadSidebarSettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabUnloadTimeoutChange),
            name: .tabUnloadTimeoutChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: .blockCrossSiteTrackingChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let enabled = note.userInfo?["enabled"] as? Bool else { return }
            Task { @MainActor [weak self] in
                self?.trackingProtectionManager.setEnabled(enabled)
            }
        }
        
        // Listen for TabManager initial data load completion to update window states
        NotificationCenter.default.addObserver(
            forName: .tabManagerDidLoadInitialData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTabManagerDataLoaded()
            }
        }
    }

    private func bindTabManagerUpdates() {
        tabManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func bindPeekManagerUpdates() {
        peekManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    /// Called when TabManager finishes loading initial data from persistence
    private func handleTabManagerDataLoaded() {
        print("🔄 [BrowserManager] TabManager data loaded, updating window states")
        
        // Update all window states with the loaded data
        guard let windowRegistry = windowRegistry else { return }
        
        for (_, windowState) in windowRegistry.windows {
            // Set current tab and space from TabManager
            windowState.currentTabId = tabManager.currentTab?.id
            windowState.currentSpaceId = tabManager.currentSpace?.id
            
            // Set gradient from current space
            if let spaceId = windowState.currentSpaceId,
                let space = tabManager.spaces.first(where: { $0.id == spaceId })
            {
                windowState.currentProfileId = space.profileId ?? currentProfile?.id
                // Only animate for the active window
                let isActiveWindow = windowRegistry.activeWindow?.id == windowState.id
                if isActiveWindow {
                    gradientColorManager.transition(to: space.gradient, duration: 0.3)
                } else {
                    gradientColorManager.setImmediate(space.gradient)
                }
            }
            
            // Refresh compositor to show the current tab
            windowState.refreshCompositor()
        }
        
        print("✅ [BrowserManager] Window states updated with loaded data")
    }

    // MARK: - OAuth Assist Controls
    func maybeShowOAuthAssist(for url: URL, in tab: Tab) {
        // Only when protection is enabled and not already disabled for this tab
        guard nookSettings?.blockCrossSiteTracking == true, trackingProtectionManager.isEnabled else {
            return
        }
        guard !trackingProtectionManager.isTemporarilyDisabled(tabId: tab.id) else { return }
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return }
        // Respect per-domain allow list
        guard !trackingProtectionManager.isDomainAllowed(host) else { return }
        // Simple heuristic for OAuth endpoints
        if isLikelyOAuthURL(url) {
            let now = Date()
            if let coolUntil = oauthAssistCooldown[host], coolUntil > now { return }
            oauthAssist = OAuthAssist(host: host, url: url, tabId: tab.id, timestamp: now)
            // Cooldown: don't show again for this host for 10 minutes
            oauthAssistCooldown[host] = now.addingTimeInterval(10 * 60)
            // Auto-hide after 8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if self?.oauthAssist?.host == host { self?.oauthAssist = nil }
            }
        }
    }

    func hideOAuthAssist() { oauthAssist = nil }

    func oauthAssistAllowForThisTab(duration: TimeInterval = 15 * 60) {
        guard let assist = oauthAssist else { return }
        guard let tab = tabManager.allTabs().first(where: { $0.id == assist.tabId }) else { return }
        trackingProtectionManager.disableTemporarily(for: tab, duration: duration)
        hideOAuthAssist()
    }

    func oauthAssistAlwaysAllowDomain() {
        guard let assist = oauthAssist else { return }
        trackingProtectionManager.allowDomain(assist.host, allowed: true)
        hideOAuthAssist()
    }

    /// Automatically allows an OAuth provider domain for tracking protection
    func oauthAllowDomain(_ host: String) {
        let normalizedHost = host.lowercased()
        print("🔐 [BrowserManager] Auto-allowing OAuth provider domain: \(normalizedHost)")
        trackingProtectionManager.allowDomain(normalizedHost, allowed: true)
    }

    private func isLikelyOAuthURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        // Common IdP hosts
        let hostHints = [
            "accounts.google.com", "login.microsoftonline.com", "login.live.com",
            "appleid.apple.com", "github.com", "gitlab.com", "bitbucket.org",
            "auth0.com", "okta.com", "onelogin.com", "pingidentity.com",
            "slack.com", "zoom.us", "login.cloudflareaccess.com",
        ]
        if hostHints.contains(where: { host.contains($0) }) { return true }
        // Common OAuth paths and signals
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize")
            || path.contains("/signin") || path.contains("/login") || path.contains("/callback")
        {
            return true
        }
        if query.contains("client_id=") || query.contains("redirect_uri=")
            || query.contains("response_type=")
        {
            return true
        }
        return false
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
                print("⏳ [BrowserManager] Ignoring concurrent profile switch request")
                return
            }
            self.isSwitchingProfile = true
            defer { self.isSwitchingProfile = false }

            let previousProfile = self.currentProfile
            print(
                "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")"
            )
            let animateTransition = context.shouldAnimateTransition

            let performUpdates = {
                if animateTransition {
                    self.isTransitioningProfile = true
                } else {
                    self.isTransitioningProfile = false
                }
                self.currentProfile = profile
                self.windowRegistry?.activeWindow?.currentProfileId = profile.id
                // Switch data stores for cookie/cache
                self.cookieManager.switchDataStore(profile.dataStore, profileId: profile.id)
                self.cacheManager.switchDataStore(profile.dataStore, profileId: profile.id)
                // Update history filtering
                self.historyManager.switchProfile(profile.id)
                // TabManager awareness (updates currentTab/currentSpace visibility)
                self.tabManager.handleProfileSwitch()
                // Update extension manager
                if #available(macOS 15.5, *), let mgr = self.extensionManager {
                    mgr.switchProfile(profile.id)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.isTransitioningProfile = false
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
            findManager.showFindBar(for: currentTabForActiveWindow())
        }
    }

    func updateFindManagerCurrentTab() {
        // Update the current tab for find manager
        findManager.updateCurrentTab(currentTabForActiveWindow())
    }

    // MARK: - Tab Management (delegates to TabManager)
    func createNewTab() {
        _ = tabManager.createNewTab()
    }

    /// Create a new tab and set it as active in the specified window
    func createNewTab(in windowState: BrowserWindowState) {
        // Handle incognito windows - create ephemeral tabs
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            let engine = nookSettings?.searchEngine ?? .google
            let normalizedURL = normalizeURL("https://www.google.com", provider: engine)
            guard let url = URL(string: normalizedURL) else { return }
            
            let newTab = tabManager.createEphemeralTab(
                url: url,
                in: windowState,
                profile: profile
            )
            selectTab(newTab, in: windowState)
            return
        }
        
        let targetSpace =
            windowState.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            }
            ?? windowState.currentProfileId.flatMap { pid in
                tabManager.spaces.first(where: { $0.profileId == pid })
            }
        let newTab = tabManager.createNewTab(in: targetSpace)
        selectTab(newTab, in: windowState)
    }

    func duplicateCurrentTab() {
        print("🔧 [BrowserManager] duplicateCurrentTab called")
        guard let currentTab = currentTabForActiveWindow() else {
            print("🔧 [BrowserManager] No current tab found")
            return
        }
        print("🔧 [BrowserManager] Current tab: \(currentTab.name) - \(currentTab.url)")

        // Get the current space for the active window
        let targetSpace =
            windowRegistry?.activeWindow?.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            } ?? tabManager.currentSpace

        // Get the current tab's index to place the duplicate below it
        let currentTabIndex = tabManager.tabs.firstIndex(where: { $0.id == currentTab.id }) ?? 0
        let insertIndex = currentTabIndex + 1

        // Create a new tab with the same URL and name
        let newTab = Tab(
            url: currentTab.url,
            name: currentTab.name,
            favicon: "globe",  // Will be updated by fetchAndSetFavicon
            spaceId: targetSpace?.id,
            index: 0,  // Will be set correctly after insertion
            browserManager: self
        )

        // Add the tab to the current space (it will be added at the end)
        tabManager.addTab(newTab)

        // Now move it to the correct position (right below the current tab)
        if let spaceId = targetSpace?.id {
            tabManager.reorderRegular(newTab, in: spaceId, to: insertIndex)
        }

        // Set as active tab in the current window
        if let windowState = windowRegistry?.activeWindow {
            selectTab(newTab, in: windowState)
        } else {
            selectTab(newTab)
        }

        print(
            "🔧 [BrowserManager] Duplicated tab created: \(newTab.name) - \(newTab.url) at index \(insertIndex)"
        )
    }

    func closeCurrentTab() {
        if let activeWindow = windowRegistry?.activeWindow,
            activeWindow.isCommandPaletteVisible
        {
            return
        }
        // Close tab in the active window
        if let activeWindow = windowRegistry?.activeWindow,
            let currentTab = currentTab(for: activeWindow)
        {
            // Handle ephemeral tabs in incognito windows
            if activeWindow.isIncognito {
                // Clean up WebView
                currentTab.performComprehensiveWebViewCleanup()
                
                // Remove from ephemeral tabs
                if let index = activeWindow.ephemeralTabs.firstIndex(where: { $0.id == currentTab.id }) {
                    activeWindow.ephemeralTabs.remove(at: index)
                    
                    // Select another tab or create new one
                    if let nextTab = activeWindow.ephemeralTabs.first {
                        selectTab(nextTab, in: activeWindow)
                    } else {
                        // All tabs closed - create a new ephemeral tab
                        if let profile = activeWindow.ephemeralProfile {
                            let engine = nookSettings?.searchEngine ?? .google
                            let normalizedURL = normalizeURL("https://www.google.com", provider: engine)
                            if let url = URL(string: normalizedURL) {
                                let newTab = tabManager.createEphemeralTab(url: url, in: activeWindow, profile: profile)
                                selectTab(newTab, in: activeWindow)
                            }
                        }
                    }
                }
            } else {
                tabManager.removeTab(currentTab.id)
            }
        } else {
            // Fallback to global current tab for backward compatibility
            tabManager.closeActiveTab()
        }
    }


    // MARK: - Dialog Methods

    func showQuitDialog() {
        if self.nookSettings?.askBeforeQuit == true {
            dialogManager.showQuitDialog(
                onAlwaysQuit: {
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

    // MARK: - Appearance / Gradient Editing
    private final class GradientDraft: ObservableObject {
        @Published var value: SpaceGradient
        init(_ value: SpaceGradient) { self.value = value }
    }

    func showGradientEditor() {
        guard let space = tabManager.currentSpace else {
            dialogManager.showDialog {
                StandardDialog(
                    header: {
                        DialogHeader(
                            icon: "paintpalette",
                            title: "No Space Available",
                            subtitle: "Create a space to customize its gradient."
                        )
                    },
                    content: {
                        Color.clear.frame(height: 0)
                    },
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

        let draft = GradientDraft(space.gradient)
        let binding = Binding<SpaceGradient>(
            get: { draft.value },
            set: { draft.value = $0 }
        )

        dialogManager.showDialog {
            StandardDialog(
                header: { EmptyView() },
                content: {
                    GradientEditorView(gradient: binding)
                        .environmentObject(self.gradientColorManager)
                },
                footer: {
                    DialogFooter(
                        leftButton: DialogButton(
                            text: "Cancel",
                            variant: .secondary,
                            action: { [weak self] in
                                self?.gradientColorManager.endInteractivePreview()
                                self?.gradientColorManager.transition(
                                    to: space.gradient, duration: 0.25)
                                self?.refreshGradientsForSpace(space, animate: true)
                                self?.closeDialog()
                            }
                        ),
                        rightButtons: [
                            DialogButton(
                                text: "Save",
                                iconName: "checkmark",
                                variant: .primary,
                                action: { [weak self] in
                                    space.gradient = draft.value
                                    self?.gradientColorManager.endInteractivePreview()
                                    self?.gradientColorManager.transition(
                                        to: draft.value, duration: 0.35)
                                    self?.refreshGradientsForSpace(space, animate: true)
                                    self?.tabManager.persistSnapshot()
                                    self?.closeDialog()
                                }
                            )
                        ]
                    )
                }
            )
        }
    }

    func showBoostsDialog() {
        guard let currentTab = currentTabForActiveWindow(),
            let domain = currentTab.url.host,
            let activeWindow = windowRegistry?.activeWindow,
            let webView = getWebView(for: currentTab.id, in: activeWindow.id)
        else {
            dialogManager.showDialog {
                StandardDialog(
                    header: {
                        DialogHeader(
                            icon: "bolt.circle",
                            title: "No Website Available",
                            subtitle: "Navigate to a website to create a boost."
                        )
                    },
                    content: {
                        Color.clear.frame(height: 0)
                    },
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

        // Show the boost window
        BoostsWindowManager.shared.show(
            for: webView,
            domain: domain,
            boostsManager: boostsManager
        )
    }

    func closeDialog() {
        dialogManager.closeDialog()
    }

    private func quitApplication() {
        // Clean up all tabs before terminating
        cleanupAllTabs()
        NSApplication.shared.terminate(nil)
    }

    func cleanupAllTabs() {
        print("🔄 [BrowserManager] Cleaning up all tabs")
        let allTabs = tabManager.pinnedTabs + tabManager.tabs

        for tab in allTabs {
            print("🔄 [BrowserManager] Cleaning up tab: \(tab.name)")
            tab.closeTab()
        }
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

    @objc private func handleTabUnloadTimeoutChange(_ notification: Notification) {
        if let timeout = notification.userInfo?["timeout"] as? TimeInterval {
            compositorManager.setUnloadTimeout(timeout)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Cookie Management Methods

    func clearCurrentPageCookies() {
        guard let currentTab = currentTabForActiveWindow(),
            let host = currentTab.url.host
        else { return }

        Task {
            await cookieManager.deleteCookiesForDomain(host)
        }
    }

    func clearAllCookies() {
        Task {
            await cookieManager.deleteAllCookies()
        }
    }

    func clearExpiredCookies() {
        Task {
            await cookieManager.deleteExpiredCookies()
        }
    }

    // MARK: - Cache Management

    func clearCurrentPageCache() {
        guard let currentTab = currentTabForActiveWindow(),
            let host = currentTab.url.host
        else { return }

        Task {
            await cacheManager.clearCacheForDomain(host)
        }
    }

    /// Clears site cache for current page excluding cookies, then reloads from origin.
    func hardReloadCurrentPage() {
        guard let currentTab = currentTabForActiveWindow(),
            let host = currentTab.url.host,
            let activeWindowId = windowRegistry?.activeWindow?.id
        else { return }
        Task { @MainActor in
            await cacheManager.clearCacheForDomainExcludingCookies(host)
            // Use the WebView that's actually visible in the current window
            if let webView = getWebView(for: currentTab.id, in: activeWindowId) {
                webView.reloadFromOrigin()
            } else {
                // Fallback to the tab's default webView
                currentTab.webView?.reloadFromOrigin()
            }
        }
    }

    func clearStaleCache() {
        Task {
            await cacheManager.clearStaleCache()
        }
    }

    func clearDiskCache() {
        Task {
            await cacheManager.clearDiskCache()
        }
    }

    func clearMemoryCache() {
        Task {
            await cacheManager.clearMemoryCache()
        }
    }

    func clearAllCache() {
        Task {
            await cacheManager.clearAllCache()
        }
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
        print("🧹 [BrowserManager] Clearing cookies for current profile: \(pid.uuidString)")
        Task { await cookieManager.deleteAllCookies() }
    }

    func clearCurrentProfileCache() {
        guard currentProfile?.id != nil else { return }
        print("🧹 [BrowserManager] Clearing cache for current profile")
        Task { await cacheManager.clearAllCache() }
    }

    func clearAllProfilesCookies() {
        print("🧹 [BrowserManager] Clearing cookies for ALL profiles (sequential, isolated)")
        let profiles = profileManager.profiles
        Task { @MainActor in
            for profile in profiles {
                let cm = CookieManager(dataStore: profile.dataStore)
                print(
                    "   → Clearing cookies for profile=\(profile.id.uuidString) [\(profile.name)]")
                await cm.deleteAllCookies()
            }
        }
    }

    func performPrivacyCleanupAllProfiles() {
        print(
            "🧹 [BrowserManager] Performing privacy cleanup across ALL profiles (sequential, isolated)"
        )
        let profiles = profileManager.profiles
        Task { @MainActor in
            for profile in profiles {
                print("   → Cleaning profile=\(profile.id.uuidString) [\(profile.name)]")
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
            print(
                "🔧 [BrowserManager] Assigned default profile to \(updated) legacy history entries")
        } catch {
            print("⚠️ [BrowserManager] Failed to assign default profile to existing data: \(error)")
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
        if #available(macOS 15.5, *) {
            extensionManager?.showExtensionInstallDialog()
        } else {
            // Show unsupported OS alert
            let alert = NSAlert()
            alert.messageText = "Extensions Not Supported"
            alert.informativeText = "Extensions require macOS 15.5 or later."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func enableExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.enableExtension(extensionId)
        }
    }

    func disableExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.disableExtension(extensionId)
        }
    }

    func uninstallExtension(_ extensionId: String) {
        if #available(macOS 15.5, *) {
            extensionManager?.uninstallExtension(extensionId)
        }
    }

    // MARK: - Window-Aware Tab Operations for Commands

    /// Get the current tab for the active window (used by keyboard shortcuts)
    func currentTabForActiveWindow() -> Tab? {
        if let activeWindow = windowRegistry?.activeWindow {
            return currentTab(for: activeWindow)
        }
        // Fallback to global current tab for backward compatibility
        return tabManager.currentTab
    }

    /// Refresh the current tab in the active window
    func refreshCurrentTabInActiveWindow() {
        currentTabForActiveWindow()?.refresh()
    }

    /// Toggle mute for the current tab in the active window
    func toggleMuteCurrentTabInActiveWindow() {
        currentTabForActiveWindow()?.toggleMute()
    }

    /// Request picture-in-picture for the current tab in the active window
    func requestPiPForCurrentTabInActiveWindow() {
        currentTabForActiveWindow()?.requestPictureInPicture()
    }

    /// Check if the current tab in the active window has video content
    func currentTabHasVideoContent() -> Bool {
        return currentTabForActiveWindow()?.hasVideoContent ?? false
    }

    /// Check if the current tab in the active window has PiP active
    func currentTabHasPiPActive() -> Bool {
        return currentTabForActiveWindow()?.hasPiPActive ?? false
    }

    /// Check if the current tab in the active window is muted
    func currentTabIsMuted() -> Bool {
        return currentTabForActiveWindow()?.isAudioMuted ?? false
    }

    /// Check if the current tab in the active window has audio content
    func currentTabHasAudioContent() -> Bool {
        return currentTabForActiveWindow()?.hasAudioContent ?? false
    }

    // MARK: - URL Utilities
    func copyCurrentURL() {
        if let url = currentTabForActiveWindow()?.url.absoluteString {
            print("Attempting to copy URL: \(url)")

            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(url, forType: .string)
                let e = NSHapticFeedbackManager.defaultPerformer
                e.perform(.generic, performanceTime: .drawCompleted)
                print("Clipboard operation success: \(success)")
            }

            // Show toast on active window
            if let windowState = windowRegistry?.activeWindow {
                windowState.isShowingCopyURLToast = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    windowState.isShowingCopyURLToast = false
                }
            }
        } else {
            print("No URL found to copy")
        }
    }

    // MARK: - Web Inspector
    func openWebInspector() {
        guard let currentTab = currentTabForActiveWindow() else {
            print("No current tab to inspect")
            return
        }

        if #available(macOS 13.3, *) {
            let webView = currentTab.activeWebView

            // Ensure the webview is inspectable (macOS 16+)
            if #available(macOS 16.0, *) {
                webView.isInspectable = true
            }

            // There is no public API to programmatically open the Web Inspector
            // Show an alert instructing the user how to open it manually
            showWebInspectorAlert()
        } else {
            print("Web inspector requires macOS 13.3 or later")
        }
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            if #available(macOS 15.4, *) {
                // No-op if already created; optionally clear
                await p.clearAllData()
            }
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
            print("⚠️ [BrowserManager] Current profile invalid; falling back to first available")
            currentProfile = profileManager.profiles.first
        }
        // Ensure spaces have profile assignments
        tabManager.validateTabProfileAssignments()
    }

    func recoverFromProfileError(_ error: Error, profile: Profile?) {
        print("❗️[BrowserManager] Profile operation failed: \(error)")
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
    func deleteProfile(_ profile: Profile) {
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
            // Choose replacement if current is being deleted
            if self.currentProfile?.id == profile.id {
                if let replacement = self.profileManager.profiles.first(where: {
                    $0.id != profile.id
                }) {
                    await self.switchToProfile(replacement)
                }
            }

            // Cleanup references and data
            self.tabManager.cleanupProfileReferences(profile.id)
            await profile.clearAllData()

            // Delete from manager
            let ok = self.profileManager.deleteProfile(profile)
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

    /// Register a new window state
    /// TEMPORARY: Setup window state with initial values
    /// This will be removed once we eliminate duplicate global state
    func setupWindowState(_ windowState: BrowserWindowState) {
        // Set TabManager reference for computed properties
        windowState.tabManager = tabManager

        // Initialize window state with current global state for backward compatibility
        windowState.sidebarWidth = sidebarWidth
        windowState.sidebarContentWidth = max(sidebarWidth - 16, 0)
        windowState.isSidebarVisible = isSidebarVisible
        windowState.savedSidebarWidth = savedSidebarWidth
        windowState.isCommandPaletteVisible = false

        // Set the NSWindow reference for keyboard shortcuts
        if let window = NSApplication.shared.windows.first(where: {
            $0.contentView?.subviews.contains(where: {
                ($0 as? NSHostingView<ContentView>) != nil
            }) ?? false
        }) {
            windowState.window = window
        }
        windowState.urlBarFrame = urlBarFrame
        windowState.currentProfileId = currentProfile?.id

        // Set initial space and tab
        windowState.currentSpaceId = tabManager.currentSpace?.id
        windowState.currentTabId = tabManager.currentTab?.id
        
        // Set gradient from current space immediately to avoid showing default blue
        if let spaceId = windowState.currentSpaceId,
            let space = tabManager.spaces.first(where: { $0.id == spaceId })
        {
            windowState.currentProfileId = space.profileId ?? currentProfile?.id
            // Set gradient immediately without animation
            gradientColorManager.setImmediate(space.gradient)
        } else {
            // Fallback to default gradient if no space exists
            gradientColorManager.setImmediate(.default)
        }

        print("🪟 [BrowserManager] Setup window state: \(windowState.id), currentTab: \(windowState.currentTabId?.uuidString ?? "none"), currentSpace: \(windowState.currentSpaceId?.uuidString ?? "none")")
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
        // Skip gradient sync for incognito windows - they use their own dark gradient
        if !windowState.isIncognito {
            gradientColorManager.setImmediate(windowState.gradient)
        }
        splitManager.refreshPublishedState(for: windowState.id)
        isCommandPaletteVisible = windowState.isCommandPaletteVisible
        if windowState.currentProfileId == nil {
            windowState.currentProfileId = currentProfile?.id
        }
        adoptProfileIfNeeded(for: windowState, context: .windowActivation)
    }

    // MARK: - Window-Aware Tab Operations

    /// Get the current tab for a specific window
    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        // Check ephemeral tabs first for incognito windows
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == windowState.currentTabId }
        }
        
        guard let tabId = windowState.currentTabId else { return nil }
        return tabManager.allTabs().first { $0.id == tabId }
    }

    /// Select a tab in the active window (convenience method for sidebar clicks)
    func selectTab(_ tab: Tab) {
        guard let activeWindow = windowRegistry?.activeWindow else {
            print("⚠️ [BrowserManager] No active window for tab selection")
            return
        }
        selectTab(tab, in: activeWindow)
    }

    /// Select a tab in a specific window
    func selectTab(_ tab: Tab, in windowState: BrowserWindowState) {
        windowState.currentTabId = tab.id

        // Update active side in split view if applicable
        splitManager.updateActiveSide(for: tab.id, in: windowState.id)

        // Update space if the tab belongs to a different space
        if let spaceId = tab.spaceId, windowState.currentSpaceId != spaceId {
            windowState.currentSpaceId = spaceId
        }

        // Remember this tab as active for the current space in this window
        if let currentSpaceId = windowState.currentSpaceId {
            windowState.activeTabForSpace[currentSpaceId] = tab.id
        }

        if let spaceId = windowState.currentSpaceId,
            let space = tabManager.spaces.first(where: { $0.id == spaceId })
        {
            updateGradient(for: windowState, to: space.gradient, animate: true)
            windowState.currentProfileId = space.profileId ?? currentProfile?.id
        } else if windowState.currentSpaceId == nil {
            updateGradient(for: windowState, to: .default, animate: false)
            windowState.currentProfileId = currentProfile?.id
        }

        // Note: No need to track tab display ownership - each window shows its own current tab

        // Load the tab in compositor if needed (reloads unloaded tabs)
        compositorManager.loadTab(tab)

        // Update tab visibility in compositor
        compositorManager.updateTabVisibility(currentTabId: tab.id)

        // Check media state using native WebKit API
        tab.checkMediaState()

        // Notify extensions about tab activation
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.notifyTabActivated(newTab: tab, previous: nil)
        }

        // Update find manager with new current tab
        updateFindManagerCurrentTab()

        // Refresh compositor for this window
        windowState.refreshCompositor()

        // DISABLED: Exclusive audio enforcement - use standard browser behavior instead
        // enforceExclusiveAudio(for: tab, activeWindowId: windowState.id)

        print("🪟 [BrowserManager] Selected tab \(tab.name) in window \(windowState.id)")

        // Update global tab state for the active window
        if windowRegistry?.activeWindow?.id == windowState.id {
            // Only update the global state, don't trigger UI operations again
            tabManager.updateActiveTabState(tab)
        }
    }

    /// Get tabs that should be displayed in a specific window
    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        // For incognito windows, return ephemeral tabs directly
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }
        
        print("🔍 tabsForDisplay called for window \(windowState.id.uuidString.prefix(8))...")

        // Get tabs for the window's current space
        let currentSpace = windowState.currentSpaceId.flatMap { id in
            tabManager.spaces.first(where: { $0.id == id })
        }

        print("   - windowState.currentSpaceId: \(windowState.currentSpaceId?.uuidString ?? "nil")")
        print(
            "   - resolved currentSpace: \(currentSpace?.name ?? "nil") (id: \(currentSpace?.id.uuidString.prefix(8) ?? "nil"))"
        )

        let profileId =
            windowState.currentProfileId ?? currentSpace?.profileId ?? currentProfile?.id
        let essentials = profileId.flatMap { tabManager.essentialTabs(for: $0) } ?? []
        let spacePinned = currentSpace.map { tabManager.spacePinnedTabs(for: $0.id) } ?? []
        let regularTabs = currentSpace.map { tabManager.tabs(in: $0) } ?? []

        print("   - essentials: \(essentials.count) tabs")
        print("   - spacePinned: \(spacePinned.count) tabs")
        print("   - regularTabs: \(regularTabs.count) tabs")

        print("   - spacePinned tabs details:")
        for tab in spacePinned {
            print(
                "     * \(tab.name) (id: \(tab.id.uuidString.prefix(8))..., folderId: \(tab.folderId?.uuidString.prefix(8) ?? "nil"))"
            )
        }

        let result = essentials + spacePinned + regularTabs
        print("   - TOTAL tabsForDisplay: \(result.count)")

        return result
    }

    /// Check if a tab is frozen (being displayed in another window)
    /// Note: This is no longer needed since each window shows its own current tab independently
    func isCurrentTabFrozen(in windowState: BrowserWindowState) -> Bool {
        return false  // Always false since windows are independent
    }

    /// Refresh compositor for a specific window
    func refreshCompositor(for windowState: BrowserWindowState) {
        windowState.refreshCompositor()
    }

/// DEPRECATED: Use WebViewCoordinator.getWebView() directly via environment
    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        // Check ephemeral tabs first for incognito windows
        if let windowState = windowRegistry?.windows[windowId],
           windowState.isIncognito {
            return webViewCoordinator?.getWebView(for: tabId, in: windowId)
        }
        return webViewCoordinator?.getWebView(for: tabId, in: windowId)
    }

    /// DEPRECATED: Use WebViewCoordinator directly
    func createWebView(for tabId: UUID, in windowId: UUID) -> WKWebView {
        // Check ephemeral tabs first for incognito windows
        if let windowState = windowRegistry?.windows[windowId],
           windowState.isIncognito,
           let tab = windowState.ephemeralTabs.first(where: { $0.id == tabId }),
           let coordinator = webViewCoordinator {
            return coordinator.createWebView(for: tab, in: windowId)
        }
        
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }),
              let coordinator = webViewCoordinator else {
            fatalError("Tab or WebViewCoordinator not found")
        }
        return coordinator.createWebView(for: tab, in: windowId)
    }

    /// DEPRECATED: This should not go through BrowserManager
    func syncTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }),
              let webViewCoordinator = webViewCoordinator else { return }

        webViewCoordinator.syncTab(tabId, to: tab.url)
    }

    func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {
        webViewCoordinator?.syncTab(tabId, to: url)
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        webViewCoordinator?.reloadTab(tabId)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {
        webViewCoordinator?.setMuteState(muted, for: tabId, excludingWindow: originatingWindowId)
    }

    /// Set active space for a specific window
    func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {
        let isActiveWindow = windowRegistry?.activeWindow?.id == windowState.id
        if isActiveWindow {
            tabManager.setActiveSpace(space)
        }

        // Update the window's current space
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = space.profileId ?? currentProfile?.id
        updateGradient(for: windowState, to: space.gradient, animate: true)

        // Get the active tab for this space
        let spacePinned = tabManager.spacePinnedTabs(for: space.id)
        let regularTabs = tabManager.tabs(in: space)
        let profileEssentials =
            (space.profileId ?? currentProfile?.id).flatMap { tabManager.essentialTabs(for: $0) }
            ?? []
        let allTabsForSpace = profileEssentials + spacePinned + regularTabs

        // Find the active tab for this space - prioritize window-specific memory
        var targetTab: Tab?

        // First, try to use the window-specific active tab for this space
        if let windowActiveTabId = windowState.activeTabForSpace[space.id] {
            targetTab = allTabsForSpace.first { $0.id == windowActiveTabId }
        }

        // If no window-specific tab found, try the global space active tab
        if targetTab == nil, let globalActiveId = space.activeTabId {
            targetTab = allTabsForSpace.first { $0.id == globalActiveId }
        }

        // Fallback to first available tab in the space
        if targetTab == nil {
            targetTab = allTabsForSpace.first
        }

        // Set the active tab for this window
        if let tab = targetTab {
            selectTab(tab, in: windowState)
        }

        if isActiveWindow {
            adoptProfileIfNeeded(for: windowState, context: .spaceChange)
        }

        print(
            "🪟 [BrowserManager] Set active space \(space.name) for window \(windowState.id), active tab: \(targetTab?.name ?? "none")"
        )
    }

    /// Validate and fix window states after tab/space mutations
    func validateWindowStates() {
        for (_, windowState) in windowRegistry?.windows ?? [:] {
            var needsUpdate = false

            // Check if current tab still exists
            if let currentTabId = windowState.currentTabId {
                if tabManager.allTabs().first(where: { $0.id == currentTabId }) == nil {
                    windowState.currentTabId = nil
                    needsUpdate = true
                }
            }

            // Check if current space still exists
            if let currentSpaceId = windowState.currentSpaceId {
                if tabManager.spaces.first(where: { $0.id == currentSpaceId }) == nil {
                    windowState.currentSpaceId = tabManager.spaces.first?.id
                    needsUpdate = true
                }
            }

            // If no current tab, try to find a suitable one using TabManager's current tab
            if windowState.currentTabId == nil {
                // Prefer TabManager's current tab over arbitrary first tab
                if let managerCurrentTab = tabManager.currentTab {
                    windowState.currentTabId = managerCurrentTab.id
                    print(
                        "🔧 [validateWindowStates] Using TabManager's current tab: \(managerCurrentTab.name)"
                    )
                } else {
                    // Fallback to first available tab
                    let availableTabs = tabsForDisplay(in: windowState)
                    if let firstTab = availableTabs.first {
                        windowState.currentTabId = firstTab.id
                        print("🔧 [validateWindowStates] Using fallback first tab: \(firstTab.name)")
                    }
                }
                needsUpdate = true
            }

            // If no current space, use the first available space
            if windowState.currentSpaceId == nil {
                windowState.currentSpaceId = tabManager.spaces.first?.id
                needsUpdate = true
            }

            if let spaceId = windowState.currentSpaceId,
                let space = tabManager.spaces.first(where: { $0.id == spaceId })
            {
                updateGradient(for: windowState, to: space.gradient, animate: false)
                windowState.currentProfileId = space.profileId ?? currentProfile?.id
            } else if windowState.currentSpaceId == nil {
                updateGradient(for: windowState, to: .default, animate: false)
                windowState.currentProfileId = currentProfile?.id
            }

            if needsUpdate {
                windowState.refreshCompositor()
            }
        }

        // Note: No need to clean up tab display owners since they're no longer used
    }

    /// Import Data from arc
    func importArcData() {
        Task {
            let result = await importManager.importArcSidebarData()

            for space in result.spaces {
                print("========== \(space.title)")
                self.tabManager.createSpace(name: space.title, icon: space.emoji ?? "person.fill")

                guard
                    let createdSpace = self.tabManager.spaces.first(where: {
                        $0.name == space.title
                    })
                else {
                    continue
                }

                for tab in space.unpinnedTabs {
                    print("Unpinned tab - \(tab.title)")
                    self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                }

                for tab in space.pinnedTabs {
                    print("Pinned tab - \(tab.title)")
                    let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                    self.tabManager.pinTabToSpace(newtab, spaceId: createdSpace.id)
                }
                for folder in space.folders {
                    print("Folder - \(folder.title)")
                    let newFolder = self.tabManager.createFolder(
                        for: createdSpace.id, name: folder.title)

                    for tab in folder.tabs {
                        let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                        self.tabManager.moveTabToFolder(tab: newtab, folderId: newFolder.id)
                    }
                }
            }
            for topTab in result.topTabs {
                print("TopTab - \(topTab.title)")
                let tab = self.tabManager.createNewTab(
                    url: topTab.url, in: self.tabManager.spaces.first!)
                self.tabManager.addToEssentials(tab)
            }
        }
    }

    // MARK: - Keyboard Shortcut Support Methods

    /// Select the next tab in the active window
    func selectNextTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
            let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let nextIndex = (currentIndex + 1) % currentTabs.count
        if let nextTab = currentTabs[safe: nextIndex] {
            selectTab(nextTab, in: activeWindow)
        }
    }

    /// Select the previous tab in the active window
    func selectPreviousTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
            let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let previousIndex = currentIndex > 0 ? currentIndex - 1 : currentTabs.count - 1
        if let previousTab = currentTabs[safe: previousIndex] {
            selectTab(previousTab, in: activeWindow)
        }
    }

    /// Select tab by index in the active window
    func selectTabByIndexInActiveWindow(_ index: Int) {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard currentTabs.indices.contains(index) else { return }

        let tab = currentTabs[index]
        selectTab(tab, in: activeWindow)
    }

    /// Select the last tab in the active window
    func selectLastTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let lastTab = currentTabs.last else { return }

        selectTab(lastTab, in: activeWindow)
    }

    /// Select the next space in the active window
    func selectNextSpaceInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
            let currentSpaceId = activeWindow.currentSpaceId,
            let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })
        else { return }

        let nextIndex = (currentSpaceIndex + 1) % tabManager.spaces.count
        if let nextSpace = tabManager.spaces[safe: nextIndex] {
            setActiveSpace(nextSpace, in: activeWindow)
        }
    }

    /// Select the previous space in the active window
    func selectPreviousSpaceInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
            let currentSpaceId = activeWindow.currentSpaceId,
            let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })
        else { return }

        let previousIndex =
            currentSpaceIndex > 0 ? currentSpaceIndex - 1 : tabManager.spaces.count - 1
        if let previousSpace = tabManager.spaces[safe: previousIndex] {
            setActiveSpace(previousSpace, in: activeWindow)
        }
    }

    /// Create a new window
    func createNewWindow() {
        guard let windowRegistry = windowRegistry,
              let webViewCoordinator = webViewCoordinator else {
            print("⚠️ [BrowserManager] Cannot create window - missing WindowRegistry or WebViewCoordinator")
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let contentView = ContentView()
            .background(BackgroundWindowModifier())
            .ignoresSafeArea(.all)
            .environmentObject(self)
            .environment(windowRegistry)
            .environment(webViewCoordinator)
            .environmentObject(gradientColorManager)
            .environment(\.nookSettings, nookSettings)
            .environment(aiService)
            .environment(aiConfigService)

        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.title = "Nook"
        newWindow.minSize = NSSize(width: 470, height: 382)
        newWindow.contentMinSize = NSSize(width: 470, height: 382)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - Incognito Window
    
    /// Active incognito window IDs
    @Published private var incognitoWindows: Set<UUID> = []
    
    /// Create a new incognito/private browsing window
    func createIncognitoWindow() {
        guard let windowRegistry = windowRegistry,
              let webViewCoordinator = webViewCoordinator else {
            print("⚠️ [BrowserManager] Cannot create incognito window - missing WindowRegistry or WebViewCoordinator")
            return
        }

        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        
        // Create ephemeral profile for this window
        let ephemeralProfile = profileManager.createEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id
        
        // Create default ephemeral space
        let ephemeralSpace = Space(
            id: UUID(),
            name: "Incognito",
            icon: "eye.slash",
            profileId: ephemeralProfile.id
        )
        ephemeralSpace.isEphemeral = true
        windowState.ephemeralSpaces.append(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id
        
        // Track as incognito window
        incognitoWindows.insert(windowState.id)
        
        // Create the NSWindow (similar to createNewWindow but with incognito title)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let contentView = ContentView(windowState: windowState)
            .background(BackgroundWindowModifier())
            .ignoresSafeArea(.all)
            .environmentObject(self)
            .environment(windowRegistry)
            .environment(webViewCoordinator)
            .environmentObject(gradientColorManager)
            .environment(\.nookSettings, nookSettings)
            .environment(aiService)
            .environment(aiConfigService)

        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.title = "Incognito - Nook"
        newWindow.minSize = NSSize(width: 470, height: 382)
        newWindow.contentMinSize = NSSize(width: 470, height: 382)
        newWindow.center()
        
        windowState.window = newWindow
        
        // Register the window
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        
        // Set tabManager reference only (don't call full setupWindowState - it would overwrite ephemeral state)
        windowState.tabManager = tabManager
        
        // Create initial ephemeral tab
        createNewTab(in: windowState)
        
        newWindow.makeKeyAndOrderFront(nil)
        
        print("🔒 [BrowserManager] Created incognito window: \(windowState.id)")
    }
    
    /// Close an incognito window and clean up all ephemeral data
    /// This method ensures complete destruction of the incognito session with no memory leaks
    func closeIncognitoWindow(_ windowState: BrowserWindowState) {
        guard windowState.isIncognito else { return }
        
        print("🔒 [BrowserManager] Closing incognito window: \(windowState.id)")
        
        // Step 1: Clean up all clone WebViews for ephemeral tabs from WebViewCoordinator
        // This is critical - clone WebViews hold references to the data store
        if let coordinator = webViewCoordinator {
            for tab in windowState.ephemeralTabs {
                coordinator.removeAllWebViews(for: tab)
            }
        }
        
        // Step 2: Clean up main WebViews for ephemeral tabs
        for tab in windowState.ephemeralTabs {
            tab.performComprehensiveWebViewCleanup()
        }
        
        // Step 3: Stop tracking this window BEFORE removing profile
        // This prevents any concurrent access to ephemeral data
        incognitoWindows.remove(windowState.id)
        
        // Step 4: Clear all ephemeral references from window state
        // This breaks retain cycles BEFORE profile destruction
        let ephemeralTabs = windowState.ephemeralTabs
        let ephemeralSpaces = windowState.ephemeralSpaces
        windowState.ephemeralTabs.removeAll()
        windowState.ephemeralSpaces.removeAll()
        windowState.currentTabId = nil
        
        // Step 5: Remove ephemeral profile (triggers data store destruction)
        // This is done last to ensure all references are cleared first
        profileManager.removeEphemeralProfile(for: windowState.id)
        
        // Step 6: Final cleanup of window state
        windowState.ephemeralProfile = nil
        windowState.currentSpaceId = nil
        
        // Step 7: Force a memory warning to encourage garbage collection
        // This helps ensure the data store is released
        #if DEBUG
        print("🔒 [BrowserManager] Incognito window closed. Ephemeral tabs: \(ephemeralTabs.count), spaces: \(ephemeralSpaces.count)")
        #endif
        
        print("🔒 [BrowserManager] Incognito window fully closed and cleaned up: \(windowState.id)")
    }
    
    /// Check if a tab can be dragged to a target window (block cross-window for incognito)
    func canDragTab(_ tab: Tab, toWindow targetWindow: BrowserWindowState) -> Bool {
        let sourceIsIncognito = tab.isEphemeral
        let targetIsIncognito = targetWindow.isIncognito
        
        // Block dragging between incognito and normal windows
        return sourceIsIncognito == targetIsIncognito
    }
    
    /// Check if a window is an incognito window
    func isIncognitoWindow(_ windowId: UUID) -> Bool {
        return incognitoWindows.contains(windowId)
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

    /// Show downloads (placeholder implementation)
    func showDownloads() {
        // TODO: Implement downloads UI
    }

    /// Show history (placeholder implementation)
    func showHistory() {
        // TODO: Implement history UI
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
        tabManager.undoCloseTab()
    }

    /// Expand all folders in the sidebar
    func expandAllFoldersInSidebar() {
        // TODO: Implement folder expansion
        // This would need to be handled by the sidebar component
        toggleSidebar()
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

    // MARK: - Zoom Management

    /// Zoom in for the current tab
    func zoomInCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = currentTabForActiveWindow(),
            let webView = getWebView(for: currentTab.id, in: windowState.id)
        else {
            return
        }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.zoomIn(for: webView, domain: domain, tabId: currentTab.id)

        // Show zoom popup feedback
        shouldShowZoomPopup = true

        // Cancel any existing hide timer
        zoomPopupHideTimer?.invalidate()

        // Schedule new hide timer
        zoomPopupHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.shouldShowZoomPopup = false
                self.zoomPopupHideTimer = nil
            }
        }
    }

    /// Zoom out for the current tab
    func zoomOutCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = currentTabForActiveWindow(),
            let webView = getWebView(for: currentTab.id, in: windowState.id)
        else {
            return
        }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.zoomOut(for: webView, domain: domain, tabId: currentTab.id)

        // Show zoom popup feedback
        shouldShowZoomPopup = true

        // Cancel any existing hide timer
        zoomPopupHideTimer?.invalidate()

        // Schedule new hide timer
        zoomPopupHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.shouldShowZoomPopup = false
                self.zoomPopupHideTimer = nil
            }
        }
    }

    /// Reset zoom to 100% for the current tab
    func resetZoomCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow,
            let currentTab = currentTabForActiveWindow(),
            let webView = getWebView(for: currentTab.id, in: windowState.id)
        else {
            return
        }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.resetZoom(for: webView, domain: domain, tabId: currentTab.id)

        // Show zoom popup feedback
        shouldShowZoomPopup = true

        // Cancel any existing hide timer
        zoomPopupHideTimer?.invalidate()

        // Schedule new hide timer
        zoomPopupHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.shouldShowZoomPopup = false
                self.zoomPopupHideTimer = nil
            }
        }
    }

    /// Apply a specific zoom level to the current tab
    func applyZoomLevel(_ zoomLevel: Double, to tabId: UUID? = nil) {
        guard let windowState = windowRegistry?.activeWindow else { return }

        let targetTabId = tabId ?? (currentTabForActiveWindow()?.id)
        guard let tabId = targetTabId,
            let webView = getWebView(for: tabId, in: windowState.id),
            let tab = tabManager.tabs.first(where: { $0.id == tabId })
        else {
            return
        }

        let domain = tab.url.host ?? tab.url.absoluteString
        zoomManager.applyZoom(zoomLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Load saved zoom level when a tab navigates to a new domain
    func loadZoomForTab(_ tabId: UUID) {
        guard let windowState = windowRegistry?.activeWindow,
            let webView = getWebView(for: tabId, in: windowState.id),
            let tab = tabManager.tabs.first(where: { $0.id == tabId }),
            let domain = tab.url.host
        else {
            return
        }

        zoomManager.loadSavedZoom(for: webView, domain: domain, tabId: tabId)
    }

    /// Clean up zoom data when a tab is closed
    func cleanupZoomForTab(_ tabId: UUID) {
        zoomManager.removeTabZoomLevel(for: tabId)
    }

    /// Get current zoom level for display
    func getCurrentZoomLevel() -> Double {
        return zoomManager.currentZoomLevel
    }

    /// Get current zoom percentage for display
    func getCurrentZoomPercentage() -> String {
        return zoomManager.getZoomPercentageDisplay()
    }

    /// Show zoom popup (for external components to trigger)
    func showZoomPopup() {
        // This will be handled by the UI layer (TopBarView) observing zoom changes
        // For now, we'll rely on the zoom button to show the popup
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
