import AppKit
import Observation
import SwiftData
import WebKit

@MainActor
@Observable
class TabManager {
    weak var browserManager: BrowserManager?
    private let context: ModelContext

    // Spaces
    public private(set) var spaces: [Space] = []
    public private(set) var currentSpace: Space?

    // Normal tabs per space
    private var tabsBySpace: [UUID: [Tab]] = [:]

    // Pinned tabs (global)
    private(set) var pinnedTabs: [Tab] = []

    // Currently active tab
    private(set) var currentTab: Tab?

    init(browserManager: BrowserManager? = nil, context: ModelContext) {
        self.browserManager = browserManager
        self.context = context
        loadFromStore()
    }

    // MARK: - Convenience

    var tabs: [Tab] {
        guard let s = currentSpace else { return [] }
        return (tabsBySpace[s.id] ?? []).sorted { $0.index < $1.index }
    }

    private func setTabs(_ items: [Tab], for spaceId: UUID) {
        tabsBySpace[spaceId] = items
    }

    private func attach(_ tab: Tab) {
        tab.browserManager = browserManager
    }

    private func allTabsAllSpaces() -> [Tab] {
        let normals = spaces.flatMap { tabsBySpace[$0.id] ?? [] }
        return pinnedTabs + normals
    }

    private func contains(_ tab: Tab) -> Bool {
        if pinnedTabs.contains(where: { $0.id == tab.id }) { return true }
        if let sid = tab.spaceId, let arr = tabsBySpace[sid] {
            return arr.contains(where: { $0.id == tab.id })
        }
        return false
    }

    // MARK: - Space Management
    @discardableResult
    func createSpace(name: String, icon: String = "square.grid.2x2") -> Space {
        let space = Space(name: name, icon: icon)
        spaces.append(space)
        tabsBySpace[space.id] = []
        if currentSpace == nil { currentSpace = space } else { setActiveSpace(space) }
        persistSnapshot()
        return space
    }

    func removeSpace(_ id: UUID) {
        guard let idx = spaces.firstIndex(where: { $0.id == id }) else {
            return
        }
        // Move tabs out or close them; here we close normal tabs of the space
        let closing = tabsBySpace[id] ?? []
        for t in closing {
            if currentTab?.id == t.id { currentTab = nil }
        }
        tabsBySpace[id] = []
        spaces.remove(at: idx)
        if currentSpace?.id == id {
            currentSpace = spaces.first
        }
        persistSnapshot()
    }

