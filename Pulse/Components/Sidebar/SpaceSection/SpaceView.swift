//
//  SpaceView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct SpaceView: View {
    let space: Space
    let tabs: [Tab]
    let isActive: Bool
    let width: CGFloat

    let onSetActive: () -> Void
    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void

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
                            tabName: tab.name,
                            tabURL: tab.url.absoluteString,
                            tabIcon: tab.favicon,
                            isActive: tab.isCurrentTab,
                            action: { onActivateTab(tab) },
                            onClose: { onCloseTab(tab) }
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
        .onScrollVisibilityChange(threshold: 0.5) { isVisible in
            if isVisible {
                onSetActive()
            }
        }
    }
    
    private func isFirstTab(_ tab: Tab) -> Bool {
        return tabs.first?.id == tab.id
    }
    
    private func isLastTab(_ tab: Tab) -> Bool {
        return tabs.last?.id == tab.id
    }
}
