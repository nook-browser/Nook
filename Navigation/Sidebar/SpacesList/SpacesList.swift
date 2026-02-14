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
    @Environment(BrowserWindowState.self) private var windowState
    @State private var availableWidth: CGFloat = 0
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false

    private var layoutMode: SpacesListLayoutMode {
        let spaces = windowState.isIncognito
            ? windowState.ephemeralSpaces
            : browserManager.tabManager.spaces
        return SpacesListLayoutMode.determine(
            spacesCount: spaces.count,
            availableWidth: availableWidth
        )
    }

    private var visibleSpaces: [Space] {
        if windowState.isIncognito {
            return windowState.ephemeralSpaces
        }
        return browserManager.tabManager.spaces
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
                                                    withAnimation(.easeInOut(duration: 0.2)) {
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
                            
                            if index != Array(visibleSpaces.enumerated()).count - 1{
                                Spacer()
                                    .frame(minWidth: 1, maxWidth: 8)
                                    .layoutPriority(-1)
                            }
                        }
                    }
                    .onHover { hovering in
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
                                .foregroundStyle(previewTextColor)
                                .opacity(0.7)
                                .lineLimit(1)
                                .id(hoveredSpace.id)
                                .transition(.blur.animation(.smooth(duration: 0.2)))
                                .offset(y: -20)
                        }
                    }
            }
            .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
            .animation(.easeInOut(duration: 0.3), value: visibleSpaces.map(\.id))
    }

    private var previewTextColor: Color {
        browserManager.gradientColorManager.isDark
            ? AppColors.spaceTabTextDark
            : AppColors.spaceTabTextLight
    }

}

// MARK: - Layout Mode

enum SpacesListLayoutMode {
    case normal    // Full icons with spacing
    case compact   // Dots for inactive, icons for active

    static func determine(spacesCount: Int, availableWidth: CGFloat) -> Self {
        guard spacesCount > 0 else { return .normal }

        // Measurements for NavButtonStyle button with default .regular control size
        let buttonSize: CGFloat = 32.0  // NavButtonStyle .regular = 32pt
        let minSpacing: CGFloat = 4.0

        // Normal mode: all icons visible with minimum spacing
        let normalMinWidth = (CGFloat(spacesCount) * buttonSize) + (CGFloat(spacesCount - 1) * minSpacing)

        // Compact mode: 1 active icon + (n-1) dots with minimum spacing
        let dotSize: CGFloat = 6.0
        let totalDots = spacesCount - 1
        let compactMinWidth = buttonSize + (CGFloat(totalDots) * dotSize) + (CGFloat(totalDots) * minSpacing)

        // Choose mode: switch to compact only when normal mode would be too cramped
        // Stay in normal as long as we have at least minimum spacing
        if availableWidth >= normalMinWidth {
            return .normal
        } else if availableWidth >= compactMinWidth {
            return .compact
        } else {
            // Even compact doesn't fit perfectly, but use compact anyway
            return .compact
        }
    }
}
