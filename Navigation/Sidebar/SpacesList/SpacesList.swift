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
        SpacesListLayoutMode.determine(
            spacesCount: browserManager.tabManager.spaces.count,
            availableWidth: availableWidth
        )
    }

    private var visibleSpaces: [Space] {
        let allSpaces = browserManager.tabManager.spaces

        guard layoutMode == .minimal,
              let currentSpaceId = windowState.currentSpaceId,
              let currentIndex = allSpaces.firstIndex(where: { $0.id == currentSpaceId })
        else {
            return allSpaces
        }

        return buildCarousel(from: allSpaces, currentIndex: currentIndex)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Preview text for hovered non-active space
            if showPreview,
               let hoveredId = hoveredSpaceId,
               hoveredId != windowState.currentSpaceId,
               let hoveredSpace = browserManager.tabManager.spaces.first(where: { $0.id == hoveredId }) {
                Text(hoveredSpace.name)
                    .font(.caption)
                    .foregroundStyle(previewTextColor)
                    .opacity(0.7)
                    .lineLimit(1)
                    .id(hoveredSpace.id)
                    .transition(.blur.animation(.smooth(duration: 0.2)))
            } else {
                // Placeholder to maintain layout
                Text(" ")
                    .font(.caption)
            }

            HStack(spacing: layoutMode == .compact ? 4 : 8) {
                ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                    SpacesListItem(
                        space: space,
                        isActive: windowState.currentSpaceId == space.id,
                        compact: layoutMode == .compact || layoutMode == .minimal,
                        isFaded: layoutMode == .minimal && windowState.currentSpaceId != space.id,
                        onHoverChange: { isHovering in
                            if isHovering {
                                hoveredSpaceId = space.id
                                // If preview is already showing, update immediately
                                // Otherwise, show after delay
                                if showPreview {
                                    // Already showing, just swap the space
                                } else {
                                    // First time showing, add delay
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
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                availableWidth = newWidth
            }
            .onHover { hovering in
                isHoveringList = hovering
                if !hovering {
                    showPreview = false
                    hoveredSpaceId = nil
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.map(\.id))
    }

    // MARK: - Colors

    private var previewTextColor: Color {
        browserManager.gradientColorManager.isDark
            ? AppColors.spaceTabTextDark
            : AppColors.spaceTabTextLight
    }

    // MARK: - Helper Methods

    /// Build a carousel of 2-3 spaces centered on the current space
    private func buildCarousel(from spaces: [Space], currentIndex: Int) -> [Space] {
        var result: [Space] = []

        // Add left space if not at beginning
        if currentIndex > 0 {
            result.append(spaces[currentIndex - 1])
        }

        // Current space (always included)
        result.append(spaces[currentIndex])

        // Add right space if not at end
        if currentIndex < spaces.count - 1 {
            result.append(spaces[currentIndex + 1])
        }

        return result
    }
}

// MARK: - Layout Mode

enum SpacesListLayoutMode {
    case normal    // Full icons with spacing
    case compact   // Dots for inactive, icons for active
    case minimal   // Only show 3 spaces (carousel)

    static func determine(spacesCount: Int, availableWidth: CGFloat) -> Self {
        guard spacesCount > 0 else { return .normal }

        // Reserve space for left/right controls
        let availableForSpaces = max(availableWidth - 120, 0)

        // Each full icon needs ~32pt (24 cell + ~8 spacing)
        let neededForFull = CGFloat(spacesCount) * 32.0

        // When compact, dots need ~16pt each
        let neededForDots = CGFloat(spacesCount) * 16.0

        if neededForDots > availableForSpaces && spacesCount > 3 {
            return .minimal
        } else if neededForFull > availableForSpaces {
            return .compact
        } else {
            return .normal
        }
    }
}
