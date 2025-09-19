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
    let isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
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
        return VStack(spacing: 8) {
            SpaceTittle(space: space)
                .padding(.horizontal, 8)
            
            if !spacePinnedTabs.isEmpty || !tabs.isEmpty {
                SpaceSeparator(isHovering: isSidebarHovered)
                    .padding(.horizontal, 8)
            }
            
            // Unified container around Pinned + New Tab + Regular to bridge gaps
            VStack(spacing: 0) {
                // Space-level pinned tabs FIRST
                if !spacePinnedTabs.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(spacePinnedTabs, id: \.id) { tab in
                            SpaceTab(
                                tab: tab,
                                action: { onActivateTab(tab) },
                                onClose: { onCloseTab(tab) },
                                onMute: { onMuteTab(tab) }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .contextMenu {
                                Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right) } label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
                                Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left) } label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
                                Divider()
                                Button { browserManager.tabManager.unpinTabFromSpace(tab) } label: { Label("Unpin from Space", systemImage: "pin.slash") }
                                Button { onPinTab(tab) } label: { Label("Pin Globally", systemImage: "pin.circle") }
                                Divider()
                                Button { onCloseTab(tab) } label: { Label("Close tab", systemImage: "xmark") }
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
                } else {
                    // Empty pinned section drop target
                    ZStack { Color.clear.frame(height: 1) }
                        .padding(.bottom, 8)
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

                NewTabButton()
                    .onDrop(
                        of: [.text],
                        delegate: SidebarSectionDropDelegateSimple(
                            itemsCount: { tabs.count },
                            draggedItem: $draggedItem,
                            targetSection: .spaceRegular(space.id),
                            tabManager: browserManager.tabManager
                        )
                    )

                // Regular tabs
                ScrollView {
                    VStack(spacing: 2) {
                        if !tabs.isEmpty {
                            VStack(spacing: 5) {
                                // Snapshot current regular tabs to keep indices stable during render
                                let currentTabs = tabs
                                let split = splitManager
                                if split.isSplit,
                                   let leftId = split.leftTabId, let rightId = split.rightTabId,
                                   let leftIdx = currentTabs.firstIndex(where: { $0.id == leftId }),
                                   let rightIdx = currentTabs.firstIndex(where: { $0.id == rightId }),
                                   leftIdx >= 0, rightIdx >= 0,
                                   leftIdx < currentTabs.count, rightIdx < currentTabs.count,
                                   leftIdx != rightIdx
                                {
                                    let firstIdx = min(leftIdx, rightIdx)
                                    let secondIdx = max(leftIdx, rightIdx)
                                    ForEach(Array(currentTabs.enumerated()), id: \.element.id) { pair in
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
                                            SpaceTab(
                                                tab: tab,
                                                action: { onActivateTab(tab) },
                                                onClose: { onCloseTab(tab) },
                                                onMute: { onMuteTab(tab) }
                                            )
                                            .transition(.move(edge: .top).combined(with: .opacity))
                                            .contextMenu {
                                                Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right) } label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
                                                Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left) } label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
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
                                    }
                                } else {
                                    ForEach(currentTabs, id: \.id) { tab in
                                        SpaceTab(
                                            tab: tab,
                                            action: { onActivateTab(tab) },
                                            onClose: { onCloseTab(tab) },
                                            onMute: { onMuteTab(tab) }
                                        )
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                        .contextMenu {
                                            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right) } label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
                                            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left) } label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
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
                                }
                            }
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
                        } else {
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
                    }
                    .animation(.easeInOut(duration: 0.15), value: tabs.count)
                }
                // Fallback drop target that covers the entire scroll area, including
                // the large empty region below the last tab. Drops here append to end.
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
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        // Keep page width equal to the whole sidebar
        .frame(width: width)
        .contentShape(Rectangle())
        // Avoid window-drag gestures in the sidebar content area
        .scrollTargetLayout()
        .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
            draggedItem = nil
        }
        
        func isFirstTab(_ tab: Tab) -> Bool {
            return tabs.first?.id == tab.id
        }
        
        func isLastTab(_ tab: Tab) -> Bool {
            return tabs.last?.id == tab.id
        }
    }
    
    // Removed insertion overlays and geometry preference keys (simplified DnD)
}
