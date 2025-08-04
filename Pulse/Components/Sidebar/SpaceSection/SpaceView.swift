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
                        .contextMenu {
                            Button {
                                onCloseTab(tab)
                            } label: {
                                Label("Close tab", systemImage: "xmark")
                            }
                            Button {
                                onPinTab(tab)
                            } label: {
                                Label("Pin tab", systemImage: "pin")
                            }
                        }
                        .onDrag {
                            NSItemProvider(
                                object: tab.id.uuidString as NSString
                            )
                        }
                    }
                }
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
}
