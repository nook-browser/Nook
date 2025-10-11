//
//  BrowserManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import SwiftData
import AppKit
import WebKit
import OSLog
import Combine
import Sparkle
import CoreServices

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer

    // MARK: - Constants
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Persistence")
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
        ExtensionEntity.self
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
            log.error("Failed to create Application Support directory: \(String(describing: error), privacy: .public)")
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
            log.error("Failed to create Backups directory: \(String(describing: error), privacy: .public)")
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
            Self.log.error("SwiftData container initialization failed. Classification=\(String(describing: classification)) error=\(String(describing: error), privacy: .public)")

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
                    Self.log.error("Backup attempt failed: \(String(describing: error), privacy: .public). Proceeding with cautious reset.")
                }

                do {
                    try Self.deleteStore()
                    Self.log.notice("Deleted existing store (and sidecars) for schema-mismatch recovery")

                    let config = ModelConfiguration(url: Self.storeURL)
                    container = try ModelContainer(for: Self.schema, configurations: [config])
                    Self.log.notice("Recreated SwiftData container after schema mismatch using configured URL")
                } catch {
                    // On any failure, attempt to restore backup (if one was made) and abort
                    if didCreateBackup {
                        do {
                            try Self.restoreFromBackup()
                            Self.log.fault("Restored store from latest backup after failed recovery attempt")
                        } catch {
                            Self.log.fault("Failed to restore store from backup: \(String(describing: error), privacy: .public)")
                        }
                    }
                    fatalError("Failed to recover from schema mismatch. Aborting to protect data integrity: \(error)")
                }

            case .diskSpace:
                Self.log.fault("Store initialization failed due to insufficient disk space. Not deleting store.")
                fatalError("SwiftData initialization failed due to insufficient disk space: \(error)")

            case .corruption:
                Self.log.fault("Store appears corrupted. Not deleting store. Please investigate backups manually.")
                fatalError("SwiftData initialization failed due to suspected corruption: \(error)")

            case .other:
                Self.log.error("Store initialization failed with unclassified error. Not deleting store.")
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
        if lower.contains("migration") || lower.contains("incompatible") || lower.contains("model") || lower.contains("version hash") || lower.contains("mapping model") || lower.contains("schema") {
            return .schemaMismatch
        }

        // Corruption indicators (SQLite/CoreData wording)
        if lower.contains("corrupt") || lower.contains("malformed") || lower.contains("database disk image is malformed") || lower.contains("file is encrypted or is not a database") {
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
                Self.log.info("No existing store found to back up at \(source.path, privacy: .public)")
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
                    let dest = backupDir.appendingPathComponent(file.lastPathComponent, isDirectory: false)
                    do {
                        try fm.copyItem(at: file, to: dest)
                    } catch {
                        Self.log.error("Failed to copy \(file.lastPathComponent, privacy: .public) to backup: \(String(describing: error), privacy: .public)")
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
                contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])
            } catch {
                Self.log.error("Failed to list backups: \(String(describing: error), privacy: .public)")
                throw error
            }

            let backups = contents.filter { url in
                url.lastPathComponent.hasPrefix(Self.backupPrefix) && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            guard !backups.isEmpty else { throw PersistenceBackupError.noBackupsFound }

            // Pick the most recently modified backup directory
            let latest = backups.max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return l < r
            }!

            // Remove current store files first
            try Self.deleteStore()

            // Copy all files from backup dir back to app support dir
            let backupFiles = try fm.contentsOfDirectory(at: latest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in backupFiles {
                let dest = Self.appSupportURL.appendingPathComponent(file.lastPathComponent, isDirectory: false)
                do { try fm.copyItem(at: file, to: dest) } catch {
                    Self.log.error("Restore copy failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                    throw error
                }
            }

            Self.log.notice("Restored store from backup directory: \(latest.lastPathComponent, privacy: .public)")
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
                        Self.log.error("Failed to remove \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
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
    nonisolated private static func runBlockingOnUtilityQueue<T>(_ work: @escaping () throws -> T) throws -> T {
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

private extension BrowserManager.ProfileSwitchContext {
    var shouldProvideFeedback: Bool {
        switch self {
        case .windowActivation:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }

    var shouldAnimateTransition: Bool {
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
    // Mini palette shown when clicking the URL bar
    @Published var isMiniCommandPaletteVisible: Bool = false
    @Published var didCopyURL: Bool = false
    @Published var commandPalettePrefilledText: String = ""
    @Published var shouldNavigateCurrentTab: Bool = false
    // Frame of the URL bar within the window; used to anchor the mini palette precisely
    @Published var urlBarFrame: CGRect = .zero
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


    // MARK: - Window State Management
    /// Registry of all active window states
    var windowStates: [UUID: BrowserWindowState] = [:]
    
    /// Note: Removed tabDisplayOwners - each window now shows its own current tab independently
    
    /// Window-specific web views: tabId -> windowId -> WKWebView
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]
    private var isSyncingTab: Set<UUID> = [] // Prevent recursive sync calls
    
    /// Weak wrapper for NSView references stored per window
    private struct WeakNSView { weak var view: NSView? }
    /// Container views per window so the compositor can manage multiple windows safely
    private var compositorContainerViews: [UUID: WeakNSView] = [:]
    
    /// The currently focused/active window state
    var activeWindowState: BrowserWindowState?

    /// Reference to the app delegate for Sparkle integration
    weak var appDelegate: AppDelegate?

    var modelContext: ModelContext
    var tabManager: TabManager
    var profileManager: ProfileManager
    var settingsManager: SettingsManager
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

    var externalMiniWindowManager = ExternalMiniWindowManager()
    @Published var peekManager = PeekManager()
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    var isSwitchingProfile: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    
    // Compositor container view
    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        if let view {
            compositorContainerViews[windowId] = WeakNSView(view: view)
        } else {
            compositorContainerViews.removeValue(forKey: windowId)
        }
    }
    
    func compositorContainerView(for windowId: UUID) -> NSView? {
        if let view = compositorContainerViews[windowId]?.view {
            return view
        }
        compositorContainerViews.removeValue(forKey: windowId)
        return nil
    }
    
    func removeCompositorContainerView(for windowId: UUID) {
        compositorContainerViews.removeValue(forKey: windowId)
    }
    
    func removeWebViewFromContainers(_ webView: WKWebView) {
        for (windowId, entry) in compositorContainerViews {
            guard let container = entry.view else {
                compositorContainerViews.removeValue(forKey: windowId)
                continue
            }
            for subview in container.subviews where subview === webView {
                subview.removeFromSuperview()
            }
        }
    }

    func removeAllWebViews(for tab: Tab) {
        guard let entries = webViewsByTabAndWindow.removeValue(forKey: tab.id) else { return }
        for (_, webView) in entries {
            tab.cleanupCloneWebView(webView)
            removeWebViewFromContainers(webView)
        }
    }

    private func enforceExclusiveAudio(for tab: Tab, activeWindowId: UUID, desiredMuteState: Bool? = nil) {
        guard let clones = webViewsByTabAndWindow[tab.id] else { return }
        let activeMute = desiredMuteState ?? tab.isAudioMuted
        for (windowId, webView) in clones {
            if windowId == activeWindowId {
                webView.isMuted = activeMute
            } else {
                webView.isMuted = true
                webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(function(el){try{el.pause();}catch(e){}});", completionHandler: nil)
            }
        }
    }

    private func updateGradient(for windowState: BrowserWindowState, to newGradient: SpaceGradient, animate: Bool) {
        let previousGradient = windowState.activeGradient
        guard !previousGradient.visuallyEquals(newGradient) else {
            windowState.activeGradient = newGradient
            if activeWindowState?.id == windowState.id {
                gradientColorManager.setImmediate(newGradient)
            }
            return
        }

        windowState.activeGradient = newGradient

        guard activeWindowState?.id == windowState.id else { return }

        if animate {
            gradientColorManager.transition(from: previousGradient, to: newGradient)
        } else {
            gradientColorManager.setImmediate(newGradient)
        }
    }

    func refreshGradientsForSpace(_ space: Space, animate: Bool) {
        for (_, state) in windowStates where state.currentSpaceId == space.id {
            updateGradient(for: state, to: space.gradient, animate: animate && activeWindowState?.id == state.id)
        }
    }

    private func adoptProfileIfNeeded(for windowState: BrowserWindowState, context: ProfileSwitchContext) {
        guard let targetProfileId = windowState.currentProfileId else { return }
        guard !isSwitchingProfile else { return }
        guard currentProfile?.id != targetProfileId else { return }
        guard let targetProfile = profileManager.profiles.first(where: { $0.id == targetProfileId }) else { return }
        Task { [weak self] in
            await self?.switchToProfile(targetProfile, context: context, in: windowState)
            await MainActor.run {
                if let activeId = self?.activeWindowState?.id, activeId == windowState.id {
                    self?.activeWindowState?.currentProfileId = targetProfileId
                }
            }
        }
    }

    func compositorContainers() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleIdentifiers: [UUID] = []
        for (windowId, entry) in compositorContainerViews {
            if let view = entry.view {
                result.append((windowId, view))
            } else {
                staleIdentifiers.append(windowId)
            }
        }
        for id in staleIdentifiers {
            compositorContainerViews.removeValue(forKey: id)
        }
        return result
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
        self.settingsManager = SettingsManager()
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
        self.compositorManager.setUnloadTimeout(self.settingsManager.tabUnloadTimeout)
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
        bindTabManagerUpdates()
        if #available(macOS 15.5, *), let mgr = self.extensionManager {
            // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
            mgr.attach(browserManager: self)
            if let pid = currentProfile?.id {
                mgr.switchProfile(pid)
            }
        }
        if let g = self.tabManager.currentSpace?.gradient {
            self.gradientColorManager.setImmediate(g)
        } else {
        self.gradientColorManager.setImmediate(.default)
        }
        self.trackingProtectionManager.attach(browserManager: self)
        self.trackingProtectionManager.setEnabled(self.settingsManager.blockCrossSiteTracking)
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

    // MARK: - OAuth Assist Controls
    func maybeShowOAuthAssist(for url: URL, in tab: Tab) {
        // Only when protection is enabled and not already disabled for this tab
        guard settingsManager.blockCrossSiteTracking, trackingProtectionManager.isEnabled else { return }
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

    private func isLikelyOAuthURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        // Common IdP hosts
        let hostHints = [
            "accounts.google.com", "login.microsoftonline.com", "login.live.com",
            "appleid.apple.com", "github.com", "gitlab.com", "bitbucket.org",
            "auth0.com", "okta.com", "onelogin.com", "pingidentity.com",
            "slack.com", "zoom.us", "login.cloudflareaccess.com"
        ]
        if hostHints.contains(where: { host.contains($0) }) { return true }
        // Common OAuth paths and signals
        if path.contains("/oauth") || path.contains("oauth2") || path.contains("/authorize") || path.contains("/signin") || path.contains("/login") || path.contains("/callback") { return true }
        if query.contains("client_id=") || query.contains("redirect_uri=") || query.contains("response_type=") { return true }
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

    func switchToProfile(_ profile: Profile, context: ProfileSwitchContext = .userInitiated, in windowState: BrowserWindowState? = nil) async {
        await profileOps.run { [weak self] in
            guard let self else { return }
            if self.isSwitchingProfile {
                print("⏳ [BrowserManager] Ignoring concurrent profile switch request")
                return
            }
            self.isSwitchingProfile = true
            defer { self.isSwitchingProfile = false }

            let previousProfile = self.currentProfile
            print("🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")")
            let animateTransition = context.shouldAnimateTransition

            let performUpdates = {
                if animateTransition {
                    self.isTransitioningProfile = true
                } else {
                    self.isTransitioningProfile = false
                }
                self.currentProfile = profile
                self.activeWindowState?.currentProfileId = profile.id
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
                self.showProfileSwitchToast(from: previousProfile, to: profile, in: windowState ?? self.activeWindowState)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
            }

            if animateTransition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.isTransitioningProfile = false
                }
            }
        }
    }
    
    func updateSidebarWidth(_ width: CGFloat) {
        if let activeWindow = activeWindowState {
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
        if activeWindowState?.id == windowState.id {
            sidebarWidth = width
            savedSidebarWidth = width
            sidebarContentWidth = max(width - 16, 0)
        }
    }
    
    func saveSidebarWidthToDefaults() {
        saveSidebarSettings()
    }

    func toggleSidebar() {
        if let windowState = activeWindowState {
            toggleSidebar(for: windowState)
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                isSidebarVisible.toggle()
                if isSidebarVisible {
                    sidebarWidth = savedSidebarWidth
                    sidebarContentWidth = max(savedSidebarWidth - 16, 0)
                } else {
                    savedSidebarWidth = sidebarWidth
                    sidebarWidth = 0
                    sidebarContentWidth = 0
                }
            }
            saveSidebarSettings()
        }
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        withAnimation(.easeInOut(duration: 0.1)) {
            windowState.isSidebarVisible.toggle()
            if windowState.isSidebarVisible {
                let restoredWidth = windowState.savedSidebarWidth
                windowState.sidebarWidth = restoredWidth
                windowState.sidebarContentWidth = max(restoredWidth - 16, 0)
            } else {
                windowState.savedSidebarWidth = max(windowState.sidebarWidth, 0)
                windowState.sidebarWidth = 0
                windowState.sidebarContentWidth = 0
            }
        }
        if activeWindowState?.id == windowState.id {
            isSidebarVisible = windowState.isSidebarVisible
            sidebarWidth = windowState.sidebarWidth
            savedSidebarWidth = windowState.savedSidebarWidth
            sidebarContentWidth = windowState.sidebarContentWidth
        }
        saveSidebarSettings()
    }
    
    // MARK: - Sidebar width access for overlays
    /// Returns the last saved sidebar width (used when sidebar is collapsed to size hover overlay)
    func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        if let state = windowState {
            return state.savedSidebarWidth
        }
        if let active = activeWindowState {
            return active.savedSidebarWidth
        }
        return savedSidebarWidth
    }

    // MARK: - Command Palette
    private func showCommandPalette(in windowState: BrowserWindowState, prefill: String, navigateCurrentTab: Bool) {
        for state in windowStates.values where state.id != windowState.id {
            state.isCommandPaletteVisible = false
            state.isMiniCommandPaletteVisible = false
        }

        windowState.commandPalettePrefilledText = prefill
        windowState.shouldNavigateCurrentTab = navigateCurrentTab
        windowState.isMiniCommandPaletteVisible = false
        DispatchQueue.main.async {
            windowState.isCommandPaletteVisible = true
        }

        commandPalettePrefilledText = prefill
        shouldNavigateCurrentTab = navigateCurrentTab
        isMiniCommandPaletteVisible = false
        isCommandPaletteVisible = true
    }

    func openCommandPalette() {
        guard let target = activeWindowState ?? windowStates.values.first else {
            commandPalettePrefilledText = ""
            shouldNavigateCurrentTab = false
            isMiniCommandPaletteVisible = false
            DispatchQueue.main.async { self.isCommandPaletteVisible = true }
            return
        }
        showCommandPalette(in: target, prefill: "", navigateCurrentTab: false)
    }

    /// Opens the full command palette prefilled with the current tab's URL,
    /// with Return navigating the current tab (not creating a new one).
    func openCommandPaletteWithCurrentURL() {
        guard let target = activeWindowState ?? windowStates.values.first else {
            openCommandPalette()
            return
        }
        let prefill = currentTab(for: target)?.url.absoluteString ?? ""
        showCommandPalette(in: target, prefill: prefill, navigateCurrentTab: true)
    }

    func closeCommandPalette(for windowState: BrowserWindowState? = nil) {
        let targets: [BrowserWindowState]
        if let windowState {
            targets = [windowState]
        } else {
            targets = Array(windowStates.values)
        }

        for state in targets {
            state.isCommandPaletteVisible = false
            state.isMiniCommandPaletteVisible = false
            state.shouldNavigateCurrentTab = false
            state.commandPalettePrefilledText = ""
        }

        if windowState == nil || windowState?.id == activeWindowState?.id {
            isCommandPaletteVisible = false
            isMiniCommandPaletteVisible = false
            shouldNavigateCurrentTab = false
            commandPalettePrefilledText = ""
        }
    }
    
    func toggleTopBarAddressView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            settingsManager.topBarAddressView.toggle()
        }
    }
    
    func toggleCommandPalette() {
        if let target = activeWindowState {
            if target.isCommandPaletteVisible {
                closeCommandPalette(for: target)
            } else {
                openCommandPalette()
            }
        } else {
            openCommandPalette()
        }
    }

    private func showMiniCommandPalette(in windowState: BrowserWindowState, prefill: String) {
        for state in windowStates.values where state.id != windowState.id {
            state.isMiniCommandPaletteVisible = false
        }

        windowState.commandPalettePrefilledText = prefill
        windowState.shouldNavigateCurrentTab = true
        windowState.isCommandPaletteVisible = false
        DispatchQueue.main.async {
            windowState.isMiniCommandPaletteVisible = true
        }

        commandPalettePrefilledText = prefill
        shouldNavigateCurrentTab = true
        isCommandPaletteVisible = false
        isMiniCommandPaletteVisible = true
    }

    func hideMiniCommandPalette(for windowState: BrowserWindowState? = nil) {
        let targets: [BrowserWindowState]
        if let windowState {
            targets = [windowState]
        } else {
            targets = Array(windowStates.values)
        }

        for state in targets {
            state.isMiniCommandPaletteVisible = false
            state.shouldNavigateCurrentTab = false
            state.commandPalettePrefilledText = ""
        }

        if windowState == nil || windowState?.id == activeWindowState?.id {
            isMiniCommandPaletteVisible = false
            shouldNavigateCurrentTab = false
            commandPalettePrefilledText = ""
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
        let targetSpace = windowState.currentSpaceId.flatMap { id in
            tabManager.spaces.first(where: { $0.id == id })
        } ?? windowState.currentProfileId.flatMap { pid in
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
        let targetSpace = activeWindowState?.currentSpaceId.flatMap { id in
            tabManager.spaces.first(where: { $0.id == id })
        } ?? tabManager.currentSpace
        
        // Get the current tab's index to place the duplicate below it
        let currentTabIndex = tabManager.tabs.firstIndex(where: { $0.id == currentTab.id }) ?? 0
        let insertIndex = currentTabIndex + 1
        
        // Create a new tab with the same URL and name
        let newTab = Tab(
            url: currentTab.url,
            name: currentTab.name,
            favicon: "globe", // Will be updated by fetchAndSetFavicon
            spaceId: targetSpace?.id,
            index: 0, // Will be set correctly after insertion
            browserManager: self
        )
        
        // Add the tab to the current space (it will be added at the end)
        tabManager.addTab(newTab)
        
        // Now move it to the correct position (right below the current tab)
        if let spaceId = targetSpace?.id {
            tabManager.reorderRegular(newTab, in: spaceId, to: insertIndex)
        }
        
        // Set as active tab in the current window
        if let windowState = activeWindowState {
            selectTab(newTab, in: windowState)
        } else {
            selectTab(newTab)
        }
        
        print("🔧 [BrowserManager] Duplicated tab created: \(newTab.name) - \(newTab.url) at index \(insertIndex)")
    }

    func closeCurrentTab() {
        if let activeWindow = activeWindowState,
           (activeWindow.isCommandPaletteVisible || activeWindow.isMiniCommandPaletteVisible) {
            closeCommandPalette(for: activeWindow)
            return
        }
        // Close tab in the active window
        if let activeWindow = activeWindowState,
           let currentTab = currentTab(for: activeWindow) {
            tabManager.removeTab(currentTab.id)
        } else {
            // Fallback to global current tab for backward compatibility
            tabManager.closeActiveTab()
        }
    }

    func focusURLBar() {
        // Open the mini palette anchored to the URL bar
        // Pre-fill with current tab's URL and set to navigate current tab
        guard let target = activeWindowState ?? windowStates.values.first else { return }
        let prefill = currentTab(for: target)?.url.absoluteString ?? ""
        showMiniCommandPalette(in: target, prefill: prefill)
    }

    // MARK: - Dialog Methods
    
    func showQuitDialog() {
        if(self.settingsManager.askBeforeQuit) {
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
    
    func showCustomDialog<Header: View, Body: View, Footer: View>(
        header: Header,
        body: Body,
        footer: Footer
    ) {
        dialogManager.showDialog(header: header, body: body, footer: footer)
    }
    
    func showCustomDialog<Body: View, Footer: View>(
        body: Body,
        footer: Footer
    ) {
        dialogManager.showDialog(body: body, footer: footer)
    }
    
    func showCustomDialog<Body: View>(
        body: Body
    ) {
        dialogManager.showDialog(body: body)
    }
    
    func showCustomContentDialog<Content: View>(
        header: AnyView?,
        content: Content,
        footer: AnyView?
    ) {
        dialogManager.showCustomContentDialog(header: header, content: content, footer: footer)
    }
    
    // MARK: - Appearance / Gradient Editing
    private final class GradientDraft: ObservableObject {
        @Published var value: SpaceGradient
        init(_ value: SpaceGradient) { self.value = value }
    }

    func showGradientEditor() {
        guard let space = tabManager.currentSpace else {
            // Consistent in-app dialog when no space is available
            let header = AnyView(
                DialogHeader(
                    icon: "paintpalette",
                    title: "No Space Available",
                    subtitle: "Create a space to customize its gradient."
                )
            )
            let footer = AnyView(
                DialogFooter(rightButtons: [
                    DialogButton(text: "OK", variant: .primary) { [weak self] in
                        self?.closeDialog()
                    }
                ])
            )
            showCustomContentDialog(header: header, content: Color.clear.frame(height: 0), footer: footer)
            return
        }

        let draft = GradientDraft(space.gradient)
        let binding = Binding<SpaceGradient>(
            get: { draft.value },
            set: { draft.value = $0 }
        )

        // Compact dialog: remove header icon/title to save vertical space
        let header: AnyView? = nil

        let content = GradientEditorView(gradient: binding)
            .environmentObject(self.gradientColorManager)

        let footer = AnyView(
            DialogFooter(
                leftButton: DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: { [weak self] in
                        // Restore background to the saved gradient for this space
                        self?.gradientColorManager.endInteractivePreview()
                        self?.gradientColorManager.transition(to: space.gradient, duration: 0.25)
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
                            // Commit draft to the current space and persist
                            space.gradient = draft.value
                            // End interactive editing then morph to the committed gradient
                            self?.gradientColorManager.endInteractivePreview()
                            self?.gradientColorManager.transition(to: draft.value, duration: 0.35)
                            self?.refreshGradientsForSpace(space, animate: true)
                            self?.tabManager.persistSnapshot()
                            self?.closeDialog()
                        }
                    )
                ]
            )
        )

        showCustomContentDialog(
            header: header,
            content: content,
            footer: footer
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
              let host = currentTab.url.host else { return }
        
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
              let host = currentTab.url.host else { return }
        
        Task {
            await cacheManager.clearCacheForDomain(host)
        }
    }
    
    /// Clears site cache for current page excluding cookies, then reloads from origin.
    func hardReloadCurrentPage() {
        guard let currentTab = currentTabForActiveWindow(),
              let host = currentTab.url.host,
              let activeWindowId = activeWindowState?.id else { return }
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
        guard let _ = currentProfile?.id else { return }
        print("🧹 [BrowserManager] Clearing cache for current profile")
        Task { await cacheManager.clearAllCache() }
    }

    func clearAllProfilesCookies() {
        print("🧹 [BrowserManager] Clearing cookies for ALL profiles (sequential, isolated)")
        let profiles = profileManager.profiles
        Task { @MainActor in
            for profile in profiles {
                let cm = CookieManager(dataStore: profile.dataStore)
                print("   → Clearing cookies for profile=\(profile.id.uuidString) [\(profile.name)]")
                await cm.deleteAllCookies()
            }
        }
    }

    func performPrivacyCleanupAllProfiles() {
        print("🧹 [BrowserManager] Performing privacy cleanup across ALL profiles (sequential, isolated)")
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
            print("🔧 [BrowserManager] Assigned default profile to \(updated) legacy history entries")
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
        if let activeWindow = activeWindowState {
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
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.didCopyURL = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    self.didCopyURL = false
                }
            }
        } else {
            print("No URL found to copy")
        }
    }
    
    // MARK: - Web Inspector
    func openWebInspector() {
        guard let currentTab = currentTabForActiveWindow(),
              let activeWindowId = activeWindowState?.id else {
            print("No current tab to inspect")
            return
        }

        if #available(macOS 13.3, *) {
            // Use the WebView that's actually visible in the current window
            let webView: WKWebView
            if let windowWebView = getWebView(for: currentTab.id, in: activeWindowId) {
                webView = windowWebView
            } else {
                webView = currentTab.activeWebView
            }

            if webView.isInspectable {
                DispatchQueue.main.async {
                    // Focus the webview and trigger context menu programmatically
                    self.presentInspectorContextMenu(for: webView)
                }
            } else {
                print("Web inspector not available for this tab")
            }
        } else {
            print("Web inspector requires macOS 13.3 or later")
        }
    }

    private func presentInspectorContextMenu(for webView: WKWebView) {
        // Focus the webview first
        webView.window?.makeFirstResponder(webView)

        // Create a right-click event at the center of the webview
        let bounds = webView.bounds
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        let rightClickEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: center,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: webView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )

        if let event = rightClickEvent {
            webView.rightMouseDown(with: event)
        }
    }

    // MARK: - Profile Switch Toast
    func showProfileSwitchToast(from: Profile?, to: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? activeWindowState else { return }
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
        guard let window = windowState ?? activeWindowState else { return }
        hideProfileSwitchToast(forWindowId: window.id)
    }

    private func hideProfileSwitchToast(forWindowId windowId: UUID) {
        guard let window = windowStates[windowId] ?? (activeWindowState?.id == windowId ? activeWindowState : nil) else { return }
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
            WKWebsiteDataTypeServiceWorkerRegistrations
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
        migrationProgress = MigrationProgress(currentStep: "Copying cookies…", progress: 0.0, totalSteps: 3, currentStepIndex: 1)
        let defaultStore = WKWebsiteDataStore.default()

        let cookies = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            defaultStore.httpCookieStore.getAllCookies { cookies in cont.resume(returning: cookies) }
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
                    self.migrationProgress?.progress = Double(copied) / Double(total) * (1.0/3.0)
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
        for i in 1...10 { // 10 ticks
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 80_000_000) // 80ms per tick
            migrationProgress?.progress = (1.0/3.0) + Double(i)/10.0 * (1.0/3.0)
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
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: .distantPast) {
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
        migrationProgress = MigrationProgress(currentStep: "Preparing…", progress: 0.0, totalSteps: 3, currentStepIndex: 0)
        migrationTask = Task { @MainActor in
            do {
                if Task.isCancelled { self.resetMigrationState(); return }
                try await migrateCookiesToCurrentProfile()
                if Task.isCancelled { self.resetMigrationState(); return }
                try await migrateCacheToCurrentProfile()
                if Task.isCancelled { self.resetMigrationState(); return }
                await clearSharedDataAfterMigration()
                let header = AnyView(DialogHeader(icon: "checkmark.seal", title: "Migration Complete", subtitle: currentProfile?.name ?? ""))
                let body = AnyView(Text("Your shared data has been migrated to the current profile.").font(.body))
                let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { self.dialogManager.closeDialog() }]))
                self.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
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
        if let cp = currentProfile, profileManager.profiles.first(where: { $0.id == cp.id }) == nil {
            print("⚠️ [BrowserManager] Current profile invalid; falling back to first available")
            currentProfile = profileManager.profiles.first
        }
        // Ensure spaces have profile assignments
        tabManager.validateTabProfileAssignments()
    }

    func recoverFromProfileError(_ error: Error, profile: Profile?) {
        print("❗️[BrowserManager] Profile operation failed: \(error)")
        // Fallback to default/first profile
        if let first = profileManager.profiles.first { Task { await switchToProfile(first, context: .recovery) } }
        // Show dialog
        let header = AnyView(DialogHeader(icon: "exclamationmark.triangle", title: "Profile Error", subtitle: profile?.name ?? ""))
        let body = AnyView(Text("An error occurred while performing a profile operation. Your session has been switched to a safe profile.").font(.body))
        let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { self.dialogManager.closeDialog() }]))
        dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
    }

    // MARK: - Profile Deletion Coordinator
    func deleteProfile(_ profile: Profile) {
        // Avoid deleting the last profile
        guard profileManager.profiles.count > 1 else {
            let header = AnyView(DialogHeader(icon: "exclamationmark.triangle", title: "Cannot Delete Last Profile", subtitle: profile.name))
            let body = AnyView(Text("At least one profile must remain.").font(.body))
            let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { self.dialogManager.closeDialog() }]))
            dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
            return
        }
        Task { @MainActor in
            // Choose replacement if current is being deleted
            if self.currentProfile?.id == profile.id {
                if let replacement = self.profileManager.profiles.first(where: { $0.id != profile.id }) {
                    await self.switchToProfile(replacement)
                }
            }

            // Cleanup references and data
            self.tabManager.cleanupProfileReferences(profile.id)
            await profile.clearAllData()

            // Delete from manager
            let ok = self.profileManager.deleteProfile(profile)
            if !ok {
                let header = AnyView(DialogHeader(icon: "exclamationmark.triangle", title: "Couldn't Delete Profile", subtitle: profile.name))
                let body = AnyView(Text("An error occurred while saving changes. Please try again.").font(.body))
                let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { self.dialogManager.closeDialog() }]))
                self.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
            }
        }
    }

    /// Presents an external URL in a mini window popup (for URL events)
    func presentExternalURL(_ url: URL) {
        externalMiniWindowManager.present(url: url)
    }
    
    // MARK: - Window State Management
    
    /// Register a new window state
    func registerWindowState(_ windowState: BrowserWindowState) {
        // Initialize window state with current global state for backward compatibility
        windowState.sidebarWidth = sidebarWidth
        windowState.sidebarContentWidth = max(sidebarWidth - 16, 0)
        windowState.isSidebarVisible = isSidebarVisible
        windowState.savedSidebarWidth = savedSidebarWidth
        windowState.isCommandPaletteVisible = false
        windowState.isMiniCommandPaletteVisible = false
        windowState.didCopyURL = false
        windowState.commandPalettePrefilledText = ""
        windowState.shouldNavigateCurrentTab = false

        // Set the NSWindow reference for keyboard shortcuts
        if let window = NSApplication.shared.windows.first(where: { $0.contentView?.subviews.contains(where: {
            ($0 as? NSHostingView<ContentView>) != nil
        }) ?? false }) {
            windowState.window = window
        }
        windowState.urlBarFrame = urlBarFrame
        windowState.activeGradient = tabManager.currentSpace?.gradient ?? .default
        windowState.currentProfileId = currentProfile?.id

        // Set initial tab and space
        windowState.currentTabId = tabManager.currentTab?.id
        windowState.currentSpaceId = tabManager.currentSpace?.id
        if let spaceId = windowState.currentSpaceId,
           let space = tabManager.spaces.first(where: { $0.id == spaceId }) {
            windowState.currentProfileId = space.profileId ?? currentProfile?.id
            windowState.activeGradient = space.gradient
        }
        
        windowStates[windowState.id] = windowState
        setActiveWindowState(windowState)
        
        print("🪟 [BrowserManager] Registered window state: \(windowState.id)")
    }
    
    /// MEMORY LEAK FIX: Comprehensive cleanup for a specific window
    func unregisterWindowState(_ windowId: UUID) {
        guard let windowState = windowStates[windowId] else { return }

        print("🧹 [BrowserManager] Starting comprehensive cleanup for window: \(windowId)")

        closeCommandPalette(for: windowState)

        // MEMORY LEAK FIX: Enhanced cleanup for window-specific web views
        cleanupWebViewsForWindow(windowId)
        
        // Clean up split state for this window
        splitManager.cleanupWindow(windowId)
        removeCompositorContainerView(for: windowId)
        
        windowStates.removeValue(forKey: windowId)
        
        // If this was the active window, switch to another window
        if activeWindowState?.id == windowId {
            if let newActive = windowStates.values.first {
                setActiveWindowState(newActive)
            } else {
                activeWindowState = nil
                splitManager.refreshPublishedState(for: windowId)
                isCommandPaletteVisible = false
                isMiniCommandPaletteVisible = false
                commandPalettePrefilledText = ""
                shouldNavigateCurrentTab = false
            }
        }

        print("✅ [BrowserManager] Completed comprehensive cleanup for window: \(windowId)")
    }
    
    /// MEMORY LEAK FIX: Comprehensive cleanup for all WebViews in a specific window
    private func cleanupWebViewsForWindow(_ windowId: UUID) {
        let webViewsToCleanup = webViewsByTabAndWindow.compactMap { (tabId, windowWebViews) -> (UUID, WKWebView)? in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (tabId, webView)
        }
        
        print("🧹 [BrowserManager] Cleaning up \(webViewsToCleanup.count) WebViews for window \(windowId)")
        
        for (tabId, webView) in webViewsToCleanup {
            // Use comprehensive cleanup from Tab class
            if let tab = tabManager.allTabs().first(where: { $0.id == tabId }) {
                tab.cleanupCloneWebView(webView)
            } else {
                // Fallback cleanup if tab is not found
                performFallbackWebViewCleanup(webView, tabId: tabId)
            }
            
            // Remove from containers
            removeWebViewFromContainers(webView)
            
            // Remove from tracking
            webViewsByTabAndWindow[tabId]?.removeValue(forKey: windowId)
            if webViewsByTabAndWindow[tabId]?.isEmpty == true {
                webViewsByTabAndWindow.removeValue(forKey: tabId)
            }
            
            print("✅ [BrowserManager] Cleaned up WebView for tab \(tabId) in window \(windowId)")
        }
    }
    
    /// MEMORY LEAK FIX: Fallback cleanup for WebViews when tab is not available
    private func performFallbackWebViewCleanup(_ webView: WKWebView, tabId: UUID) {
        print("🧹 [BrowserManager] Performing fallback WebView cleanup for tab: \(tabId)")
        
        // Stop loading
        webView.stopLoading()
        
        // Remove all message handlers
        let controller = webView.configuration.userContentController
        let allMessageHandlers = [
            "linkHover",
            "commandHover", 
            "commandClick",
            "pipStateChange",
            "mediaStateChange_\(tabId.uuidString)",
            "backgroundColor_\(tabId.uuidString)",
            "historyStateDidChange",
            "NookIdentity"
        ]
        
        for handlerName in allMessageHandlers {
            controller.removeScriptMessageHandler(forName: handlerName)
        }
        
        // Clear delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        // Remove from view hierarchy
        webView.removeFromSuperview()
        
        print("✅ [BrowserManager] Fallback WebView cleanup completed for tab: \(tabId)")
    }
    
    /// MEMORY LEAK FIX: Comprehensive cleanup for all WebViews across all windows
    func cleanupAllWebViews() {
        print("🧹 [BrowserManager] Starting comprehensive cleanup for ALL WebViews")
        
        let totalWebViews = webViewsByTabAndWindow.values.flatMap { $0.values }.count
        print("🧹 [BrowserManager] Cleaning up \(totalWebViews) WebViews across all windows")
        
        // Clean up all WebViews for all tabs in all windows
        for (tabId, windowWebViews) in webViewsByTabAndWindow {
            for (windowId, webView) in windowWebViews {
                // Use comprehensive cleanup from Tab class
                if let tab = tabManager.allTabs().first(where: { $0.id == tabId }) {
                    tab.cleanupCloneWebView(webView)
                } else {
                    // Fallback cleanup if tab is not found
                    performFallbackWebViewCleanup(webView, tabId: tabId)
                }
                
                // Remove from containers
                removeWebViewFromContainers(webView)
                
                print("✅ [BrowserManager] Cleaned up WebView for tab \(tabId) in window \(windowId)")
            }
        }
        
        // Clear all tracking
        webViewsByTabAndWindow.removeAll()
        compositorContainerViews.removeAll()
        
        print("✅ [BrowserManager] Completed comprehensive cleanup for ALL WebViews")
    }

    /// Set the active window state (called when a window gains focus)
    func setActiveWindowState(_ windowState: BrowserWindowState) {
        activeWindowState = windowState
        sidebarWidth = windowState.sidebarWidth
        savedSidebarWidth = windowState.savedSidebarWidth
        sidebarContentWidth = windowState.sidebarContentWidth
        isSidebarVisible = windowState.isSidebarVisible
        urlBarFrame = windowState.urlBarFrame
        gradientColorManager.setImmediate(windowState.activeGradient)
        splitManager.refreshPublishedState(for: windowState.id)
        isCommandPaletteVisible = windowState.isCommandPaletteVisible
        isMiniCommandPaletteVisible = windowState.isMiniCommandPaletteVisible
        commandPalettePrefilledText = windowState.commandPalettePrefilledText
        shouldNavigateCurrentTab = windowState.shouldNavigateCurrentTab
        if windowState.currentProfileId == nil {
            windowState.currentProfileId = currentProfile?.id
        }
        adoptProfileIfNeeded(for: windowState, context: .windowActivation)
        if let currentId = windowState.currentTabId,
           let tab = tabManager.allTabs().first(where: { $0.id == currentId }) {
            enforceExclusiveAudio(for: tab, activeWindowId: windowState.id)
        }
    }
    
    // MARK: - Window-Aware Tab Operations
    
    /// Get the current tab for a specific window
    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        guard let tabId = windowState.currentTabId else { return nil }
        return tabManager.allTabs().first { $0.id == tabId }
    }
    
    /// Select a tab in the active window (convenience method for sidebar clicks)
    func selectTab(_ tab: Tab) {
        guard let activeWindow = activeWindowState else {
            print("⚠️ [BrowserManager] No active window for tab selection")
            return
        }
        selectTab(tab, in: activeWindow)
    }
    
    /// Select a tab in a specific window
    func selectTab(_ tab: Tab, in windowState: BrowserWindowState) {
        windowState.currentTabId = tab.id
        
        // Update space if the tab belongs to a different space
        if let spaceId = tab.spaceId, windowState.currentSpaceId != spaceId {
            windowState.currentSpaceId = spaceId
        }
        
        // Remember this tab as active for the current space in this window
        if let currentSpaceId = windowState.currentSpaceId {
            windowState.activeTabForSpace[currentSpaceId] = tab.id
        }

        if let spaceId = windowState.currentSpaceId,
           let space = tabManager.spaces.first(where: { $0.id == spaceId }) {
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

        enforceExclusiveAudio(for: tab, activeWindowId: windowState.id)

        print("🪟 [BrowserManager] Selected tab \(tab.name) in window \(windowState.id)")

        // Update global tab state for the active window
        if activeWindowState?.id == windowState.id {
            // Only update the global state, don't trigger UI operations again
            tabManager.updateActiveTabState(tab)
        }
    }
    
    /// Get tabs that should be displayed in a specific window
    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        print("🔍 tabsForDisplay called for window \(windowState.id.uuidString.prefix(8))...")

        // Get tabs for the window's current space
        let currentSpace = windowState.currentSpaceId.flatMap { id in
            tabManager.spaces.first(where: { $0.id == id })
        }

        print("   - windowState.currentSpaceId: \(windowState.currentSpaceId?.uuidString ?? "nil")")
        print("   - resolved currentSpace: \(currentSpace?.name ?? "nil") (id: \(currentSpace?.id.uuidString.prefix(8) ?? "nil"))")

        let profileId = windowState.currentProfileId ?? currentSpace?.profileId ?? currentProfile?.id
        let essentials = profileId.flatMap { tabManager.essentialTabs(for: $0) } ?? []
        let spacePinned = currentSpace.map { tabManager.spacePinnedTabs(for: $0.id) } ?? []
        let regularTabs = currentSpace.map { tabManager.tabs(in: $0) } ?? []

        print("   - essentials: \(essentials.count) tabs")
        print("   - spacePinned: \(spacePinned.count) tabs")
        print("   - regularTabs: \(regularTabs.count) tabs")

        print("   - spacePinned tabs details:")
        for tab in spacePinned {
            print("     * \(tab.name) (id: \(tab.id.uuidString.prefix(8))..., folderId: \(tab.folderId?.uuidString.prefix(8) ?? "nil"))")
        }

        let result = essentials + spacePinned + regularTabs
        print("   - TOTAL tabsForDisplay: \(result.count)")

        return result
    }
    
    /// Check if a tab is frozen (being displayed in another window)
    /// Note: This is no longer needed since each window shows its own current tab independently
    func isCurrentTabFrozen(in windowState: BrowserWindowState) -> Bool {
        return false // Always false since windows are independent
    }
    
    /// Refresh compositor for a specific window
    func refreshCompositor(for windowState: BrowserWindowState) {
        windowState.refreshCompositor()
    }
    
    /// Get a web view for a specific tab in a specific window
    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        return webViewsByTabAndWindow[tabId]?[windowId]
    }
    
    /// Get all web views for a specific tab across all windows
    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        return webViewsByTabAndWindow[tabId]?.values.map { $0 } ?? []
    }
    
    /// Create a new web view for a specific tab in a specific window
    func createWebView(for tabId: UUID, in windowId: UUID) -> WKWebView {
        // Get the tab
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }) else {
            fatalError("Tab not found: \(tabId)")
        }
        
        // Create a new web view configuration based on the tab's original web view
        let configuration = WKWebViewConfiguration()
        
        // Copy configuration from the original tab's web view if it exists
        if let originalWebView = tab.webView {
            configuration.websiteDataStore = originalWebView.configuration.websiteDataStore
            // CRITICAL: Copy all preferences including PiP settings
            configuration.preferences = originalWebView.configuration.preferences
            configuration.defaultWebpagePreferences = originalWebView.configuration.defaultWebpagePreferences
            configuration.mediaTypesRequiringUserActionForPlayback = originalWebView.configuration.mediaTypesRequiringUserActionForPlayback
            configuration.allowsAirPlayForMediaPlayback = originalWebView.configuration.allowsAirPlayForMediaPlayback
            configuration.applicationNameForUserAgent = originalWebView.configuration.applicationNameForUserAgent
            if #available(macOS 15.5, *) {
                configuration.webExtensionController = originalWebView.configuration.webExtensionController
            }
        } else {
            // Use the tab's resolved profile data store and apply proper configuration
            let resolvedProfile = tab.resolveProfile()
            configuration.websiteDataStore = resolvedProfile?.dataStore ?? WKWebsiteDataStore.default()
            
            // Apply the same configuration as BrowserConfiguration
            let preferences = WKWebpagePreferences()
            preferences.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences = preferences
            
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.allowsAirPlayForMediaPlayback = true
            configuration.applicationNameForUserAgent = "Version/17.4.1 Safari/605.1.15"
            
            // CRITICAL: Enable Picture-in-Picture
            configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
            
            // CRITICAL: Enable full-screen API support
            configuration.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
            configuration.preferences.setValue(true, forKey: "mediaDevicesEnabled")
            
            // CRITICAL: Enable HTML5 Fullscreen API
            configuration.preferences.isElementFullscreenEnabled = true
            
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        
        // Create the new web view
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.setValue(false, forKey: "drawsBackground")
        
        // Set up message handlers
        newWebView.configuration.userContentController.add(tab, name: "linkHover")
        newWebView.configuration.userContentController.add(tab, name: "commandHover")
        newWebView.configuration.userContentController.add(tab, name: "commandClick")
        newWebView.configuration.userContentController.add(tab, name: "pipStateChange")
        newWebView.configuration.userContentController.add(tab, name: "mediaStateChange_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "backgroundColor_\(tabId.uuidString)")
        newWebView.configuration.userContentController.add(tab, name: "historyStateDidChange")
        newWebView.configuration.userContentController.add(tab, name: "NookIdentity")

        tab.setupThemeColorObserver(for: newWebView)
        
        // Load the same URL as the original tab
        if let url = URL(string: tab.url.absoluteString) {
            newWebView.load(URLRequest(url: url))
        }
        newWebView.isMuted = tab.isAudioMuted
        
        // Store the web view
        if webViewsByTabAndWindow[tabId] == nil {
            webViewsByTabAndWindow[tabId] = [:]
        }
        webViewsByTabAndWindow[tabId]?[windowId] = newWebView

        if let activeId = activeWindowState?.id {
            enforceExclusiveAudio(for: tab, activeWindowId: activeId)
        } else {
            enforceExclusiveAudio(for: tab, activeWindowId: windowId)
        }

        print("🪟 [BrowserManager] Created new web view for tab \(tab.name) in window \(windowId)")
        return newWebView
    }

    

    /// Synchronize a tab's state across all windows that are displaying it
    func syncTabAcrossWindows(_ tabId: UUID) {
        // Prevent recursive sync calls
        guard !isSyncingTab.contains(tabId) else {
            print("🪟 [BrowserManager] Skipping recursive sync for tab \(tabId)")
            return
        }
        
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }) else { return }
        
        isSyncingTab.insert(tabId)
        defer { isSyncingTab.remove(tabId) }
        
        // Get all web views for this tab across all windows
        let allWebViews: [WKWebView]
        if let webViews = webViewsByTabAndWindow[tabId] {
            allWebViews = Array(webViews.values)
        } else {
            allWebViews = []
        }
        
        for webView in allWebViews {
            // Sync the URL if it's different
            let currentURL = tab.url
            if webView.url != currentURL {
                webView.load(URLRequest(url: currentURL))
            }
            
            // Sync other state as needed (loading state, etc.)
            // Note: Navigation state (back/forward) is handled by the Tab's navigationDelegate
        }
        
        print("🪟 [BrowserManager] Synchronized tab \(tab.name) across \(allWebViews.count) windows")
    }
    
    /// Navigate a tab across all windows that are displaying it
    func navigateTabAcrossWindows(_ tabId: UUID, to url: URL) {
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }) else { return }
        
        // Update the tab's URL
        tab.url = url
        
        // Get all web views for this tab across all windows
        let allWebViews: [WKWebView]
        if let webViews = webViewsByTabAndWindow[tabId] {
            allWebViews = Array(webViews.values)
        } else {
            allWebViews = []
        }
        
        for webView in allWebViews {
            webView.load(URLRequest(url: url))
        }
        
        print("🪟 [BrowserManager] Navigated tab \(tab.name) to \(url.absoluteString) across \(allWebViews.count) windows")
    }
    
    /// Reload a tab across all windows that are displaying it
    func reloadTabAcrossWindows(_ tabId: UUID) {
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }) else { return }
        
        // Get all web views for this tab across all windows
        let allWebViews: [WKWebView]
        if let webViews = webViewsByTabAndWindow[tabId] {
            allWebViews = Array(webViews.values)
        } else {
            allWebViews = []
        }
        
        for webView in allWebViews {
            webView.reload()
        }
        
        print("🪟 [BrowserManager] Reloaded tab \(tab.name) across \(allWebViews.count) windows")
    }
    
    /// Apply mute state to all window-specific web views for a tab
    func setMuteState(_ muted: Bool, for tabId: UUID, originatingWindowId: UUID?) {
        guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }) else { return }
        if let origin = originatingWindowId {
            enforceExclusiveAudio(for: tab, activeWindowId: origin, desiredMuteState: muted)
        } else if let webViews = webViewsByTabAndWindow[tabId] {
            for webView in webViews.values {
                webView.isMuted = muted
            }
        }
    }
    
    /// Set active space for a specific window
    func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {
        let isActiveWindow = activeWindowState?.id == windowState.id
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
        let profileEssentials = (space.profileId ?? currentProfile?.id).flatMap { tabManager.essentialTabs(for: $0) } ?? []
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

        print("🪟 [BrowserManager] Set active space \(space.name) for window \(windowState.id), active tab: \(targetTab?.name ?? "none")")
    }
    
    /// Validate and fix window states after tab/space mutations
    func validateWindowStates() {
        for (_, windowState) in windowStates {
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
                    print("🔧 [validateWindowStates] Using TabManager's current tab: \(managerCurrentTab.name)")
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
               let space = tabManager.spaces.first(where: { $0.id == spaceId }) {
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
                self.tabManager.createSpace(name: space.title, icon: space.icon ?? "person")
                
                guard let createdSpace = self.tabManager.spaces.first(where: { $0.name == space.title }) else {
                    continue
                }
                
                for tab in space.tabs {
                    self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                }
            }
            
            for topTab in result.topTabs {
                let tab = self.tabManager.createNewTab(url: topTab.url, in: self.tabManager.spaces.first!)
                self.tabManager.addToEssentials(tab)
            }
        }
    }

    // MARK: - Keyboard Shortcut Support Methods

    /// Select the next tab in the active window
    func selectNextTabInActiveWindow() {
        guard let activeWindow = activeWindowState else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id }) else { return }

        let nextIndex = (currentIndex + 1) % currentTabs.count
        if let nextTab = currentTabs[safe: nextIndex] {
            selectTab(nextTab, in: activeWindow)
        }
    }

    /// Select the previous tab in the active window
    func selectPreviousTabInActiveWindow() {
        guard let activeWindow = activeWindowState else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id }) else { return }

        let previousIndex = currentIndex > 0 ? currentIndex - 1 : currentTabs.count - 1
        if let previousTab = currentTabs[safe: previousIndex] {
            selectTab(previousTab, in: activeWindow)
        }
    }

    /// Select tab by index in the active window
    func selectTabByIndexInActiveWindow(_ index: Int) {
        guard let activeWindow = activeWindowState else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard currentTabs.indices.contains(index) else { return }

        let tab = currentTabs[index]
        selectTab(tab, in: activeWindow)
    }

    /// Select the last tab in the active window
    func selectLastTabInActiveWindow() {
        guard let activeWindow = activeWindowState else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let lastTab = currentTabs.last else { return }

        selectTab(lastTab, in: activeWindow)
    }

    /// Select the next space in the active window
    func selectNextSpaceInActiveWindow() {
        guard let activeWindow = activeWindowState,
              let currentSpaceId = activeWindow.currentSpaceId,
              let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId }) else { return }

        let nextIndex = (currentSpaceIndex + 1) % tabManager.spaces.count
        if let nextSpace = tabManager.spaces[safe: nextIndex] {
            setActiveSpace(nextSpace, in: activeWindow)
        }
    }

    /// Select the previous space in the active window
    func selectPreviousSpaceInActiveWindow() {
        guard let activeWindow = activeWindowState,
              let currentSpaceId = activeWindow.currentSpaceId,
              let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId }) else { return }

        let previousIndex = currentSpaceIndex > 0 ? currentSpaceIndex - 1 : tabManager.spaces.count - 1
        if let previousSpace = tabManager.spaces[safe: previousIndex] {
            setActiveSpace(previousSpace, in: activeWindow)
        }
    }

    /// Create a new window
    func createNewWindow() {
        // This is handled by the Command+N shortcut in NookApp.swift
        // For consistency, we'll trigger the same menu action
        // Create new window using the same approach as NookApp.swift
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentView = NSHostingView(rootView: ContentView()
            .background(BackgroundWindowModifier())
            .ignoresSafeArea(.all)
            .environmentObject(self))
        newWindow.title = "Nook"
        newWindow.minSize = NSSize(width: 470, height: 382)
        newWindow.contentMinSize = NSSize(width: 470, height: 382)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// Close the active window
    func closeActiveWindow() {
        guard let activeWindow = activeWindowState?.window else { return }
        activeWindow.close()
    }

    /// Toggle full screen for the active window
    func toggleFullScreenForActiveWindow() {
        guard let activeWindow = activeWindowState?.window else { return }
        activeWindow.toggleFullScreen(nil)
    }

    /// Show downloads (placeholder implementation)
    func showDownloads() {
        // TODO: Implement downloads UI
        openCommandPaletteWithCurrentURL()
    }

    /// Show history (placeholder implementation)
    func showHistory() {
        // TODO: Implement history UI
        openCommandPaletteWithCurrentURL()
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
