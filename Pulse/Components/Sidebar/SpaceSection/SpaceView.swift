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

    var body: some View {
        VStack(spacing: 8) {
            SpaceTittle(space: space)

            if !tabs.isEmpty {
                SpaceSeparator()
            }

            NewTabButton()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tabs, id: \.id) { tab in
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
                                onPinTab(tab)
                            } label: {
                                Label("Pin tab", systemImage: "pin")
                            }
                            
                            Button {
                                onCloseTab(tab)
                            } label: {
                                Label("Close tab", systemImage: "xmark")
                            }
                        }
                        .onDrag {
                            NSItemProvider(
                                object: tab.id.uuidString as NSString
                            )
                        }
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
