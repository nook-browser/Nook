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

    private var dynamicSpacing: CGFloat {
        SpacesListLayoutMode.calculateSpacing(
            for: layoutMode,
            spacesCount: browserManager.tabManager.spaces.count,
            availableWidth: availableWidth
        )
    }

    private var visibleSpaces: [Space] {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: dynamicSpacing) {
                        ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                            SpacesListItem(
                                space: space,
                                isActive: windowState.currentSpaceId == space.id,
                                compact: layoutMode == .compact,
                                isFaded: false,
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
                    .onHover { hovering in
                        isHoveringList = hovering
                        if !hovering {
                            showPreview = false
                            hoveredSpaceId = nil
                        }
                    }
                    .overlay(alignment: .top) {
                        // Preview text positioned above the icons
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
                                .offset(y: -20)
                        }
                    }
                }
                .defaultScrollAnchor(.center)
                .scrollBounceBehavior(.basedOnSize)
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

        // Normal mode: all icons visible
        let normalTotalWidth = (CGFloat(spacesCount) * buttonSize) + (CGFloat(spacesCount - 1) * minSpacing)

        // Compact mode: 1 active icon + (n-1) dots
        let dotSize: CGFloat = 6.0
        let totalDots = spacesCount - 1
        let compactTotalWidth = buttonSize + (CGFloat(totalDots) * dotSize) + (CGFloat(spacesCount - 1) * minSpacing)

        // Choose mode based on what fits
        if availableWidth >= normalTotalWidth {
            return .normal
        } else if availableWidth >= compactTotalWidth {
            return .compact
        } else {
            // Even compact doesn't fit perfectly, but use compact anyway
            return .compact
        }
    }

    static func calculateSpacing(for mode: Self, spacesCount: Int, availableWidth: CGFloat) -> CGFloat {
        guard spacesCount > 1 else { return 8.0 }

        let maxSpacing: CGFloat = 8.0
        let minSpacing: CGFloat = 4.0

        switch mode {
        case .normal:
            let buttonSize: CGFloat = 32.0
            let totalButtonSpace = CGFloat(spacesCount) * buttonSize
            let remainingSpace = availableWidth - totalButtonSpace
            let gapCount = CGFloat(max(1, spacesCount - 1))
            let calculatedSpacing = remainingSpace / gapCount
            return max(minSpacing, min(maxSpacing, calculatedSpacing))

        case .compact:
            // In compact mode, try to distribute space more evenly
            let buttonSize: CGFloat = 32.0
            let dotSize: CGFloat = 6.0
            // 1 icon + (n-1) dots
            let totalItemSpace = buttonSize + (CGFloat(spacesCount - 1) * dotSize)
            let remainingSpace = availableWidth - totalItemSpace
            let gapCount = CGFloat(max(1, spacesCount - 1))
            let calculatedSpacing = remainingSpace / gapCount
            return max(minSpacing, min(maxSpacing, calculatedSpacing))
        }
    }
}
