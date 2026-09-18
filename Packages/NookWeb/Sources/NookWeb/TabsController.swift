//
//  TabsController.swift
//  Nook
//
//  The app side of the tab model. Owns the TabTree, DeviceState, TabStore and the live page
//  sessions, and exposes the intents the sidebar, commands, extensions and AI tools call.
//  Window selection lives on BrowserWindowState and is mirrored into DeviceState.windows.
//  Private windows keep their own in-memory tree and sessions on BrowserWindowState.
//

import Foundation
import NookBlocker
import NookSettings
import NookTabsCore
import NookTweaks
import OSLog
import WebKit

@MainActor
@Observable
public final class TabsController {
    public enum Placement { case newTab, background, replaceCurrent }

    public static let homeURL = URL(string: "https://www.google.com")!
    static let undoLimit = 100

    // MARK: - State

    public private(set) var tree: TabTree
    public private(set) var device: DeviceState
    public let loadOutcome: LoadOutcome
    public let directory: URL
    var isReadOnly: Bool {
        if case .readOnly = loadOutcome { return true }
        return false
    }

    /// Sessions for items in the main tree, by item id. Private sessions live on their window.
    private var liveSessions: [UUID: PageSession] = [:]
    /// The window that last selected or claimed each page. A page has one live view; other
    /// windows showing the same item show a placeholder instead. In memory only.
    private var pageOwners: [UUID: UUID] = [:]
    /// Open folders of private windows, kept apart so their ids never reach device.json.
    private var privateOpenFolders: Set<UUID> = []

    /// One `Profile` (website data store) per space, made on first use and kept for the session.
    @ObservationIgnored private var spaceProfiles: [UUID: Profile] = [:]

    @ObservationIgnored private let store: TabStore
    @ObservationIgnored private(set) var undoStack: [Change] = []
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored public let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Tabs")

    // MARK: - Injected

    @ObservationIgnored public let settings: NookSettingsService
    @ObservationIgnored public let windowRegistry: WindowRegistry
    @ObservationIgnored public let blocker: ContentBlockerManager
    @ObservationIgnored public let sponsorBlock: SponsorBlockManager
    @ObservationIgnored public let siteRouting: SiteRoutingManager
    /// Set once the SwiftData context has produced it; nil in a host without history.
    @ObservationIgnored public var history: HistoryManager?
    @ObservationIgnored public weak var webViews: WebViewProvider?
    @ObservationIgnored public weak var sessionDelegate: PageSessionDelegate?
    @ObservationIgnored public weak var tabEvents: TabEventObserver?
    @ObservationIgnored public weak var alerts: AlertPresenter?

