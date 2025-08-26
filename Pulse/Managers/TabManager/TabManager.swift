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
    
    // Space-level pinned tabs per space
    private var spacePinnedTabs: [UUID: [Tab]] = [:]

    // Pinned tabs (global essentials)
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
        let spacePinned = spaces.flatMap { spacePinnedTabs[$0.id] ?? [] }
        return pinnedTabs + spacePinned + normals
    }

    private func contains(_ tab: Tab) -> Bool {
        if pinnedTabs.contains(where: { $0.id == tab.id }) { return true }
        if let sid = tab.spaceId {
            if let spacePinned = spacePinnedTabs[sid], spacePinned.contains(where: { $0.id == tab.id }) { return true }
            if let arr = tabsBySpace[sid], arr.contains(where: { $0.id == tab.id }) { return true }
        }
        return false
    }

    // MARK: - Space Management
    @discardableResult
    func createSpace(name: String, icon: String = "square.grid.2x2") -> Space {
        let space = Space(name: name, icon: icon)
        spaces.append(space)
        tabsBySpace[space.id] = []
        spacePinnedTabs[space.id] = []
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
        let spacePinnedClosing = spacePinnedTabs[id] ?? []
        for t in closing + spacePinnedClosing {
            if currentTab?.id == t.id { currentTab = nil }
        }
        tabsBySpace[id] = []
        spacePinnedTabs[id] = []
        spaces.remove(at: idx)
        if currentSpace?.id == id {
            currentSpace = spaces.first
        }
        persistSnapshot()
    }

    func setActiveSpace(_ space: Space) {
        guard spaces.contains(where: { $0.id == space.id }) else { return }
        
        // Capture the previous tab before switching
        let previousTab = currentTab
        
        // Save the current tab as the active tab for the current space
        if let currentSpace = self.currentSpace, let currentTab = self.currentTab {
            if let spaceTabId = currentTab.spaceId, spaceTabId == currentSpace.id {
                currentSpace.activeTabId = currentTab.id
            }
        }
        
        currentSpace = space
        let inSpace = tabsBySpace[space.id] ?? []

        // Restore the previously active tab for this space IMMEDIATELY
        let targetTab: Tab?
        if let activeTabId = space.activeTabId,
           let activeTab = inSpace.first(where: { $0.id == activeTabId }) {
            targetTab = activeTab
        } else if let ct = currentTab {
            if let sid = ct.spaceId, sid != space.id {
                targetTab = inSpace.first ?? pinnedTabs.first
            } else if ct.spaceId == nil {
                targetTab = inSpace.first ?? pinnedTabs.first
            } else {
                targetTab = ct
            }
        } else {
            targetTab = inSpace.first ?? pinnedTabs.first
        }
        
        // Simply set the current tab - the UI will update automatically
        currentTab = targetTab

        persistSnapshot()
        // Notify extensions about activation change across spaces
        if #available(macOS 15.5, *), let newActive = currentTab {
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
        let wasCurrent = (currentTab?.id == id)
        var removed: Tab?
        var removedIndexInCurrentSpace: Int?

        for space in spaces {
            // Check space-pinned tabs first
            if var spacePinned = spacePinnedTabs[space.id],
                let i = spacePinned.firstIndex(where: { $0.id == id })
            {
                removed = spacePinned.remove(at: i)
                removedIndexInCurrentSpace =
                    (space.id == currentSpace?.id) ? i : nil
                spacePinnedTabs[space.id] = spacePinned
                break
            }
            // Then check regular tabs
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

        // Force unload the tab from compositor before removing
        browserManager?.compositorManager.unloadTab(tab)

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
    }

    func setActiveTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        let previous = currentTab
        currentTab = tab
        
        // Save this tab as the active tab for its space
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            space.activeTabId = tab.id
            currentSpace = space
        }
        
        // Load the tab in compositor if needed
        browserManager?.compositorManager.loadTab(tab)
        
        // Update tab visibility in compositor
        browserManager?.compositorManager.updateTabVisibility(currentTabId: tab.id)
        
        // Check media state using native WebKit API
        tab.checkMediaState()
        if #available(macOS 15.5, *) {
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
        let normalizedUrl = normalizeURL(url, provider: engine)
        guard let validURL = URL(string: normalizedUrl)
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
    
    func unloadTab(_ tab: Tab) {
        browserManager?.compositorManager.unloadTab(tab)
    }
    
    func unloadAllInactiveTabs() {
        let allTabs = pinnedTabs + tabs
        for tab in allTabs {
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
            // Regular tab to global pinned
            pinTab(tab)
            reorderGlobalPinnedTabs(tab, to: operation.toIndex)
            
        case (.spacePinned(_), .essentials):
            // Space pinned to global pinned
            pinTab(tab)
            reorderGlobalPinnedTabs(tab, to: operation.toIndex)
            
        case (.essentials, .spaceRegular(let spaceId)):
            // Global pinned to regular tab
            unpinTab(tab)
            tab.spaceId = spaceId
            addTab(tab)
            reorderRegularTabs(tab, in: spaceId, to: operation.toIndex)
            
        case (.essentials, .spacePinned(let spaceId)):
            // Global pinned to space pinned
            unpinTab(tab)
            pinTabToSpace(tab, spaceId: spaceId)
            reorderSpacePinnedTabs(tab, in: spaceId, to: operation.toIndex)
            
        case (.none, _), (_, .none):
            print("⚠️ Invalid drag operation: \(operation)")
        }
        
        print("✅ Drag operation completed: \(operation.fromContainer) → \(operation.toContainer)")
    }
    
    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) {
        guard let currentIndex = pinnedTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        guard index != currentIndex else { return }
        
        pinnedTabs.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), pinnedTabs.count)
        pinnedTabs.insert(tab, at: clampedIndex)
        
        // Update indices
        for (i, pinnedTab) in pinnedTabs.enumerated() {
            pinnedTab.index = i
        }
        
        persistSnapshot()
    }
    
    private func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        guard var spacePinned = spacePinnedTabs[spaceId],
              let currentIndex = spacePinned.firstIndex(where: { $0.id == tab.id }) else { return }
        guard index != currentIndex else { return }
        
        spacePinned.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), spacePinned.count)
        spacePinned.insert(tab, at: clampedIndex)
        
        // Update indices
        for (i, pinnedTab) in spacePinned.enumerated() {
            pinnedTab.index = i
        }
        
        spacePinnedTabs[spaceId] = spacePinned
        persistSnapshot()
    }
    
    private func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) {
        guard var regularTabs = tabsBySpace[spaceId],
              let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        guard index != currentIndex else { return }
        
        regularTabs.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), regularTabs.count)
        regularTabs.insert(tab, at: clampedIndex)
        
        // Update indices
        for (i, regularTab) in regularTabs.enumerated() {
            regularTab.index = i
        }
        
        tabsBySpace[spaceId] = regularTabs
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
            spacePinned.insert(tab, at: min(toIndex, spacePinned.count))
            // Update indices
            for (i, pinnedTab) in spacePinned.enumerated() {
                pinnedTab.index = i
            }
            spacePinnedTabs[toSpaceId] = spacePinned
        } else {
            var regularTabs = tabsBySpace[toSpaceId] ?? []
            tab.index = toIndex
            regularTabs.insert(tab, at: min(toIndex, regularTabs.count))
            // Update indices
            for (i, regularTab) in regularTabs.enumerated() {
                regularTab.index = i
            }
            tabsBySpace[toSpaceId] = regularTabs
        }
        
        persistSnapshot()
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
    
    // MARK: - Space-Level Pinned Tabs
    
    func spacePinnedTabs(for spaceId: UUID) -> [Tab] {
        return (spacePinnedTabs[spaceId] ?? []).sorted { $0.index < $1.index }
    }
    
    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        guard contains(tab) else { return }
        guard let space = spaces.first(where: { $0.id == spaceId }) else { return }
        
        // Remove from current location
        removeFromCurrentContainer(tab)
        
        // Add to space pinned tabs
        tab.spaceId = spaceId
        var spacePinned = spacePinnedTabs[spaceId] ?? []
        let nextIndex = (spacePinned.map { $0.index }.max() ?? -1) + 1
        tab.index = nextIndex
        spacePinned.append(tab)
        spacePinnedTabs[spaceId] = spacePinned
        
        print("Pinned tab '\(tab.name)' to space '\(space.name)'")
        persistSnapshot()
    }
    
    func unpinTabFromSpace(_ tab: Tab) {
        guard let spaceId = tab.spaceId,
              var spacePinned = spacePinnedTabs[spaceId],
              let index = spacePinned.firstIndex(where: { $0.id == tab.id }) else { return }
        
        // Remove from space pinned tabs
        let unpinned = spacePinned.remove(at: index)
        spacePinnedTabs[spaceId] = spacePinned
        
        // Add to regular tabs in the same space
        var regularTabs = tabsBySpace[spaceId] ?? []
        let nextIndex = (regularTabs.map { $0.index }.max() ?? -1) + 1
        unpinned.index = nextIndex
        regularTabs.append(unpinned)
        tabsBySpace[spaceId] = regularTabs
        
        print("Unpinned tab '\(tab.name)' from space")
        persistSnapshot()
    }
    
    private func removeFromCurrentContainer(_ tab: Tab) {
        // Remove from global pinned
        if let index = pinnedTabs.firstIndex(where: { $0.id == tab.id }) {
            pinnedTabs.remove(at: index)
            return
        }
        
        // Remove from space pinned
        if let spaceId = tab.spaceId,
           var spacePinned = spacePinnedTabs[spaceId],
           let index = spacePinned.firstIndex(where: { $0.id == tab.id }) {
            spacePinned.remove(at: index)
            spacePinnedTabs[spaceId] = spacePinned
            return
        }
        
        // Remove from regular tabs
        if let spaceId = tab.spaceId,
           var regularTabs = tabsBySpace[spaceId],
           let index = regularTabs.firstIndex(where: { $0.id == tab.id }) {
            regularTabs.remove(at: index)
            tabsBySpace[spaceId] = regularTabs
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
        setActiveTab(all[nextIndex])
    }

    func selectPreviousTab() {
        let inSpace = tabs
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        let all = pinnedTabs + spacePinned + inSpace
        guard !all.isEmpty, let current = currentTab else { return }
        guard let currentIndex = all.firstIndex(where: { $0.id == current.id })
        else { return }
        let previousIndex = currentIndex == 0 ? all.count - 1 : currentIndex - 1
        setActiveTab(all[previousIndex])
    }

    // MARK: - Persistence mapping

    private func toTabEntity(_ tab: Tab, isPinned: Bool, isSpacePinned: Bool, persistenceIndex: Int)
        -> TabEntity
    {
        TabEntity(
            id: tab.id,
            urlString: tab.url.absoluteString,
            name: tab.name,
            isPinned: isPinned,
            isSpacePinned: isSpacePinned,
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
                spacePinnedTabs[sp.id] = []
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

            self.pinnedTabs = globalPinned.map(toRuntime)
            
            // Load space-pinned tabs
            for e in spacePinned {
                let t = toRuntime(e)
                if let sid = e.spaceId {
                    var arr = spacePinnedTabs[sid] ?? []
                    arr.append(t)
                    spacePinnedTabs[sid] = arr
                }
            }
            
            // Load regular tabs
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
                (pinnedTabs + 
                 spaces.flatMap { spacePinnedTabs[$0.id] ?? [] } +
                 spaces.flatMap { tabsBySpace[$0.id] ?? [] }).map {
                    $0.id
                }
            )
            for e in all where !keepIDs.contains(e.id) {
                context.delete(e)
            }
        } catch {
            print("Fetch for cleanup failed: \(error)")
        }

        func upsert(tab: Tab, isPinned: Bool, isSpacePinned: Bool, index: Int) {
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
                        isSpacePinned: isSpacePinned,
                        index: tab.index,
                        spaceId: tab.spaceId
                    )
                    context.insert(e!)
                } else if let entity = e {
                    entity.urlString = tab.url.absoluteString
                    entity.name = tab.name
                    entity.isPinned = isPinned
                    entity.isSpacePinned = isSpacePinned
                    entity.index = tab.index
                    entity.spaceId = tab.spaceId
                }
            } catch {
                print("Upsert failed: \(error)")
            }
        }

        // Save global pinned tabs
        for (i, t) in pinnedTabs.enumerated() {
            upsert(tab: t, isPinned: true, isSpacePinned: false, index: i)
        }
        
        for (sIndex, sp) in spaces.enumerated() {
            // Save space-pinned tabs
            let spacePinned = spacePinnedTabs[sp.id] ?? []
            for (i, t) in spacePinned.enumerated() {
                upsert(tab: t, isPinned: false, isSpacePinned: true, index: i)
            }
            
            // Save regular tabs
            let arr = tabsBySpace[sp.id] ?? []
            for (i, t) in arr.enumerated() {
                upsert(tab: t, isPinned: false, isSpacePinned: false, index: i)
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
        let spacePinned = currentSpace.flatMap { spacePinnedTabs(for: $0.id) } ?? []
        for t in (self.pinnedTabs + spacePinned + self.tabs) {
            t.browserManager = bm
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
    }
}
extension TabManager {
    func tabs(in space: Space) -> [Tab] {
        (tabsBySpace[space.id] ?? []).sorted { $0.index < $1.index }
    }
}
