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
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var draggedItem: UUID? = nil
    @State private var spacePinnedPreviewIndex: Int? = nil
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
        browserManager.tabManager.tabs(in: space)
    }

    private var spacePinnedTabs: [Tab] {
        browserManager.tabManager.spacePinnedTabs(for: space.id)
    }

    private var folders: [TabFolder] {
        let folders = browserManager.tabManager.folders(for: space.id)
        print("🔄 SpaceView.folders recomputed: \(folders.count) folders")
        return folders
    }
    
    private var spacePinnedItems: [AnyHashable] {
        _ = folderChangeCount

        var items: [AnyHashable] = []

        let tabsByFolderId = Dictionary(grouping: spacePinnedTabs) { tab in
            tab.folderId
        }

        for folder in folders {
            let folderTabs = tabsByFolderId[folder.id]?.sorted { $0.index < $1.index } ?? []
            items.append(FolderWithTabs(folder: folder, tabs: folderTabs))
        }
        if let nonFolderTabs = tabsByFolderId[nil] {
            let sortedTabs = nonFolderTabs.sorted { $0.index < $1.index }
            items.append(contentsOf: sortedTabs)
        }

        print("🔄 spacePinnedItems recomputed: \(items.count) items (folderChangeCount: \(folderChangeCount))")
        return items
    }
    
    
    var body: some View {
        VStack(spacing: 4) {
            SpaceTitle(space: space)

            if !spacePinnedTabs.isEmpty || !tabs.isEmpty {
                mainContentContainer
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
          .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
            draggedItem = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("TabFoldersDidChange"))) { _ in
            folderChangeCount += 1
        }
      }
    
    private var mainContentContainer: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            pinnedTabsSection
                            newTabButtonSectionWithClear
                            regularTabsList
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
                    .onDrop(
                        of: [.text],
                        delegate: SidebarSectionDropDelegateSimple(
                            itemsCount: { tabs.count },
                            draggedItem: $draggedItem,
                            targetSection: .spaceRegular(space.id),
                            tabManager: browserManager.tabManager
                        )
                    )
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
            if !spacePinnedTabs.isEmpty {
                pinnedTabsList
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.3)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeInOut(duration: 0.2))
                    ))
            } else {
                emptyPinnedDropTarget
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.2)),
                        removal: .opacity.animation(.easeInOut(duration: 0.15))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: spacePinnedTabs.isEmpty)
    }
    
    private var pinnedTabsList: some View {
        let items = spacePinnedItems

        return VStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                if let folderWithTabs = item as? FolderWithTabs {
                    TabFolderView(
                        folder: folderWithTabs.folder,
                        space: space,
                        onRename: { renameFolder(folderWithTabs.folder) },
                        onDelete: { deleteFolder(folderWithTabs.folder) },
                        onAddTab: { addTabToFolder(folderWithTabs.folder) },
                        onActivateTab: { onActivateTab($0) }
                    )
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.3)),
                        removal: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.2))
                    ))
                } else if let tab = item as? Tab {
                    pinnedTabView(tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).animation(.easeInOut(duration: 0.2)),
                        removal: .opacity.combined(with: .move(edge: .top)).animation(.easeInOut(duration: 0.15))
                    ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: items.count)
        .contentShape(Rectangle())
        .onDrop(
            of: [.text],
            delegate: SidebarSectionDropDelegateSimple(
                itemsCount: { browserManager.tabManager.spacePinnedTabs(for: space.id).count },
                draggedItem: $draggedItem,
                targetSection: .spacePinned(space.id),
                tabManager: browserManager.tabManager
            )
        )
    }
    
    private func pinnedTabView(_ tab: Tab) -> some View {
        SpaceTab(
            tab: tab,
            action: { handleUserTabActivation(tab) },
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) }
        )
        .id(tab.id)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TabPositionPreferenceKey.self, value: [tab.id: geometry.frame(in: .named("ScrollSpace"))])
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            pinnedTabContextMenu(tab)
        }
        .onTabDrag(tab.id, draggedItem: $draggedItem)
        .opacity(draggedItem == tab.id ? 0.0 : 1.0)
        .onDrop(
            of: [.text],
            delegate: SidebarTabDropDelegateSimple(
                item: tab,
                draggedItem: $draggedItem,
                targetSection: .spacePinned(space.id),
                tabManager: browserManager.tabManager
            )
        )
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
    
    private var emptyPinnedDropTarget: some View {
        ZStack { Color.clear.frame(height: 1) }
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { 0 },
                    draggedItem: $draggedItem,
                    targetSection: .spacePinned(space.id),
                    tabManager: browserManager.tabManager
                )
            )
    }
    
    @ViewBuilder
    private func spacePinnedSpacer(before displayIndex: Int) -> some View {
        let isActive = spacePinnedPreviewIndex == displayIndex
        
        Color.clear
            .frame(height: 2)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.controlBackgroundHover)
                    .frame(height: isActive ? 4 : 0)
                    .padding(.horizontal, 8)
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: isActive)
            }
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { 0 },
                    draggedItem: $draggedItem,
                    targetSection: .spacePinned(space.id),
                    tabManager: browserManager.tabManager,
                    targetIndex: { spacePinnedInsertionIndex(before: displayIndex) },
                    onDropEntered: { spacePinnedPreviewIndex = displayIndex },
                    onDropCompleted: { spacePinnedPreviewIndex = nil },
                    onDropExited: {
                        if spacePinnedPreviewIndex == displayIndex {
                            spacePinnedPreviewIndex = nil
                        }
                    }
                )
            )
    }
    
    private func spacePinnedInsertionIndex(before displayIndex: Int) -> Int {
        let all = browserManager.tabManager.spacePinnedTabs(for: space.id)
        guard !all.isEmpty else { return 0 }

        if displayIndex <= 0 { return 0 }
        if displayIndex >= spacePinnedItems.count { return all.count }

        let nextItem = spacePinnedItems[displayIndex]
        if let anchor = spacePinnedAnchorIndex(for: nextItem, within: all) {
            return max(0, min(anchor, all.count))
        }

        if displayIndex > 0 {
            let previousItem = spacePinnedItems[displayIndex - 1]
            if let previousAnchor = spacePinnedAnchorIndex(for: previousItem, within: all) {
                return max(0, min(previousAnchor + 1, all.count))
            }
        }

        return all.count
    }
    
    private func spacePinnedAnchorIndex(for item: AnyHashable, within all: [Tab]) -> Int? {
        if let tab = item as? Tab {
            return tab.index
        }
        
        if let folderWithTabs = item as? FolderWithTabs {
            let tabs = all.filter { $0.folderId == folderWithTabs.folder.id }
                .sorted { $0.index < $1.index }
            if let first = tabs.first {
                return first.index
            }
            return folderWithTabs.folder.index
        }
        
        return nil
    }
    
    private var newTabButtonSection: some View {
        NewTabButton()
            .padding(.top, 8)
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { tabs.count },
                    draggedItem: $draggedItem,
                    targetSection: .spaceRegular(space.id),
                    tabManager: browserManager.tabManager
                )
            )
    }

    private var newTabButtonSectionWithClear: some View {
        VStack(spacing: 0) {
            SpaceSeparator {
                // Clear all regular tabs for this space
                browserManager.tabManager.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)

            newTabButtonSection
        }
    }
    
    private var regularTabsList: some View {
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
            
            if split.isSplit,
               let leftId = split.leftTabId, let rightId = split.rightTabId,
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
        .padding(.top, 8)
        .onDrop(
            of: [.text],
            delegate: SidebarSectionDropDelegateSimple(
                itemsCount: { tabs.count },
                draggedItem: $draggedItem,
                targetSection: .spaceRegular(space.id),
                tabManager: browserManager.tabManager
            )
        )
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
                    draggedItem: $draggedItem,
                    onActivate: onActivateTab,
                    onClose: onCloseTab
                )
                .environmentObject(browserManager)
            } else if idx == secondIdx {
                EmptyView()
            } else {
                regularTabView(tab)
            }
        }
    }
    
    private func regularTabsView(currentTabs: [Tab]) -> some View {
        ForEach(currentTabs, id: \.id) { tab in
            regularTabView(tab)
        }
    }
    
    private func regularTabView(_ tab: Tab) -> some View {
        SpaceTab(
            tab: tab,
            action: { handleUserTabActivation(tab) },
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) }
        )
        .id(tab.id)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: TabPositionPreferenceKey.self, value: [tab.id: geometry.frame(in: .named("ScrollSpace"))])
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            regularTabContextMenu(tab)
        }
        .onTabDrag(tab.id, draggedItem: $draggedItem)
        .opacity(draggedItem == tab.id ? 0.0 : 1.0)
        .onDrop(
            of: [.text],
            delegate: SidebarTabDropDelegateSimple(
                item: tab,
                draggedItem: $draggedItem,
                targetSection: .spaceRegular(space.id),
                tabManager: browserManager.tabManager
            )
        )
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
        ZStack { Color.clear.frame(height: 50) }
            .padding(.top, 8)
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { 0 },
                    draggedItem: $draggedItem,
                    targetSection: .spaceRegular(space.id),
                    tabManager: browserManager.tabManager
                )
            )
    }
    
    // MARK: - Folder Management
    
    private func renameFolder(_ folder: TabFolder) {
        print("Rename folder: \(folder.name)")
    }
    
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