    nonisolated public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nook", isDirectory: true)
            .appendingPathComponent("Tabs", isDirectory: true)
    }

    // MARK: - Load

    public init(
        settings: NookSettingsService,
        windowRegistry: WindowRegistry,
        blocker: ContentBlockerManager,
        sponsorBlock: SponsorBlockManager,
        siteRouting: SiteRoutingManager,
        history: HistoryManager? = nil,
        legacyProfiles: [(id: UUID, name: String)] = [],
        directory: URL = TabsController.defaultDirectory
    ) {
        self.settings = settings
        self.windowRegistry = windowRegistry
        self.blocker = blocker
        self.sponsorBlock = sponsorBlock
        self.siteRouting = siteRouting
        self.history = history
        self.directory = directory
        let store = TabStore(directory: directory)
        self.store = store
        let loaded = store.load()
        loadOutcome = loaded.outcome
        switch loaded.outcome {
        case .firstLaunch, .readOnly:
            // Read-only still needs a working sidebar; the store writes nothing this session.
            tree = Self.seed(from: legacyProfiles)
            device = DeviceState()
            device.firstLaunchCompleted = true
        case .loaded, .restoredFromBackup:
            tree = loaded.tree
            device = loaded.device
            // A quit ends every page, so pinned tabs and favorites start at their home URL again.
            device.openPages = [:]
        }
        log.info("Tabs loaded: \(String(describing: loaded.outcome), privacy: .public), \(self.tree.items.count) items")
        if case .readOnly(let reason) = loaded.outcome {
            log.error("Tabs are read-only: \(reason, privacy: .public)")
        }
        if case .firstLaunch = loaded.outcome { save() }
        if !loaded.migratedSpaceIDs.isEmpty {
            log.info("Merged profiles into \(self.tree.orderedSpaces.count) spaces")
        }
    }

    /// One space per profile left over from before spaces owned their data (same UUID, so each
    /// WKWebsiteDataStore keeps its cookies and logins), each with one tab.
    public static func seed(from legacyProfiles: [(id: UUID, name: String)], now: Date = Date()) -> TabTree {
        guard !legacyProfiles.isEmpty else { return TabTree.firstLaunch(homeURL: homeURL, now: now) }
        var tree = TabTree()
        for profile in legacyProfiles {
            tree.createSpace(id: profile.id, name: profile.name, icon: "house", accentHex: "#7C7C7C",
                             after: tree.orderedSpaces.last?.id, now: now)
            do {
                try tree.createTab(url: homeURL, title: "Google", in: .tabs(spaceID: profile.id), after: nil, now: now)
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Tabs").error("Seeding space failed: \(String(describing: error), privacy: .public)")
            }
        }
        return tree
    }

    // MARK: - Save and Undo

    public func save() {
        store.save(tree, device)
    }

    /// Writes now, with every regular window's current frame. Called at quit; windows closing
    /// afterwards keep their records so they all reopen.
    public func flushSync() {
        isTerminating = true
        for window in regularWindows { mirror(window) }
        store.save(tree, device)
        store.flush()
    }

    func pushUndo(_ change: Change) {
        guard !change.isEmpty else { return }
        undoStack.append(change)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
    }

    /// Where an item or space lives.
    enum Owner {
        case main
        case privateWindow(BrowserWindowState)
    }

    public var allWindows: [BrowserWindowState] {
        Array(windowRegistry.windows.values)
    }

    public var privateWindows: [BrowserWindowState] { allWindows.filter { $0.privateTree != nil } }

    public var regularWindows: [BrowserWindowState] { allWindows.filter { $0.privateTree == nil } }

    func owner(ofItem id: UUID) -> Owner? {
        if tree.item(id) != nil { return .main }
        return privateWindows.first { $0.privateTree?.item(id) != nil }.map(Owner.privateWindow)
    }

    func owner(ofSpace id: UUID) -> Owner? {
        if tree.space(id) != nil { return .main }
        return privateWindows.first { $0.privateTree?.space(id) != nil }.map(Owner.privateWindow)
    }

    func owner(of window: BrowserWindowState) -> Owner {
        window.privateTree != nil ? .privateWindow(window) : .main
    }

    func tree(_ owner: Owner) -> TabTree {
        switch owner {
        case .main: return tree
        case .privateWindow(let window): return window.privateTree ?? TabTree()
        }
    }

    /// Runs one tree edit. Main-tree edits push their undo change and save; private edits never save.
    /// Tree errors are logged and leave state unchanged.
    @discardableResult
    func perform(_ owner: Owner, _ label: String, undoable: Bool = true, _ body: (inout TabTree) throws -> Change) -> Change? {
        do {
            switch owner {
            case .main:
                var copy = tree
                let change = try body(&copy)
                tree = copy
                if undoable { pushUndo(change) }
                device.prune(against: tree)
                save()
                return change
            case .privateWindow(let window):
                var copy = window.privateTree ?? TabTree()
                let change = try body(&copy)
                window.privateTree = copy
                return change
            }
        } catch {
            log.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Reads

    public func space(_ id: UUID) -> SpaceRecord? {
        owner(ofSpace: id).flatMap { tree($0).space(id) }
    }

    public var orderedSpaces: [SpaceRecord] { tree.orderedSpaces }

    /// The spaces a window can move a tab to: its own temporary one when private, else all of them.
    public func spaces(visibleIn window: BrowserWindowState?) -> [SpaceRecord] {
        guard let window else { return orderedSpaces }
        return tree(owner(of: window)).orderedSpaces
    }

    public func item(_ id: UUID) -> Item? {
        owner(ofItem: id).flatMap { tree($0).item(id) }
    }

    public func children(of parent: Parent) -> [Item] {
        treeHolding(parent).children(of: parent)
    }

    public func favorites(of spaceID: UUID) -> [Item] {
        children(of: .favorites(spaceID: spaceID))
    }

    public func rows(space spaceID: UUID) -> [Row] {
        guard let owner = owner(ofSpace: spaceID) else { return [] }
        return tree(owner).visibleRows(space: spaceID, openFolders: openFolders(owner))
    }

    public func section(of itemID: UUID) -> Parent? {
        owner(ofItem: itemID).flatMap { tree($0).section(of: itemID) }
    }

    public func spaceID(of itemID: UUID) -> UUID? {
        owner(ofItem: itemID).flatMap { tree($0).spaceID(of: itemID) }
    }

    /// Live tabs in every section of a space: its favorites, pinned tabs and tabs.
    public func items(inSpace spaceID: UUID) -> [Item] {
        guard let owner = owner(ofSpace: spaceID) else { return [] }
        let source = tree(owner)
        return source.items.values.filter { item in
            item.deletedAt == nil && !item.isFolder && source.spaceID(of: item.id) == spaceID
        }
    }

    public func isOpen(folder: UUID) -> Bool {
        device.openFolders.contains(folder) || privateOpenFolders.contains(folder)
    }

    /// A synced tab whose open page's host and path differ from its home URL.
    public func hasLeftHome(_ itemID: UUID) -> Bool {
        guard let owner = owner(ofItem: itemID), let item = tree(owner).item(itemID),
              tree(owner).scope(of: itemID) == .synced, let home = item.url else { return false }
        let current: URL?
        switch owner {
        case .main: current = device.openPages[itemID]?.url ?? liveSessions[itemID]?.url
        case .privateWindow(let window): current = window.privateSessions[itemID]?.url
        }
        guard let current else { return false }
        return current.host?.lowercased() != home.host?.lowercased() || Self.normalizedPath(current) != Self.normalizedPath(home)
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    var canReopenClosed: Bool { !device.closed.isEmpty }

    func treeHolding(_ parent: Parent) -> TabTree {
        switch parent {
        case .favorites(let spaceID), .pinned(let spaceID), .tabs(let spaceID):
            return owner(ofSpace: spaceID).map(tree) ?? tree
        case .folder(let itemID):
            return owner(ofItem: itemID).map(tree) ?? tree
        }
    }

    func openFolders(_ owner: Owner) -> Set<UUID> {
        switch owner {
        case .main: return device.openFolders
        case .privateWindow: return privateOpenFolders
        }
    }

    // MARK: - Sessions

    public func session(for itemID: UUID) -> PageSession? {
        if let session = liveSessions[itemID] { return session }
        for window in privateWindows {
            if let session = window.privateSessions[itemID] { return session }
        }
        return nil
    }

    public var sessions: [PageSession] {
        Array(liveSessions.values) + privateWindows.flatMap { $0.privateSessions.values }
    }

    public func session(for webView: WKWebView) -> PageSession? {
        let coordinator = webViews
        return sessions.first { session in
            session.webView === webView
                || coordinator?.allWebViews(for: session.itemID).contains(where: { $0 === webView }) == true
        }
    }

    public func selectedItemID(in window: BrowserWindowState) -> UUID? {
        window.selectedItemID
    }

    public func selectedSession(in window: BrowserWindowState) -> PageSession? {
        window.selectedItemID.flatMap { session(for: $0) }
    }

    /// The active window's selected page, when that window holds the live page. Commands never
    /// reach a page another window holds; the user moves it first.
    public var activeWindowSession: PageSession? {
        windowRegistry.activeWindow.flatMap { controllableSession(in: $0) }
    }

    /// The window's selected page for actions (navigation, reload, find, zoom): nil while another
    /// window holds it. Display code uses `selectedSession(in:)`.
    public func controllableSession(in window: BrowserWindowState) -> PageSession? {
        guard let session = selectedSession(in: window), !isPageShownElsewhere(session.itemID, from: window) else { return nil }
        return session
    }

    /// Favorites of the window's space, then its rows in sidebar order.
    public func displayOrder(in window: BrowserWindowState) -> [UUID] {
        guard let spaceID = window.spaceID else { return [] }
        let favorites = tree(owner(of: window)).favorites(of: spaceID).map(\.id)
        return favorites + rows(space: spaceID).filter { !$0.item.isFolder }.map(\.item.id)
    }

    public func isVisibleInAnyWindow(_ itemID: UUID) -> Bool {
        allWindows.contains { window in
            window.selectedItemID == itemID
                || window.split?.leftItemID == itemID
                || window.split?.rightItemID == itemID
        }
    }

    /// The session for an item, created when missing. A synced item opens its saved open page,
    /// else its home URL.
    public func ensureSession(for itemID: UUID) -> PageSession? {
        if let existing = session(for: itemID) { return existing }
        guard let owner = owner(ofItem: itemID), let item = tree(owner).item(itemID),
              case .tab(let homeURL, let pageTitle) = item.kind else { return nil }
        switch owner {
        case .main:
            let synced = tree.scope(of: itemID) == .synced
            let page = synced ? device.openPages[itemID] : nil
            let session = PageSession(
                itemID: itemID, url: page?.url ?? homeURL, title: page?.title ?? pageTitle,
                isPrivate: false, controller: self)
            liveSessions[itemID] = session
            if synced, page == nil {
                setOpenPage(itemID, OpenPage(url: homeURL, title: pageTitle))
            }
            return session
        case .privateWindow(let window):
            let session = PageSession(
                itemID: itemID, url: homeURL, title: pageTitle,
                isPrivate: true, controller: self)
            window.privateSessions[itemID] = session
            return session
        }
    }

    /// Removes and tears down a session without touching the tree.
    func endSession(_ itemID: UUID) {
        let session: PageSession?
        if let main = liveSessions.removeValue(forKey: itemID) {
            session = main
        } else if let window = privateWindows.first(where: { $0.privateSessions[itemID] != nil }) {
            session = window.privateSessions.removeValue(forKey: itemID)
        } else {
            session = nil
        }
        device.openPages[itemID] = nil
        guard let session else { return }
        session.tearDown()
        if !session.isPrivate {
            tabEvents?.tabClosed(itemID: itemID)
        }
    }

    /// The website data store of a space, made on first use. Its name and icon follow the space.
    public func profile(forSpace spaceID: UUID) -> Profile? {
        guard let space = tree.space(spaceID) else { return nil }
        if let existing = spaceProfiles[spaceID] {
            existing.name = space.name
            existing.icon = space.icon
            return existing
        }
        let profile = Profile(id: spaceID, name: space.name, icon: space.icon)
        spaceProfiles[spaceID] = profile
        return profile
    }

    /// Every space's data store, made if it does not exist yet. For whole-app cleanup only.
    var allSpaceProfiles: [Profile] {
        tree.orderedSpaces.compactMap { profile(forSpace: $0.id) }
    }

    /// Drops the cached data store of a deleted space.
    func forgetProfile(_ spaceID: UUID) {
        spaceProfiles[spaceID] = nil
    }

    /// The data store a session's page uses: the private window's ephemeral one, else the store
    /// of the space that owns the item's section.
    public func profile(for session: PageSession) -> Profile? {
        if session.isPrivate {
            return privateWindows.first { $0.privateSessions[session.itemID] === session }?.ephemeralProfile
        }
        if let id = tree.spaceID(of: session.itemID), let profile = profile(forSpace: id) {
            return profile
        }
        return sessionDelegate?.currentProfile ?? tree.orderedSpaces.first.flatMap { profile(forSpace: $0.id) }
    }

    /// The window a session's actions belong to: its private window, else the active window
    /// when that window can show the item, else a window selecting it, else the active window.
    public func window(for session: PageSession) -> BrowserWindowState? {
        if session.isPrivate {
            return privateWindows.first { $0.privateSessions[session.itemID] === session }
        }
        let active = windowRegistry.activeWindow
        if let active, active.privateTree == nil, canShow(session.itemID, in: active) { return active }
        if let selecting = regularWindows.first(where: { $0.selectedItemID == session.itemID }) { return selecting }
        return active?.privateTree == nil ? active : regularWindows.first
    }

    func canShow(_ itemID: UUID, in window: BrowserWindowState) -> Bool {
        let source = tree(owner(of: window))
        guard source.item(itemID) != nil else { return false }
        return source.spaceID(of: itemID) == window.spaceID
    }

    // MARK: - Page Ownership

    private func shows(_ itemID: UUID, in window: BrowserWindowState) -> Bool {
        window.selectedItemID == itemID || window.split?.leftItemID == itemID || window.split?.rightItemID == itemID
    }

    /// The window that shows the item's live page: the last window to select or claim it while
    /// still showing it, else the active window if it shows it, else any window showing it.
    public func pageOwnerWindow(of itemID: UUID) -> BrowserWindowState? {
        let showing = allWindows.filter { shows(itemID, in: $0) }
        if let id = pageOwners[itemID], let owner = showing.first(where: { $0.id == id }) { return owner }
        let activeID = windowRegistry.activeWindowId
        return showing.first(where: { $0.id == activeID }) ?? showing.first
    }

    /// True when `window` shows the item but another window holds its live page.
    public func isPageShownElsewhere(_ itemID: UUID, from window: BrowserWindowState) -> Bool {
        guard let owner = pageOwnerWindow(of: itemID) else { return false }
        return owner.id != window.id
    }

    /// Moves the item's live page to `window`.
    public func takeControl(_ itemID: UUID, in window: BrowserWindowState) {
        pageOwners[itemID] = window.id
        refreshWindows(showing: itemID)
    }

    /// Brings forward the window holding the item's live page.
    public func showOwnerWindow(of itemID: UUID) {
        pageOwnerWindow(of: itemID)?.windowHandle?.bringToFront()
    }

    public func refreshWindows(showing itemID: UUID) {
        for window in allWindows
        where window.selectedItemID == itemID || window.split?.leftItemID == itemID || window.split?.rightItemID == itemID {
            window.refreshCompositor()
        }
    }

    // MARK: - Page Reports

    /// A committed navigation or SPA URL change. Device items store it as their URL; synced items
    /// keep their home URL and store the open page instead.
    func pageCommitted(itemID: UUID, url: URL) {
        guard let owner = owner(ofItem: itemID) else { return }
        guard tree(owner).scope(of: itemID) == .synced else {
            perform(owner, "setURL", undoable: false) { try $0.setURL(itemID, url) }
            return
        }
        // Private windows keep no open-page state.
        guard case .main = owner, device.openPages[itemID]?.url != url else { return }
        let title = liveSessions[itemID]?.title ?? device.openPages[itemID]?.title ?? ""
        device.openPages[itemID] = OpenPage(url: url, title: title)
        save()
    }

    func pageTitleChanged(itemID: UUID, title: String) {
        guard let owner = owner(ofItem: itemID) else { return }
        if case .main = owner, tree.scope(of: itemID) == .synced {
            guard var page = device.openPages[itemID], page.title != title else { return }
            page.title = title
            device.openPages[itemID] = page
            save()
            return
        }
        perform(owner, "setPageTitle", undoable: false) { try $0.setPageTitle(itemID, title) }
    }

    // MARK: - Device State Edits

    func setOpenPage(_ itemID: UUID, _ page: OpenPage?) {
        guard device.openPages[itemID] != page else { return }
        device.openPages[itemID] = page
        save()
    }

    /// Main-tree folders are remembered in device.json; private ones only in memory.
    func setFolder(_ folderID: UUID, open: Bool) {
        guard let owner = owner(ofItem: folderID) else { return }
        switch owner {
        case .main:
            if open { device.openFolders.insert(folderID) } else { device.openFolders.remove(folderID) }
            save()
        case .privateWindow:
            if open { privateOpenFolders.insert(folderID) } else { privateOpenFolders.remove(folderID) }
        }
    }

    func recordClosed(_ entry: ClosedEntry) {
        device.pushClosed(entry)
        save()
    }

    /// Removes reopen entries holding any of `ids` (items that are back in the tree).
    func dropClosed(containing ids: Set<UUID>) {
        let count = device.closed.count
        device.closed.removeAll { entry in entry.items.contains { ids.contains($0.id) } }
        if device.closed.count != count { save() }
    }

    func dropLastClosed() {
        guard !device.closed.isEmpty else { return }
        device.closed.removeLast()
        save()
    }

    func addSession(_ session: PageSession) {
        liveSessions[session.itemID] = session
    }

    // MARK: - Windows

    /// Sets up a newly registered window: a private window gets its own tree; a regular window
    /// takes an unclaimed saved window record, else the first space. Loads no pages.
    public func attach(window: BrowserWindowState) {
        if window.isIncognito, window.ephemeralProfile != nil {
            if window.privateTree == nil {
                // One temporary space, never written to disk. Its pages use the window's
                // ephemeral data store, not one keyed by this id.
                var privateTree = TabTree()
                let spaceID = UUID()
                privateTree.createSpace(id: spaceID, name: "Private", icon: "eyeglasses", accentHex: "#3A3A3C", after: nil)
                window.privateTree = privateTree
                window.spaceID = spaceID
            }
            return
        }
        let claimed = Set(regularWindows.map(\.id)).subtracting([window.id])
        if let index = device.windows.firstIndex(where: { $0.id == window.id })
            ?? device.windows.firstIndex(where: { !claimed.contains($0.id) }) {
            let record = device.windows[index]
            window.spaceID = record.spaceID.flatMap { tree.space($0)?.id }
            window.selectedItemBySpace = record.selectedItemBySpace.filter { tree.item($0.value) != nil }
            window.split = record.split
            window.pendingFrame = record.frame
            window.applyPendingFrame()
            device.windows[index].id = window.id
        }
        if window.spaceID == nil {
            window.spaceID = tree.orderedSpaces.first?.id
        }
        if let spaceID = window.spaceID, window.selectedItemBySpace[spaceID] == nil,
           let first = displayOrder(in: window).first {
            window.selectedItemBySpace[spaceID] = first
        }
        mirror(window)
    }

    /// A window closed. Private windows end their pages; a regular window's record is dropped
    /// unless it is the last one, so the last window reopens as it was.
    public func detach(window: BrowserWindowState) {
        if window.privateTree != nil {
            for itemID in Array(window.privateSessions.keys) { endSession(itemID) }
            window.privateTree = nil
            return
        }
        let others = regularWindows.filter { $0.id != window.id }
        guard !isTerminating, !others.isEmpty else { return }
        device.windows.removeAll { $0.id == window.id }
        save()
    }

    /// Saved window records no open regular window has claimed; the app opens a window for each.
    public func unclaimedWindowRecords() -> [WindowRecord] {
        let open = Set(regularWindows.map(\.id))
        return device.windows.filter { !open.contains($0.id) }
    }

    /// Copies a regular window's selection into DeviceState.windows.
    public func mirror(_ window: BrowserWindowState) {
        guard window.privateTree == nil else { return }
        let record = WindowRecord(
            id: window.id, spaceID: window.spaceID, selectedItemBySpace: window.selectedItemBySpace,
            split: window.split, frame: window.windowHandle?.frameString)
        if let index = device.windows.firstIndex(where: { $0.id == window.id }) {
            guard device.windows[index] != record else { return }
            device.windows[index] = record
        } else {
            device.windows.append(record)
        }
        save()
    }
}
