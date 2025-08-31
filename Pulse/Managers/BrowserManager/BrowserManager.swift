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
    
    var modelContext: ModelContext
    var tabManager: TabManager
    var settingsManager: SettingsManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    var historyManager: HistoryManager
    var cookieManager: CookieManager
    var cacheManager: CacheManager
    var extensionManager: ExtensionManager?
    var compositorManager: TabCompositorManager
    var gradientColorManager: GradientColorManager
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    
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
        self.tabManager = TabManager(browserManager: nil, context: modelContext)
        self.settingsManager = SettingsManager()
        self.dialogManager = DialogManager()
        self.downloadManager = DownloadManager.shared
        self.historyManager = HistoryManager(context: modelContext)
        self.cookieManager = CookieManager()
        self.cacheManager = CacheManager()
        self.compositorManager = TabCompositorManager()
        self.gradientColorManager = GradientColorManager()
        self.compositorContainerView = nil

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.compositorManager.setUnloadTimeout(self.settingsManager.tabUnloadTimeout)
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
        if #available(macOS 15.5, *), let mgr = self.extensionManager {
            // Attach extension manager BEFORE any WKWebView is created so content scripts can inject
            mgr.attach(browserManager: self)
        }
        if let g = self.tabManager.currentSpace?.gradient {
            self.gradientColorManager.setImmediate(g)
        } else {
            self.gradientColorManager.setImmediate(.default)
        }
        loadSidebarSettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabUnloadTimeoutChange),
            name: .tabUnloadTimeoutChanged,
            object: nil
        )
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
        if isCommandPaletteVisible { 
                   DispatchQueue.main.async {
            self.isCommandPaletteVisible = false
        } 
         } else {
        // Clear prefilled text and set to create new tab
        commandPalettePrefilledText = ""
        shouldNavigateCurrentTab = false
        // Ensure mini palette is closed when opening full palette
        self.isMiniCommandPaletteVisible = false
        DispatchQueue.main.async {
            self.isCommandPaletteVisible = true
        }
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
}
