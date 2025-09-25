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

struct SpaceView: View {
    let space: Space
    let isActive: Bool
    let width: CGFloat
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var draggedItem: UUID? = nil
    @State private var spacePinnedPreviewIndex: Int? = nil

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    @EnvironmentObject var splitManager: SplitViewManager
    
    // Get tabs directly from TabManager to ensure proper observation
    private var tabs: [Tab] {
        browserManager.tabManager.tabs(in: space)
    }
    
    private var spacePinnedTabs: [Tab] {
        browserManager.tabManager.spacePinnedTabs(for: space.id)
    }

    private var folders: [TabFolder] {
        browserManager.tabManager.folders(for: space.id)
    }

    private var spacePinnedItems: [AnyHashable] {
        // Group space-pinned tabs by folderId and create the display structure
        var items: [AnyHashable] = []

        // Group tabs by folderId
        let tabsByFolderId = Dictionary(grouping: spacePinnedTabs) { tab in
            tab.folderId
        }

        // First, add folders with their tabs embedded
        for folder in folders {
            // Get tabs that belong to this folder
            let folderTabs = tabsByFolderId[folder.id]?.sorted { $0.index < $1.index } ?? []

            // Create a folder wrapper that contains both the folder and its tabs
            items.append(FolderWithTabs(folder: folder, tabs: folderTabs))
        }

        // Then, add space-pinned tabs that are not in any folder
        if let nonFolderTabs = tabsByFolderId[nil] {
            let sortedTabs = nonFolderTabs.sorted { $0.index < $1.index }
            items.append(contentsOf: sortedTabs)
        }

        return items
    }
    
    // (no coordinate spaces needed for simple DnD)
    
    var body: some View {
        VStack(spacing: 8) {
            SpaceTitle(space: space)

            if !spacePinnedTabs.isEmpty || !tabs.isEmpty {
                SpaceSeparator()
                    .padding(.horizontal, 8)
            }

            mainContentContainer
        }
        .frame(minWidth: 0, maxWidth: width)
        .contentShape(Rectangle())
        .scrollTargetLayout()
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
        .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
            draggedItem = nil
        }
    }

    private var mainContentContainer: some View {
        VStack(spacing: 0) {
            pinnedTabsSection
            newTabButtonSection
            regularTabsSection
        }
    }

    private var pinnedTabsSection: some View {
        Group {
            if !spacePinnedTabs.isEmpty {
                pinnedTabsList
            } else {
                emptyPinnedDropTarget
            }
        }
    }

    private var pinnedTabsList: some View {
        let items = spacePinnedItems

        return VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                spacePinnedSpacer(before: index)

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
                } else if let tab = item as? Tab {
                    pinnedTabView(tab)
                }
            }

            spacePinnedSpacer(before: items.count)
        }
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
            action: { onActivateTab(tab) },
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) }
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
            .frame(height: 8)
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

    private var regularTabsSection: some View {
        ScrollView {
            VStack(spacing: 2) {
                if !tabs.isEmpty {
                    regularTabsList
                } else {
                    emptyRegularTabsDropTarget
                }
            }
            .animation(.easeInOut(duration: 0.15), value: tabs.count)
        }
        .frame(minWidth: 0, maxWidth: width)
        .onDrop(
            of: [.text],
            delegate: SidebarSectionDropDelegateSimple(
                itemsCount: { tabs.count },
                draggedItem: $draggedItem,
                targetSection: .spaceRegular(space.id),
                tabManager: browserManager.tabManager
            )
        )
        .contentShape(Rectangle())
    }

    private var regularTabsList: some View {
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
            
            // Small zone at end of tab list to capture window drag
            Color.clear
                .contentShape(Rectangle())
                .conditionalWindowDrag()
                .frame(height: 100)
        }
        .frame(minWidth: 0, maxWidth: width)
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
            action: { onActivateTab(tab) },
            onClose: { onCloseTab(tab) },
            onMute: { onMuteTab(tab) }
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

    // MARK: - Folder Management Helper Methods

    private func renameFolder(_ folder: TabFolder) {
        // TODO: Implement folder rename dialog
        // For now, just log the action
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

    // Removed insertion overlays and geometry preference keys (simplified DnD)
}
