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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
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

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
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
        max(outerWidth - 16, 0)
    }

    private var tabs: [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return browserManager.tabManager.tabs(in: space)
    }

    private var spacePinnedTabs: [Tab] {
        if windowState.isIncognito {
            return []
        }
        return browserManager.tabManager.spacePinnedTabs(for: space.id)
    }

    private var folders: [TabFolder] {
        if windowState.isIncognito {
            return []
        }
        return browserManager.tabManager.folders(for: space.id)
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

        // Filter out folder tabs from spacePinnedTabs before processing
        // Only tabs with folderId == nil should appear outside folders
        let nonFolderSpacePinnedTabs = currentSpacePinnedTabs.filter { $0.folderId == nil }
        let folderSpacePinnedTabs = currentSpacePinnedTabs.filter { $0.folderId != nil }

        // Group folder tabs by their folderId
        let tabsByFolderId = Dictionary(grouping: folderSpacePinnedTabs) { tab in
            tab.folderId
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
        VStack(spacing: 4) {
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
        .padding(.horizontal, 8)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
        .onReceive(NotificationCenter.default.publisher(for: .init("TabFoldersDidChange"))) { _ in
            folderChangeCount += 1
        }
        .onHover { state in
            withAnimation(.easeInOut(duration: 0.15)) {
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
        switch drop.targetZone {
        case .spacePinned(let id), .spaceRegular(let id):
            isTargetingThisSpace = (id == space.id)
        case .folder(let folderId):
            // Check if folder belongs to this space
            isTargetingThisSpace = folders.contains(where: { $0.id == folderId })
        default:
            isTargetingThisSpace = false
        }
        guard isTargetingThisSpace else { return }

        let allTabs = browserManager.tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }

        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
        }
        dragSession.pendingDrop = nil
    }

    private func handlePendingReorder(_ reorder: PendingReorder?) {
        guard let reorder = reorder else { return }
        // Only handle reorders for this space's zones
        let isForThisSpace: Bool
        switch reorder.zone {
        case .spacePinned(let id), .spaceRegular(let id):
            isForThisSpace = (id == space.id)
        case .folder(let folderId):
            isForThisSpace = folders.contains(where: { $0.id == folderId })
        default:
            isForThisSpace = false
        }
        guard isForThisSpace else { return }

        guard let tab = browserManager.tabManager.allTabs().first(where: { $0.id == reorder.item.tabId }) else {
            dragSession.pendingReorder = nil
            return
        }

        let op = dragSession.makeDragOperation(from: reorder, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
        }
        dragSession.pendingReorder = nil
    }

    private var mainContentContainer: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            pinnedTabsSection

                            NookDropZoneHostView(
                                zoneID: .spaceRegular(space.id),
                                isVertical: true,
                                manager: dragSession
                            ) {
                                VStack(spacing: 8) {
                                    newTabButtonSectionWithClear
                                    regularTabsListInner
                                }
                            }
                            .onAppear {
                                updateRegularTabsCaches()
                            }
                            .onChange(of: tabs.count) { _, _ in
                                updateRegularTabsCaches()
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
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToTop(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .zIndex(10)

                    VStack {
                        Spacer()
                        if showBottomArrow {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToActiveTab(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
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
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.3)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.2))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasSpacePinnedContent)
    }

    private var pinnedTabsList: some View {
        let items = spacePinnedItems

        return NookDropZoneHostView(
            zoneID: .spacePinned(space.id),
            isVertical: true,
            manager: dragSession
        ) {
            VStack(spacing: 0) {
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
                            insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.3)),
                            removal: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.2))
                        ))
                    } else if let tab = item as? Tab {
                        pinnedTabView(tab, index: index)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).animation(.easeInOut(duration: 0.2)),
                            removal: .opacity.combined(with: .move(edge: .top)).animation(.easeInOut(duration: 0.15))
                        ))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: items.count)
        }
        .onAppear {
            updateSpacePinnedCaches()
        }
        .onChange(of: spacePinnedItems.count) { _, _ in
            updateSpacePinnedCaches()
        }
    }

    private func updateSpacePinnedCaches() {
        let zone = DropZoneID.spacePinned(space.id)
        let nonFolderTabs = spacePinnedTabs.filter { $0.folderId == nil }
        dragSession.itemCellSize[zone] = 36
        dragSession.itemCellSpacing[zone] = 2
        dragSession.itemCounts[zone] = nonFolderTabs.count + folders.count
    }

    private func pinnedTabView(_ tab: Tab, index: Int) -> some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.name, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .spacePinned(space.id),
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
        .offset(y: dragSession.reorderOffset(for: .spacePinned(space.id), at: index))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragSession.insertionIndex[.spacePinned(space.id)])
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            pinnedTabContextMenu(tab)
        }
    }

    private func pinnedTabContextMenu(_ tab: Tab) -> some View {
        VStack {
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) } label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) } label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
            Divider()
            Button { browserManager.tabManager.unpinTabFromSpace(tab) } label: { Label("Unpin from Space", systemImage: "pin.slash") }
            Button { onPinTab(tab) } label: { Label("Pin Globally", systemImage: "pin.circle") }
            Divider()
            Button { onCloseTab(tab) } label: { Label("Close tab", systemImage: "xmark") }
        }
    }

    private var newTabButtonSection: some View {
        Button {
            commandPalette.open()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("New Tab")
                Spacer()
            }
        }
        .buttonStyle(RectNavButtonStyle())
        .padding(.top, 8)
    }

    private var newTabButtonSectionWithClear: some View {
        VStack(spacing: 0) {
            SpaceSeparator(isHovering: $isSidebarHovered) {
                browserManager.tabManager.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            newTabButtonSection
        }
    }

    private var regularTabsListInner: some View {
        VStack(spacing: 2) {
            if !tabs.isEmpty {
                regularTabsContent
            } else {
                emptyRegularTabsDropTarget
            }
        }
        .animation(.easeInOut(duration: 0.15), value: tabs.count)
    }

    private var regularTabsContent: some View {
        VStack(spacing: 2) {
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
                .frame(height: 100)
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.top, 2)
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
        VStack(spacing: 2) {
            ForEach(Array(currentTabs.enumerated()), id: \.element.id) { index, tab in
                regularTabView(tab, index: index)
            }
        }
    }

    private func updateRegularTabsCaches() {
        let zone = DropZoneID.spaceRegular(space.id)
        dragSession.itemCellSize[zone] = 36
        dragSession.itemCellSpacing[zone] = 2
        dragSession.itemCounts[zone] = tabs.count
    }

    private func regularTabView(_ tab: Tab, index: Int) -> some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.name, urlString: tab.url.absoluteString),
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragSession.insertionIndex[.spaceRegular(space.id)])
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            regularTabContextMenu(tab)
        }
    }

    private func regularTabContextMenu(_ tab: Tab) -> some View {
        VStack {
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) } label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) } label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
            Divider()
            Button { onMoveTabUp(tab) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(isFirstTab(tab))
            Button { onMoveTabDown(tab) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(isLastTab(tab))
            Divider()
            Button { browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id) } label: { Label("Pin to Space", systemImage: "pin") }
            Button { onPinTab(tab) } label: { Label("Pin Globally", systemImage: "pin.circle") }
            Button { onCloseTab(tab) } label: { Label("Close tab", systemImage: "xmark") }
        }
    }

    private var emptyRegularTabsDropTarget: some View {
        Color.clear
            .frame(minHeight: 100, maxHeight: .infinity)
            .padding(.top, 2)
            .contentShape(Rectangle())
    }

    // MARK: - Folder Management

    private func deleteFolder(_ folder: TabFolder) {
        browserManager.tabManager.deleteFolder(folder.id)
    }

    private func addTabToFolder(_ folder: TabFolder) {
        // Create a new tab and add it to the folder
        let newTab = browserManager.tabManager.createNewTab(in: space)
        newTab.folderId = folder.id
        newTab.isSpacePinned = true
        browserManager.tabManager.persistSnapshot()
    }

    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }

    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }

    private var windowDragSpacer: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .frame(width: geometry.size.width, height: max(40, geometry.size.height))
                .contentShape(Rectangle())
                .conditionalWindowDrag()
        }
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

        height += 17

        let pinnedCount = spacePinnedItems.count
        if pinnedCount > 0 {
            height += CGFloat(pinnedCount) * 40
            height += 8
        }

        height += 32 + 8

        let regularCount = tabs.count
        if regularCount > 0 {
            height += CGFloat(regularCount) * 40
        } else {
            height += 40
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
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .bottom)
            }
            return
        }

        let activeTabBottom = activeTabPosition.maxY
        if activeTabBottom < scrollOffset {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .top)
            }
            return
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("space-separator-top", anchor: .top)
        }
    }
}
