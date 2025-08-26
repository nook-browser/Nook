//
//  SpaceView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SpaceView: View {
    let space: Space
    let isActive: Bool
    let width: CGFloat
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    
    // Get tabs directly from TabManager to ensure proper observation
    private var tabs: [Tab] {
        browserManager.tabManager.tabs(in: space)
    }
    
    private var spacePinnedTabs: [Tab] {
        browserManager.tabManager.spacePinnedTabs(for: space.id)
    }

    var body: some View {
        VStack(spacing: 8) {
            SpaceTittle(space: space)

            if !spacePinnedTabs.isEmpty || !tabs.isEmpty {
                SpaceSeparator()
            }

            NewTabButton()
            ScrollView {
                VStack(spacing: 2) {
                    // Space-level pinned tabs
                    if !spacePinnedTabs.isEmpty {
                        ForEach(spacePinnedTabs.indices, id: \.self) { index in
                            let tab = spacePinnedTabs[index]
                            SpaceTab(
                                tab: tab,
                                action: { onActivateTab(tab) },
                                onClose: { onCloseTab(tab) },
                                onMute: { onMuteTab(tab) }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .contextMenu {
                                Button {
                                    browserManager.tabManager.unpinTabFromSpace(tab)
                                } label: {
                                    Label("Unpin from Space", systemImage: "pin.slash")
                                }
                                
                                Button {
                                    onPinTab(tab) // This will convert to global pinned
                                } label: {
                                    Label("Pin Globally", systemImage: "pin.circle")
                                }
                                
                                Divider()
                                
                                Button {
                                    onCloseTab(tab)
                                } label: {
                                    Label("Close tab", systemImage: "xmark")
                                }
                            }
                            .draggableTab(
                                tab: tab,
                                container: .spacePinned(space.id),
                                index: index,
                                dragManager: dragManager ?? TabDragManager()
                            )
                        }
                        
                        // Divider between space pinned and regular tabs
                        if !tabs.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                    
                    // Regular tabs
                    ForEach(tabs.indices, id: \.self) { index in
                        let tab = tabs[index]
                        SpaceTab(
                            tab: tab,
                            action: { onActivateTab(tab) },
                            onClose: { onCloseTab(tab) },
                            onMute: { onMuteTab(tab) }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .contextMenu {
                            Button {
                                onMoveTabUp(tab)
                            } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .disabled(isFirstTab(tab))
                            
                            Button {
                                onMoveTabDown(tab)
                            } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                            .disabled(isLastTab(tab))
                            
                            Divider()
                            
                            Button {
                                browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id)
                            } label: {
                                Label("Pin to Space", systemImage: "pin")
                            }
                            
                            Button {
                                onPinTab(tab)
                            } label: {
                                Label("Pin Globally", systemImage: "pin.circle")
                            }
                            
                            Button {
                                onCloseTab(tab)
                            } label: {
                                Label("Close tab", systemImage: "xmark")
                            }
                        }
                        .draggableTab(
                            tab: tab,
                            container: .spaceRegular(space.id),
                            index: index,
                            dragManager: dragManager ?? TabDragManager()
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: tabs.count)
            }
            Spacer()
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .backgroundDraggable()
        .scrollTargetLayout()
    }
    
    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }
    
    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }
}
