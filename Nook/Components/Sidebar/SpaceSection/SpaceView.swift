//
//  SpaceView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SpaceView: View {
    let space: Space
    let isActive: Bool
    let width: CGFloat
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var draggedItem: UUID? = nil
    
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
            windowDragSpacer
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
        VStack(spacing: 2) {
            ForEach(spacePinnedTabs, id: \.id) { tab in
                pinnedTabView(tab)
            }
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [.text],
            delegate: SidebarSectionDropDelegateSimple(
                itemsCount: { spacePinnedTabs.count },
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
    
    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }
    
    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }

    private var windowDragSpacer: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 30)
            .contentShape(Rectangle())
            .conditionalWindowDrag()
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 8),
                alignment: .top
            )
    }

    // Removed insertion overlays and geometry preference keys (simplified DnD)
}

