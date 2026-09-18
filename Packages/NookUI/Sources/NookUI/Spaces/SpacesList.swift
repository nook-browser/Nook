// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SpacesList.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb

public struct SpacesList: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false

    private var visibleSpaces: [SpaceRecord] {
        tabs.switchableSpaces(for: windowState)
    }

    public init() {}

    public var body: some View {
        Color.clear
            .overlay{
                    HStack(spacing: NookDesign.Spacing.xxs) {
                        ForEach(visibleSpaces, id: \.id) { space in
                            SpacesListItem(
                                space: space,
                                isActive: windowState.spaceID == space.id,
                                isFaded: false,
                                onHoverChange: { isHovering in
                                    if isHovering {
                                        hoveredSpaceId = space.id
                                        if showPreview {
                                        } else {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                                if hoveredSpaceId == space.id && isHoveringList {
                                                    withAnimation(NookDesign.Motion.standard) {
                                                        showPreview = true
                                                    }
                                                }
                                            }
                                        }
                                    } else if hoveredSpaceId == space.id {
                                        hoveredSpaceId = nil
                                    }
                                }
                            )
                            .environment(windowState)
                            .id(space.id)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .onHoverTracking { hovering in
                        isHoveringList = hovering
                        if !hovering {
                            showPreview = false
                            hoveredSpaceId = nil
                        }
                    }
                    .overlay(alignment: .top) {
                        if showPreview,
                           let hoveredId = hoveredSpaceId,
                           hoveredId != windowState.spaceID,
                           let hoveredSpace = visibleSpaces.first(where: { $0.id == hoveredId }) {
                            Text(hoveredSpace.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .id(hoveredSpace.id)
                                .transition(.blur.animation(NookDesign.Motion.standard))
                                .offset(y: -NookDesign.Spacing.xxl)
                        }
                    }
            }
            .animation(NookDesign.Motion.standard, value: visibleSpaces.count)
    }


}
