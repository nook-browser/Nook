//
//  SpaceView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types
struct FolderWithTabs: Hashable {
    let folder: TabFolder
    let tabs: [Tab]

    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(folder.id)
    }

    static func == (lhs: FolderWithTabs, rhs: FolderWithTabs) -> Bool {
        lhs.folder.id == rhs.folder.id && lhs.tabs.count == rhs.tabs.count
    }
}

struct TabPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SpaceView: View {
    let space: Space
    let isActive: Bool
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(TabOrganizerManager.self) private var tabOrganizerManager
    @Environment(\.nookSettings) private var nookSettings
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @ObservedObject private var dragSession = NookDragSessionManager.shared
    @State private var canScrollUp: Bool = false
    @State private var canScrollDown: Bool = false
    @State private var showTopArrow: Bool = false
    @State private var showBottomArrow: Bool = false
    @State private var isAtTop: Bool = true
    @State private var activeTabIsVisible: Bool = true
    @State private var viewportHeight: CGFloat = 0
    @State private var totalContentHeight: CGFloat = 0
    @State private var activeTabPosition: CGRect = .zero
    @State private var scrollOffset: CGFloat = 0
    @State private var tabPositions: [UUID: CGRect] = [:]
    @State private var lastScrollOffset: CGFloat = 0
    @State private var lastPositionUpdate: Date = .distantPast
    @State private var isUserInitiatedTabSelection: Bool = false
    @State private var lockScrollView: Bool = false
    @State private var refreshTrigger: UUID = UUID()
    @State private var folderChangeCount: Int = 0
    @State private var isHovered: Bool = false
    @State private var isNewTabHovering = false

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    @EnvironmentObject var splitManager: SplitViewManager

    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserManager.getSavedSidebarWidth(for: windowState)
        return max(fallbackWidth, 0)
    }

    private var innerWidth: CGFloat {
        max(outerWidth - NookDesign.Spacing.sidebarInset * 2, 0)
    }

    private var tabs: [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return tabManager.tabs(in: space)
    }

    private var spacePinnedTabs: [Tab] {
        if windowState.isIncognito {
            return []
        }
        return tabManager.spacePinnedTabs(for: space.id)
    }

    /// Folders shown in the pinned section. Regular folders render in the regular section.
    private var folders: [TabFolder] {
        if windowState.isIncognito {
            return []
        }
        return tabManager.folders(for: space.id).filter { !$0.isRegular }
    }

    // Drop zones index by sidebar row, and folders sit above the loose tabs in both sections.
    // A folder takes its header row plus one row per tab while open. These offsets translate
    // between the drag session's row slots and TabManager's loose-tab positions.
    private func rowCount(of folder: TabFolder, tabs: [Tab]) -> Int {
        folder.isOpen ? 1 + tabs.filter { $0.folderId == folder.id }.count : 1
    }

    private var pinnedFolderRows: Int {
        folders.reduce(0) { $0 + rowCount(of: $1, tabs: spacePinnedTabs) }
    }

    private var regularFolderRows: Int {
        if windowState.isIncognito { return 0 }
        return tabManager.regularFolders(for: space.id).reduce(0) { $0 + rowCount(of: $1, tabs: tabs) }
    }

    /// Converts a row in one of this space's zones to a position among its loose tabs.
    private func looseIndex(_ row: Int, in zone: DropZoneID) -> Int {
        switch zone {
        case .spacePinned: return max(0, row - pinnedFolderRows)
        case .spaceRegular: return max(0, row - regularFolderRows)
        default: return row
        }
    }

    private var hasSpacePinnedContent: Bool {
        !spacePinnedTabs.isEmpty || !folders.isEmpty
    }

    private var spacePinnedItems: [AnyHashable] {
        // Force dependency tracking for folder changes
        _ = folderChangeCount

        let currentFolders = folders
        let currentSpacePinnedTabs = spacePinnedTabs

        // Early return if no content
        guard !currentSpacePinnedTabs.isEmpty || !currentFolders.isEmpty else {
            return []
        }

        var items: [AnyHashable] = []

        // Single-pass partition: split tabs into folder vs non-folder
        var nonFolderSpacePinnedTabs: [Tab] = []
        var tabsByFolderId: [UUID: [Tab]] = [:]
        for tab in currentSpacePinnedTabs {
            if let folderId = tab.folderId {
                tabsByFolderId[folderId, default: []].append(tab)
            } else {
                nonFolderSpacePinnedTabs.append(tab)
            }
        }

        // Add folders with their tabs
        for folder in currentFolders {
            let folderTabs = tabsByFolderId[folder.id]?.sorted { $0.index < $1.index } ?? []
            items.append(FolderWithTabs(folder: folder, tabs: folderTabs))
        }

        // Add non-folder tabs (these appear outside folders)
        let sortedNonFolderTabs = nonFolderSpacePinnedTabs.sorted { $0.index < $1.index }
        items.append(contentsOf: sortedNonFolderTabs)

        return items
    }


    var body: some View {
        VStack(spacing: NookDesign.Spacing.xs) {
            // Wrap SpaceTitle in a spacePinned drop zone so tabs can be dropped
            // onto the title to pin them (especially when pinned section is empty)
            NookDropZoneHostView(
                zoneID: .spacePinned(space.id),
                isVertical: true,
                manager: dragSession
            ) {
                SpaceTitle(space: space)
            }
            .onAppear {
                updateSpacePinnedCaches()
            }

            mainContentContainer
        }
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
        .onReceive(NotificationCenter.default.publisher(for: .init("TabFoldersDidChange"))) { _ in
            folderChangeCount += 1
        }
        .onHoverTracking { state in
            withAnimation(NookDesign.Motion.quick) {
                isHovered = state
            }
        }
        .onChange(of: dragSession.pendingDrop) { _, newDrop in
            handlePendingDrop(newDrop)
        }
        .onChange(of: dragSession.pendingReorder) { _, newReorder in
            handlePendingReorder(newReorder)
        }
    }

    // MARK: - Drop Handling

    private func handlePendingDrop(_ drop: PendingDrop?) {
        guard let drop = drop else { return }
        // Only handle drops targeting this space's zones
        let isTargetingThisSpace: Bool
        // Folder zones are handled by their own TabFolderView.
        switch drop.targetZone {
        case .spacePinned(let id), .spaceRegular(let id):
            isTargetingThisSpace = (id == space.id)
        default:
            isTargetingThisSpace = false
        }
        guard isTargetingThisSpace else { return }

        let allTabs = tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }

        let op = DragOperation(
            tab: tab,
            fromContainer: drop.sourceZone.asDragContainer,
            fromIndex: drop.sourceIndex,
            toContainer: drop.targetZone.asDragContainer,
            toIndex: looseIndex(drop.targetIndex, in: drop.targetZone),
            toSpaceId: drop.targetZone.spaceId
        )
        // Disable all animations — items are already at their visual positions
        // from drag offsets, so the drop should just "lock in" instantly
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
        dragSession.pendingDrop = nil
    }

    private func handlePendingReorder(_ reorder: PendingReorder?) {
        guard let reorder = reorder else { return }
        // Only handle reorders for this space's zones
        let isForThisSpace: Bool
        // Folder zones are handled by their own TabFolderView.
        switch reorder.zone {
        case .spacePinned(let id), .spaceRegular(let id):
            isForThisSpace = (id == space.id)
        default:
            isForThisSpace = false
        }
        guard isForThisSpace else { return }

        guard let tab = tabManager.allTabs().first(where: { $0.id == reorder.item.tabId }) else {
            dragSession.pendingReorder = nil
            return
        }

        let op = DragOperation(
            tab: tab,
            fromContainer: reorder.zone.asDragContainer,
            fromIndex: reorder.fromIndex,
            toContainer: reorder.zone.asDragContainer,
            toIndex: looseIndex(reorder.toIndex, in: reorder.zone),
            toSpaceId: reorder.zone.spaceId
        )
        // Disable all animations — items are already at their visual positions
        // from drag offsets, so the reorder should just "lock in" instantly
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
        dragSession.pendingReorder = nil
    }

    private var mainContentContainer: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: NookDesign.Spacing.sectionGap) {
                            pinnedTabsSection
                                .id("space-separator-top")

                            VStack(spacing: NookDesign.Spacing.sectionGap) {
                                newTabButtonSectionWithClear
                                NookDropZoneHostView(
                                    zoneID: .spaceRegular(space.id),
                                    isVertical: true,
                                    manager: dragSession
                                ) {
                                    regularTabsListInner
                                }
                                .onAppear {
                                    updateRegularTabsCaches()
                                }
                                .onChange(of: tabs.count) { _, _ in
                                    updateRegularTabsCaches()
                                }
                                .onChange(of: regularFolderRows) { _, _ in
                                    updateRegularTabsCaches()
                                }
                            }
                        }
                        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
                        .coordinateSpace(name: "ScrollSpace")
                    }
                    .contentShape(Rectangle())
                    .onScrollGeometryChange(for: CGRect.self) { geometry in
                        geometry.bounds
                    } action: { oldBounds, newBounds in
                        updateScrollState(bounds: newBounds)
                    }
                    VStack {
                        if showTopArrow {
                            HStack {
                                Rectangle()
                                    .fill(NookDesign.Surface.hairline)
                                    .frame(height: NookDesign.Size.hairlineWidth)
                                Spacer()
                                Button {
                                    scrollToTop(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(NookDesign.Font.secondary)
                                        .foregroundColor(.gray)
                                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                                        .background(NookDesign.Surface.raised)
                                        .clipShape(Circle())
                                        .nookElevation(.raised)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
                            .padding(.top, NookDesign.Spacing.xs)
                        }
                        Spacer()
                    }
                    .zIndex(10)

                    VStack {
                        Spacer()
                        if showBottomArrow {
                            HStack {
                                Rectangle()
                                    .fill(NookDesign.Surface.hairline)
                                    .frame(height: NookDesign.Size.hairlineWidth)
                                Spacer()
                                Button {
                                    scrollToActiveTab(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(NookDesign.Font.secondary)
                                        .foregroundColor(.gray)
                                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                                        .background(NookDesign.Surface.raised)
                                        .clipShape(Circle())
                                        .nookElevation(.raised)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
                            .padding(.bottom, NookDesign.Spacing.xs)
                        }
                    }
                }
                .onPreferenceChange(TabPositionPreferenceKey.self) { positions in
                    let now = Date()
                    guard now.timeIntervalSince(lastPositionUpdate) > 0.1 else { return }

                    tabPositions = positions
                    lastPositionUpdate = now
                    updateActiveTabPosition()
                }
            }
        }
    }

    private var pinnedTabsSection: some View {
        Group {
            if hasSpacePinnedContent {
                pinnedTabsList
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(NookDesign.Motion.standard),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(NookDesign.Motion.standard)
                    ))
            }
        }
        .animation(NookDesign.Motion.standard, value: hasSpacePinnedContent)
    }

    private var pinnedTabsList: some View {
        let items = spacePinnedItems

        return NookDropZoneHostView(
            zoneID: .spacePinned(space.id),
            isVertical: true,
            manager: dragSession
        ) {
            let folderRows = pinnedFolderRows
            let folderCount = folders.count
            VStack(spacing: NookDesign.Spacing.rowGap) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    if let folderWithTabs = item as? FolderWithTabs {
                        TabFolderView(
                            folder: folderWithTabs.folder,
                            space: space,
                            onDelete: { deleteFolder(folderWithTabs.folder) },
                            onAddTab: { addTabToFolder(folderWithTabs.folder) },
                            onActivateTab: { onActivateTab($0) }
                        )
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity).animation(NookDesign.Motion.standard),
                            removal: .scale.combined(with: .opacity).animation(NookDesign.Motion.standard)
                        ))
                    } else if let tab = item as? Tab {
                        // Items list folders first, so index - folderCount is the loose position.
                        pinnedTabView(tab, index: folderRows + index - folderCount)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).animation(NookDesign.Motion.standard),
                            removal: .opacity.combined(with: .move(edge: .top)).animation(NookDesign.Motion.quick)
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(NookDesign.Motion.standard, value: items.count)
        }
        .onAppear {
            updateSpacePinnedCaches()
        }
        .onChange(of: spacePinnedItems.count) { _, _ in
            updateSpacePinnedCaches()
        }
        .onChange(of: pinnedFolderRows) { _, _ in
            updateSpacePinnedCaches()
        }
    }

    private func updateSpacePinnedCaches() {
        let zone = DropZoneID.spacePinned(space.id)
        let nonFolderTabs = spacePinnedTabs.filter { $0.folderId == nil }
        dragSession.itemCellSize[zone] = NookDesign.Size.row
        dragSession.itemCellSpacing[zone] = NookDesign.Spacing.rowGap
        dragSession.itemCounts[zone] = nonFolderTabs.count + pinnedFolderRows
    }

    private func pinnedTabView(_ tab: Tab, index: Int) -> some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.displayName, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .spacePinned(space.id),
            index: index,
            manager: dragSession
        ) {
            SpaceTab(
                tab: tab,
                action: { handleUserTabActivation(tab) },
                onClose: { tabManager.forceRemoveTab(tab.id) },
                onUnload: { tabManager.unloadTabMovingSelection(tab) },
                onMute: { onMuteTab(tab) },
                menuContext: .spacePinned
            )
        }
        .id(tab.id)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TabPositionPreferenceKey.self, value: [tab.id: geometry.frame(in: .named("ScrollSpace"))])
            }
        )
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0.0 : 1.0)
        .offset(y: dragSession.reorderOffset(for: .spacePinned(space.id), at: index))
        .animation(NookDesign.Motion.spring, value: dragSession.insertionIndex[.spacePinned(space.id)])
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var newTabButtonSection: some View {
        Button {
            commandPalette.open()
        } label: {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: NookDesign.Size.favicon, weight: .medium))
                Text("New Tab")
                    .font(NookDesign.Font.body)
                Spacer(minLength: 0)
                if isNewTabHovering {
                    Text("⌘T")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isNewTabHovering ? .secondary : .tertiary)
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(maxWidth: .infinity)
            .background(isNewTabHovering ? NookDesign.Surface.fill : Color.clear)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) { isNewTabHovering = hovering }
        }
    }

    private var newTabButtonSectionWithClear: some View {
        VStack(spacing: NookDesign.Spacing.xs) {
            SpaceSeparator(
                isHovering: $isSidebarHovered,
                onClear: {
                    tabManager.clearRegularTabs(for: space.id)
                },
                onOrganize: nookSettings.tabOrganizerEnabled ? {
                    Task {
                        await tabOrganizerManager.organizeTabs(
                            in: space,
                            using: tabManager
                        )
                    }
                } : nil,
                isOrganizing: tabOrganizerManager.isOrganizing,
                tabCount: tabs.filter { $0.folderId == nil }.count
            )
            .padding(.horizontal, NookDesign.Spacing.md)

            newTabButtonSection
        }
    }

    private var regularTabsListInner: some View {
        VStack(spacing: NookDesign.Spacing.rowGap) {
            if !tabs.isEmpty {
                regularTabsContent
            } else {
                emptyRegularTabsDropTarget
            }
        }
        .animation(NookDesign.Motion.quick, value: tabs.count)
    }

    private var regularTabsContent: some View {
        VStack(spacing: NookDesign.Spacing.rowGap) {
            let currentTabs = tabs
            let split = splitManager
            let windowId = windowState.id

            if split.isSplit(for: windowId),
               let leftId = split.leftTabId(for: windowId), let rightId = split.rightTabId(for: windowId),
               let leftIdx = currentTabs.firstIndex(where: { $0.id == leftId }),
               let rightIdx = currentTabs.firstIndex(where: { $0.id == rightId }),
               leftIdx >= 0, rightIdx >= 0,
               leftIdx < currentTabs.count, rightIdx < currentTabs.count,
               leftIdx != rightIdx {
                splitTabsView(currentTabs: currentTabs, leftIdx: leftIdx, rightIdx: rightIdx)
            } else {
                regularTabsView(currentTabs: currentTabs)
            }

            Color.clear
                .contentShape(Rectangle())
                .conditionalWindowDrag()
                .frame(height: NookDesign.Size.dropTail)
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.top, NookDesign.Spacing.rowGap)
    }

    private func splitTabsView(currentTabs: [Tab], leftIdx: Int, rightIdx: Int) -> some View {
        let firstIdx = min(leftIdx, rightIdx)
        let secondIdx = max(leftIdx, rightIdx)

        return ForEach(Array(currentTabs.enumerated()), id: \.element.id) { pair in
            let (idx, tab) = pair
            if idx == firstIdx {
                let left = currentTabs[leftIdx]
                let right = currentTabs[rightIdx]

                SplitTabRow(
                    left: left,
                    right: right,
                    spaceId: space.id,
                    onActivate: onActivateTab,
                    onClose: onCloseTab
                )
                .environmentObject(browserManager)
            } else if idx == secondIdx {
                EmptyView()
            } else {
                regularTabView(tab, index: idx)
            }
        }
    }

    private func regularTabsView(currentTabs: [Tab]) -> some View {
        VStack(spacing: NookDesign.Spacing.rowGap) {
            // Regular folders
            let regFolders = tabManager.regularFolders(for: space.id)
            ForEach(regFolders.sorted(by: { $0.index < $1.index })) { folder in
                TabFolderView(
                    folder: folder,
                    space: space,
                    onDelete: { deleteFolder(folder) },
                    onAddTab: { addTabToFolder(folder) },
                    onActivateTab: { onActivateTab($0) },
                    isRegular: true
                )
                .environmentObject(browserManager)
            }

            // Loose tabs (no folder), indexed by sidebar row within the zone
            let looseTabs = currentTabs.filter { $0.folderId == nil }
            let folderRows = regularFolderRows
            ForEach(Array(looseTabs.enumerated()), id: \.element.id) { index, tab in
                regularTabView(tab, index: folderRows + index)
            }
        }
    }

    private func updateRegularTabsCaches() {
        let zone = DropZoneID.spaceRegular(space.id)
        dragSession.itemCellSize[zone] = NookDesign.Size.row
        dragSession.itemCellSpacing[zone] = NookDesign.Spacing.rowGap
        dragSession.itemCounts[zone] = tabs.filter { $0.folderId == nil }.count + regularFolderRows
    }

    private func regularTabView(_ tab: Tab, index: Int) -> some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.displayName, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .spaceRegular(space.id),
            index: index,
            manager: dragSession
        ) {
            SpaceTab(
                tab: tab,
                action: { handleUserTabActivation(tab) },
                onClose: { onCloseTab(tab) },
                onMute: { onMuteTab(tab) }
            )
        }
        .id(tab.id)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TabPositionPreferenceKey.self, value: [tab.id: geometry.frame(in: .named("ScrollSpace"))])
            }
        )
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0.0 : 1.0)
        .offset(y: dragSession.reorderOffset(for: .spaceRegular(space.id), at: index))
        .animation(NookDesign.Motion.spring, value: dragSession.insertionIndex[.spaceRegular(space.id)])
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyRegularTabsDropTarget: some View {
        Color.clear
            .frame(minHeight: NookDesign.Size.dropTail, maxHeight: .infinity)
            .padding(.top, NookDesign.Spacing.rowGap)
            .contentShape(Rectangle())
    }

    // MARK: - Folder Management

    private func deleteFolder(_ folder: TabFolder) {
        tabManager.deleteFolder(folder.id)
    }

    private func addTabToFolder(_ folder: TabFolder) {
        // Create the tab, then move it with the folder's own membership rules (pinned or regular).
        let newTab = tabManager.createNewTab(in: space)
        tabManager.moveTabToFolder(tab: newTab, folderId: folder.id)
    }

    // MARK: - Scroll State

    private func updateScrollState(bounds: CGRect) {
        let minY = bounds.minY
        let contentHeight = bounds.height

        viewportHeight = contentHeight
        scrollOffset = -minY
        lastScrollOffset = scrollOffset

        canScrollUp = minY < 0

        canScrollDown = totalContentHeight > viewportHeight && (-minY + viewportHeight) < totalContentHeight

        isAtTop = minY >= 0

        updateContentHeight()
        updateArrowIndicators()
    }

    private func updateContentHeight() {
        var height: CGFloat = 0

        height += NookDesign.Size.row // title row

        let pinnedCount = spacePinnedItems.count
        if pinnedCount > 0 {
            height += CGFloat(pinnedCount) * (NookDesign.Size.row + NookDesign.Spacing.rowGap)
            height += NookDesign.Spacing.sectionGap
        }

        height += NookDesign.Size.row + NookDesign.Spacing.sectionGap // new-tab row + separator gap

        let regularCount = tabs.count
        if regularCount > 0 {
            height += CGFloat(regularCount) * (NookDesign.Size.row + NookDesign.Spacing.rowGap)
        } else {
            height += NookDesign.Size.row + NookDesign.Spacing.rowGap
        }

        totalContentHeight = height
    }

    private func handleUserTabActivation(_ tab: Tab) {
        lockScrollView = true
        isUserInitiatedTabSelection = true

        onActivateTab(tab)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.lockScrollView = false
            self.isUserInitiatedTabSelection = false
        }
    }

    private func updateActiveTabPosition() {
        guard let activeTab = browserManager.currentTabForActiveWindow(),
              activeTab.spaceId == space.id else {
            activeTabPosition = .zero
            showTopArrow = false
            showBottomArrow = false
            return
        }

        if let tabFrame = tabPositions[activeTab.id] {
            activeTabPosition = tabFrame
        }

        DispatchQueue.main.async {
            self.updateArrowIndicators()
        }
    }

    private func updateArrowIndicators() {
        guard let activeTab = browserManager.currentTabForActiveWindow(),
              activeTab.spaceId == space.id else {
            // No active tab in this space, don't show arrows
            showTopArrow = false
            showBottomArrow = false
            return
        }

        guard !isUserInitiatedTabSelection else {
            showTopArrow = false
            showBottomArrow = false
            return
        }

        let activeTabTop = activeTabPosition.minY
        let activeTabBottom = activeTabPosition.maxY

        let activeTabIsAbove = activeTabBottom < scrollOffset
        let activeTabIsBelow = activeTabTop > scrollOffset + viewportHeight
        showTopArrow = activeTabIsAbove && canScrollUp
        showBottomArrow = activeTabIsBelow && canScrollDown
    }

    private func scrollToActiveTab(proxy: ScrollViewProxy) {
        guard let activeTab = browserManager.currentTabForActiveWindow(),
              activeTab.spaceId == space.id else { return }

        guard !isUserInitiatedTabSelection && !lockScrollView else { return }

        updateContentHeight()
        updateActiveTabPosition()

        let activeTabTop = activeTabPosition.minY
        if activeTabTop > scrollOffset + viewportHeight {
            withAnimation(NookDesign.Motion.standard) {
                proxy.scrollTo(activeTab.id, anchor: .bottom)
            }
            return
        }

        let activeTabBottom = activeTabPosition.maxY
        if activeTabBottom < scrollOffset {
            withAnimation(NookDesign.Motion.standard) {
                proxy.scrollTo(activeTab.id, anchor: .top)
            }
            return
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation(NookDesign.Motion.standard) {
            proxy.scrollTo("space-separator-top", anchor: .top)
        }
    }
}
