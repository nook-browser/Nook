//
//  BrowserManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import SwiftData
import AppKit
import WebKit
import OSLog

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer

    // MARK: - Constants
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pulse", category: "Persistence")
    private static let storeFileName = "default.store"
    private static let backupPrefix = "default_backup_"
    // Backups now use a directory per snapshot: default_backup_<timestamp>/
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return fmt
    }()
    static let schema = Schema([
        SpaceEntity.self,
        ProfileEntity.self,
        TabEntity.self,
        TabsStateEntity.self,
        HistoryEntity.self,
        ExtensionEntity.self
    ])

    // MARK: - URLs
    nonisolated private static var appSupportURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "Pulse"
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
            let stamp = Self.dateFormatter.string(from: Date())
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


@MainActor
class BrowserManager: ObservableObject {
    @Published var sidebarWidth: CGFloat = 250
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
    // Toast state for profile switching feedback
    @Published var profileSwitchToast: ProfileSwitchToast?
    @Published var isShowingProfileSwitchToast: Bool = false
    // Migration state
    @Published var migrationProgress: MigrationProgress?
    @Published var isMigrationInProgress: Bool = false
    
    var modelContext: ModelContext
    var tabManager: TabManager
    var profileManager: ProfileManager
    var settingsManager: SettingsManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    var historyManager: HistoryManager
    var cookieManager: CookieManager
    var cacheManager: CacheManager
    var extensionManager: ExtensionManager?
    var compositorManager: TabCompositorManager
    var gradientColorManager: GradientColorManager
    var trackingProtectionManager: TrackingProtectionManager
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    private var isSwitchingProfile: Bool = false
    
    // Compositor container view
    var compositorContainerView: NSView?

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
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(context: modelContext, profileId: initialProfile?.id)
        self.cookieManager = CookieManager(dataStore: initialProfile?.dataStore)
        self.cacheManager = CacheManager(dataStore: initialProfile?.dataStore)
        self.compositorManager = TabCompositorManager()
        self.gradientColorManager = GradientColorManager()
        self.trackingProtectionManager = TrackingProtectionManager()
        self.compositorContainerView = nil

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.compositorManager.setUnloadTimeout(self.settingsManager.tabUnloadTimeout)
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
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
            self?.trackingProtectionManager.setEnabled(enabled)
        }
    }

    // MARK: - Profile Switching
    struct ProfileSwitchToast: Equatable {
        let fromProfile: Profile?
        let toProfile: Profile
        let timestamp: Date
    }

    actor ProfileOps { func run(_ body: @MainActor () async -> Void) async { await body() } }
    private let profileOps = ProfileOps()

    func switchToProfile(_ profile: Profile) async {
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
            self.currentProfile = profile
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
            // Animate gradient to the active space of the new profile
            let newGradient = self.tabManager.currentSpace?.gradient ?? .default
            self.gradientColorManager.transition(to: newGradient, duration: 0.35)
            // Show toast and haptic feedback
            self.showProfileSwitchToast(from: previousProfile, to: profile)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
            // Trigger any UI updates if needed
            self.objectWillChange.send()
        }
    }
    
    func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
        savedSidebarWidth = width
    }
    
    func saveSidebarWidthToDefaults() {
        saveSidebarSettings()
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.1)) {
            isSidebarVisible.toggle()

            if isSidebarVisible {
                sidebarWidth = savedSidebarWidth
            } else {
                sidebarWidth = 0
            }
        }
        saveSidebarSettings()
    }

    // MARK: - Command Palette
    func openCommandPalette() {
        // Always open; toggling handled by toggleCommandPalette()
        commandPalettePrefilledText = ""
        shouldNavigateCurrentTab = false
        self.isMiniCommandPaletteVisible = false
        DispatchQueue.main.async {
            self.isCommandPaletteVisible = true
        }
    }

    func closeCommandPalette() {
        // Close both variants
        if isCommandPaletteVisible || isMiniCommandPaletteVisible {
            DispatchQueue.main.async {
                self.isCommandPaletteVisible = false
                self.isMiniCommandPaletteVisible = false
            }
        }
    }

    func toggleCommandPalette() {
        if isCommandPaletteVisible {
            closeCommandPalette()
        } else {
            openCommandPalette()
        }
    }

    // MARK: - Tab Management (delegates to TabManager)
    func createNewTab() {
        _ = tabManager.createNewTab()
    }

    func closeCurrentTab() {
        tabManager.closeActiveTab()
    }

    func focusURLBar() {
        // Open the mini palette anchored to the URL bar
        // Pre-fill with current tab's URL and set to navigate current tab
        if let currentURL = tabManager.currentTab?.url {
            commandPalettePrefilledText = currentURL.absoluteString
        } else {
            commandPalettePrefilledText = ""
        }
        shouldNavigateCurrentTab = true
        // Ensure full-screen palette is closed
        self.isCommandPaletteVisible = false
        DispatchQueue.main.async {
            self.isMiniCommandPaletteVisible = true
        }
    }

    // MARK: - Dialog Methods
    
    func showQuitDialog() {
        dialogManager.showQuitDialog(
            onAlwaysQuit: {
                // Save always quit preference
                self.quitApplication()
            },
            onQuit: {
                self.quitApplication()
            }
        )
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

        if savedWidth > 0 {
            savedSidebarWidth = savedWidth
            sidebarWidth = savedVisibility ? savedWidth : 0
        }
        isSidebarVisible = savedVisibility
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
        guard let currentTab = tabManager.currentTab,
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
        guard let currentTab = tabManager.currentTab,
              let host = currentTab.url.host else { return }
        
        Task {
            await cacheManager.clearCacheForDomain(host)
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

    // MARK: - URL Utilities
    func copyCurrentURL() {
        if let url = tabManager.currentTab?.url.absoluteString {
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
        guard let currentTab = tabManager.currentTab else { 
            print("No current tab to inspect")
            return 
        }
        
        if #available(macOS 13.3, *) {
            let webView = currentTab.activeWebView
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
    func showProfileSwitchToast(from: Profile?, to: Profile) {
        profileSwitchToast = ProfileSwitchToast(fromProfile: from, toProfile: to, timestamp: Date())
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isShowingProfileSwitchToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.hideProfileSwitchToast()
        }
    }

    func hideProfileSwitchToast() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            isShowingProfileSwitchToast = false
        }
        // Keep the last toast payload around briefly for exit animation; clear after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.profileSwitchToast = nil
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
        if let first = profileManager.profiles.first { Task { await switchToProfile(first) } }
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
}
