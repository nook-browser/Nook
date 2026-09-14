//
//  SpacesList.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

struct SpacesList: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var availableWidth: CGFloat = 0
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false

    private var layoutMode: SpacesListLayoutMode {
        let spaces = windowState.isIncognito
            ? windowState.ephemeralSpaces
            : tabManager.spaces
        return SpacesListLayoutMode.determine(
            spacesCount: spaces.count,
            availableWidth: availableWidth
        )
    }

    private var visibleSpaces: [Space] {
        if windowState.isIncognito {
            return windowState.ephemeralSpaces
        }
        return tabManager.spaces
    }

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                availableWidth = newWidth
            }
            .overlay{
                    HStack(spacing: 0) {
                        ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                            SpacesListItem(
                                space: space,
                                isActive: windowState.currentSpaceId == space.id,
                                compact: layoutMode == .compact,
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
                            .environmentObject(browserManager)
                            .environment(windowState)
                            .id(space.id)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                            
                            if index != visibleSpaces.count - 1 {
                                Spacer()
                                    .frame(minWidth: NookDesign.Size.hairlineWidth, maxWidth: NookDesign.Spacing.md)
                                    .layoutPriority(-1)
                            }
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
                           hoveredId != windowState.currentSpaceId,
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

// MARK: - Layout Mode

enum SpacesListLayoutMode {
    case normal    // Full icons with spacing
    case compact   // Dots for inactive, icons for active

    static func determine(spacesCount: Int, availableWidth: CGFloat) -> Self {
        guard spacesCount > 0 else { return .normal }

        // Measurements for NookIconButtonStyle at its default size
        let buttonSize = NookDesign.Size.iconButton
        let minSpacing = NookDesign.Spacing.xs

        // Normal mode: all icons visible with minimum spacing
        let normalMinWidth = (CGFloat(spacesCount) * buttonSize) + (CGFloat(spacesCount - 1) * minSpacing)

        // Choose mode: switch to compact whenever normal mode would be too cramped
        return availableWidth >= normalMinWidth ? .normal : .compact
    }
}