    func setActiveSpace(_ space: Space) {
        guard spaces.contains(where: { $0.id == space.id }) else { return }
        let previousTab = currentTab
        currentSpace = space

        let inSpace = tabsBySpace[space.id] ?? []

        if let ct = currentTab {
            if let sid = ct.spaceId, sid != space.id {
                currentTab = inSpace.first ?? pinnedTabs.first
            } else if ct.spaceId == nil {
                if currentTab == nil, let first = inSpace.first {
                    currentTab = first
                }
            }
        } else {
            currentTab = inSpace.first ?? pinnedTabs.first
        }

        // Pick a new current tab if needed
        persistSnapshot()
        // Notify extensions about activation change across spaces
        if #available(macOS 15.4, *), let newActive = currentTab {
            ExtensionManager.shared.notifyTabActivated(newTab: newActive, previous: previousTab)
        }
    }

    func renameSpace(spaceId: UUID, newName: String) {
        guard let idx = spaces.firstIndex(where: { $0.id == spaceId }) else {
            return
        }

        spaces[idx].name = newName

        if currentSpace?.id == spaceId {
            currentSpace?.name = newName
        }

        persistSnapshot()
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
        print("Added tab: \(tab.name) to space \(sid)")
        persistSnapshot()
    }

    func removeTab(_ id: UUID) {
        let wasCurrent = (currentTab?.id == id)
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        for space in spaces {
            if var arr = tabsBySpace[space.id],
                let i = arr.firstIndex(where: { $0.id == id })
            {
                removed = arr.remove(at: i)
                removedIndexInCurrentSpace =
                    (space.id == currentSpace?.id) ? i : nil
                setTabs(arr, for: space.id)
                break
            }
        }
        if removed == nil, let i = pinnedTabs.firstIndex(where: { $0.id == id })
        {
            removed = pinnedTabs.remove(at: i)
        }

        guard let tab = removed else { return }

        if #available(macOS 15.4, *) {
            ExtensionManager.shared.notifyTabClosed(tab)
        }

        if wasCurrent {
            if tab.spaceId == nil {
                if !pinnedTabs.isEmpty {
                    currentTab = pinnedTabs.last
                } else if let cs = currentSpace {
                    let arr = tabsBySpace[cs.id] ?? []
                    currentTab = arr.last
                } else {
                    currentTab = nil
                }
            } else if let cs = currentSpace {
                let arr = tabsBySpace[cs.id] ?? []
                if let i = removedIndexInCurrentSpace, !arr.isEmpty {
                    let newIndex = min(i, arr.count - 1)
                    currentTab =
                        arr.indices.contains(newIndex)
                        ? arr[newIndex] : arr.first
                } else if !arr.isEmpty {
                    currentTab = arr.last
                } else if !pinnedTabs.isEmpty {
                    currentTab = pinnedTabs.last
                } else {
                    currentTab = nil
                }
            }
        }

        persistSnapshot()
    }

    func setActiveTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        let previous = currentTab
        if let old = currentTab, old.id != tab.id { old.pause() }
        currentTab = tab
        if let sid = tab.spaceId, let sp = spaces.first(where: { $0.id == sid })
        {
            currentSpace = sp
        }
        if #available(macOS 15.4, *) {
            ExtensionManager.shared.notifyTabActivated(newTab: tab, previous: previous)
        }
        persistSnapshot()
    }

    @discardableResult
    func createNewTab(
        url: String = "https://www.google.com",
        in space: Space? = nil
    ) -> Tab {
        let engine = browserManager?.settingsManager.searchEngine ?? .google
        guard let validURL = URL(string: normalizeURL(url, provider: engine))
        else {
            print("Invalid URL: \(url). Falling back to default.")
            return createNewTab(in: space)
        }
        let targetSpace = space ?? currentSpace
        let sid = targetSpace?.id
        
        // Get the next index for this space
        let existingTabs = sid.flatMap { tabsBySpace[$0] } ?? []
        let nextIndex = (existingTabs.map { $0.index }.max() ?? -1) + 1
        
        let newTab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            browserManager: browserManager
        )
        addTab(newTab)
        setActiveTab(newTab)
        return newTab
    }

    func closeActiveTab() {
        guard let currentTab else {
            print("No active tab to close")
            return
        }
        removeTab(currentTab.id)
    }

    // MARK: - Tab Ordering

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

    // MARK: - Pinned tabs (global)

    func pinTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        if pinnedTabs.contains(where: { $0.id == tab.id }) { return }

        // Remove from its space list if needed
        if let sid = tab.spaceId, var arr = tabsBySpace[sid],
            let i = arr.firstIndex(where: { $0.id == tab.id })
        {
            _ = arr.remove(at: i)
            setTabs(arr, for: sid)
        }
        tab.spaceId = nil
        pinnedTabs.append(tab)
        if currentTab?.id == tab.id { currentTab = tab }
        persistSnapshot()
    }

    func unpinTab(_ tab: Tab) {
        guard let i = pinnedTabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }
        let moved = pinnedTabs.remove(at: i)
        let targetSpaceId = currentSpace?.id ?? spaces.first?.id
        guard let sid = targetSpaceId else {
            print("No space to place unpinned tab")
            return
        }
        moved.spaceId = sid
        var arr = tabsBySpace[sid] ?? []
        arr.insert(moved, at: 0)
        setTabs(arr, for: sid)
        print("Unpinned tab: \(moved.name) -> space \(sid)")
        if currentTab?.id == moved.id { currentTab = moved }
        persistSnapshot()
    }

    func togglePin(_ tab: Tab) {
        if pinnedTabs.contains(where: { $0.id == tab.id }) {
            unpinTab(tab)
        } else {
            pinTab(tab)
        }
    }

    // MARK: - Navigation (pinned + current space)

    func selectNextTab() {
        let inSpace = tabs
        let all = pinnedTabs + inSpace
        guard !all.isEmpty, let current = currentTab else { return }
        guard let currentIndex = all.firstIndex(where: { $0.id == current.id })
        else { return }
        let nextIndex = (currentIndex + 1) % all.count
        setActiveTab(all[nextIndex])
    }

    func selectPreviousTab() {
        let inSpace = tabs
        let all = pinnedTabs + inSpace
        guard !all.isEmpty, let current = currentTab else { return }
        guard let currentIndex = all.firstIndex(where: { $0.id == current.id })
        else { return }
        let previousIndex = currentIndex == 0 ? all.count - 1 : currentIndex - 1
        setActiveTab(all[previousIndex])
    }

    // MARK: - Persistence mapping

    private func toTabEntity(_ tab: Tab, isPinned: Bool, persistenceIndex: Int)
        -> TabEntity
    {
        TabEntity(
            id: tab.id,
            urlString: tab.url.absoluteString,
            name: tab.name,
            isPinned: isPinned,
            index: tab.index,
            spaceId: tab.spaceId
        )
    }

    private func toRuntime(_ e: TabEntity) -> Tab {
        let url =
            URL(string: e.urlString) ?? URL(string: "https://www.google.com")!
        let t = Tab(
            id: e.id,
            url: url,
            name: e.name,
            favicon: "globe",
            spaceId: e.spaceId,
            index: e.index,
            browserManager: browserManager
        )
        return t
    }

    // MARK: - SwiftData load/save

    @MainActor
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
                )
            }
            for sp in spaces {
                tabsBySpace[sp.id] = []
            }

            // Tabs
            let tabEntities = try context.fetch(FetchDescriptor<TabEntity>())
            let sortedTabs = tabEntities.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                if a.spaceId != b.spaceId {
                    return (a.spaceId?.uuidString ?? "")
                        < (b.spaceId?.uuidString ?? "")
                }
                return a.index < b.index
            }

            let pinned = sortedTabs.filter { $0.isPinned }
            let normals = sortedTabs.filter { !$0.isPinned }

            self.pinnedTabs = pinned.map(toRuntime)
            for e in normals {
                let t = toRuntime(e)
                if let sid = e.spaceId {
                    var arr = tabsBySpace[sid] ?? []
                    arr.append(t)
                    tabsBySpace[sid] = arr
                }
            }

            // Attach browser manager
            for t in (self.pinnedTabs + allTabsAllSpaces()) {
                t.browserManager = browserManager
            }

            // State
            let states = try context.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first
            // Ensure there's always at least one space
            if spaces.isEmpty {
                let personalSpace = Space(name: "Personal", icon: "person.crop.circle")
                spaces.append(personalSpace)
                tabsBySpace[personalSpace.id] = []
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

            let allForSelection =
                self.pinnedTabs
                + (currentSpace.flatMap { tabsBySpace[$0.id] } ?? [])
            if let id = state?.currentTabID,
                let match = allForSelection.first(where: { $0.id == id })
            {
                self.currentTab = match
            } else {
                self.currentTab = allForSelection.first
            }

            if let ct = self.currentTab { _ = ct.webView }
            print(
                "Current Space: \(currentSpace?.name ?? "None"), Tab: \(currentTab?.name ?? "None")"
            )
        } catch {
            print("SwiftData load error: \(error)")
        }
    }

    @MainActor
    public func persistSnapshot() {
        do {
            let all = try context.fetch(FetchDescriptor<TabEntity>())
            let keepIDs = Set(
                (pinnedTabs + spaces.flatMap { tabsBySpace[$0.id] ?? [] }).map {
                    $0.id
                }
            )
            for e in all where !keepIDs.contains(e.id) {
                context.delete(e)
            }
        } catch {
            print("Fetch for cleanup failed: \(error)")
        }

        func upsert(tab: Tab, isPinned: Bool, index: Int) {
            do {
                let wantedID = tab.id
                let predicate = #Predicate<TabEntity> { $0.id == wantedID }
                var e =
                    try context
                    .fetch(FetchDescriptor<TabEntity>(predicate: predicate))
                    .first

                if e == nil {
                    e = TabEntity(
                        id: tab.id,
                        urlString: tab.url.absoluteString,
                        name: tab.name,
                        isPinned: isPinned,
                        index: tab.index,
                        spaceId: tab.spaceId
                    )
                    context.insert(e!)
                } else if let entity = e {
                    entity.urlString = tab.url.absoluteString
                    entity.name = tab.name
                    entity.isPinned = isPinned
                    entity.index = tab.index
                    entity.spaceId = tab.spaceId
                }
            } catch {
                print("Upsert failed: \(error)")
            }
        }

        for (sIndex, sp) in spaces.enumerated() {
            let arr = tabsBySpace[sp.id] ?? []
            for (i, t) in arr.enumerated() {
                upsert(tab: t, isPinned: false, index: i)
            }

            do {
                let spaceID = sp.id
                let predicate = #Predicate<SpaceEntity> { $0.id == spaceID }
                var e =
                    try context
                    .fetch(FetchDescriptor<SpaceEntity>(predicate: predicate))
                    .first

                if e == nil {
                    e = SpaceEntity(
                        id: sp.id,
                        name: sp.name,
                        icon: sp.icon,
                        index: sIndex
                    )
                    context.insert(e!)
                } else if let entity = e {
                    entity.name = sp.name
                    entity.icon = sp.icon
                    entity.index = sIndex
                }
            } catch {
                print("Space upsert failed: \(error)")
            }
        }

        do {
            let allSpaces = try context.fetch(FetchDescriptor<SpaceEntity>())
            let keep = Set(spaces.map { $0.id })
            for e in allSpaces where !keep.contains(e.id) {
                context.delete(e)
            }
        } catch {
            print("Space cleanup failed: \(error)")
        }

        do {
            let allStates = try context.fetch(
                FetchDescriptor<TabsStateEntity>()
            )
            let state =
                allStates.first
                ?? {
                    let s = TabsStateEntity(
                        currentTabID: nil,
                        currentSpaceID: nil
                    )
                    context.insert(s)
                    return s
                }()
            state.currentTabID = currentTab?.id
            state.currentSpaceID = currentSpace?.id
        } catch {
            print("State upsert failed: \(error)")
        }

        do {
            try context.save()
            print("SwiftData snapshot saved.")
        } catch {
            print("SwiftData save error: \(error)")
        }
    }
}

extension TabManager {
    func reattachBrowserManager(_ bm: BrowserManager) {
        self.browserManager = bm
        for t in (self.pinnedTabs + self.tabs) {
            t.browserManager = bm
        }
        if let current = self.currentTab {
            let all = self.pinnedTabs + self.tabs
            if let match = all.first(where: { $0.id == current.id }) {
                self.currentTab = match
            }
        }
        if let ct = self.currentTab { _ = ct.webView }
        // Inform the extension controller about existing tabs and the active tab
        if #available(macOS 15.4, *) {
            for t in (self.pinnedTabs + self.tabs) where t.didNotifyOpenToExtensions == false {
                ExtensionManager.shared.notifyTabOpened(t)
                t.didNotifyOpenToExtensions = true
            }
            if let current = self.currentTab {
                ExtensionManager.shared.notifyTabActivated(newTab: current, previous: nil)
            }
        }
    }
}
extension TabManager {
    func tabs(in space: Space) -> [Tab] {
        (tabsBySpace[space.id] ?? []).sorted { $0.index < $1.index }
    }
}
