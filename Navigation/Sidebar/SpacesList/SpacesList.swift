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
        HStack(spacing: layoutMode == .compact ? 4 : 8) {
            ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                SpacesListItem(
                    space: space,
                    isActive: windowState.currentSpaceId == space.id,
                    compact: layoutMode == .compact || layoutMode == .minimal,
                    isFaded: layoutMode == .minimal && windowState.currentSpaceId != space.id
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            availableWidth = newWidth
        }
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.map(\.id))
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
