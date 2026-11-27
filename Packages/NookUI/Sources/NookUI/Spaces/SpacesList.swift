// Licensed under GPL-3.0. See LICENSE.
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
    @State private var hoveredIndex: Int?

    private var visibleSpaces: [SpaceRecord] {
        tabs.switchableSpaces(for: windowState)
    }

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            // Items shrink to fit as Arc's dock does. At the 8 pt floor a row that still does
            // not fit scrolls sideways, so every space stays reachable.
            let count = visibleSpaces.count
            let width = max(geometry.size.width, 0)
            let size = SpaceSwitcher.itemSize(available: width, count: count)
            let gap = SpaceSwitcher.gap(available: width, count: count, size: size)
            let compact = SpaceSwitcher.isCompact(itemSize: size)
            let overflows = size * CGFloat(count) > width
            let row = HStack(alignment: .center, spacing: gap) {
                ForEach(Array(visibleSpaces.enumerated()), id: \.element.id) { index, space in
                    SpacesListItem(
                        space: space,
                        isActive: windowState.spaceID == space.id,
                        selection: selection(of: space.id),
                        isFaded: false,
                        buttonSize: size,
                        forceDot: compact,
                        onHoverChange: { hovering in
                            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
                        }
                    )
                    .environment(windowState)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            if overflows {
                ScrollView(.horizontal, showsIndicators: false) { row }
                    .frame(width: width, height: geometry.size.height)
            } else {
                row
                    .frame(width: width, height: geometry.size.height, alignment: .center)
            }
        }
        .overlay(alignment: .top) {
            if let hoveredIndex, visibleSpaces.indices.contains(hoveredIndex) {
                SpaceHoverPill(
                    space: visibleSpaces[hoveredIndex],
                    shortcutNumber: hoveredIndex < 9 ? hoveredIndex + 1 : nil
                )
                .fixedSize()
                .offset(y: -(NookDesign.Size.iconButton + NookDesign.Spacing.sm))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(NookDesign.Motion.quick, value: hoveredIndex)
        .animation(NookDesign.Motion.standard, value: visibleSpaces.count)
    }

    /// How selected a dot looks, 0 to 1: the swipe's position while one runs, else the space shown.
    private func selection(of id: UUID) -> Double {
        guard let swipe = windowState.spaceSwipe else { return windowState.spaceID == id ? 1 : 0 }

        if swipe.from == swipe.to { return id == swipe.from ? 1 : 0 }
        if id == swipe.from { return 1 - swipe.progress }
        return id == swipe.to ? swipe.progress : 0
    }
}

/// Arc-style floating pill shown above a hovered space icon in the bottom bar.
private struct SpaceHoverPill: View {
    let space: SpaceRecord
    let shortcutNumber: Int?

    var body: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Text(space.name)
                .font(NookDesign.Font.label)
                .foregroundStyle(.white)
                .lineLimit(1)

            if let profile = space.profileName, !profile.isEmpty {
                HStack(spacing: NookDesign.Spacing.xs) {
                    Image(systemName: "face.smiling")
                        .font(NookDesign.Font.captionStrong)
                    Text(profile)
                        .font(NookDesign.Font.captionStrong)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, NookDesign.Spacing.sm)
                .padding(.vertical, NookDesign.Spacing.xxs)
                .background(Color.white.opacity(0.85), in: Capsule())
            }

            if let shortcutNumber {
                HStack(spacing: NookDesign.Spacing.xxs) {
                    keycap("⌃")
                    keycap("\(shortcutNumber)")
                }
            }
        }
        .padding(.horizontal, NookDesign.Spacing.md)
        .frame(height: NookDesign.Size.iconButton)
        .background(Color.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: NookDesign.Size.hairlineWidth))
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(NookDesign.Font.captionStrong)
            .foregroundStyle(.black)
            .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
            .background(Color.white.opacity(0.85), in: NookDesign.Radius.shape(NookDesign.Radius.xs))
    }
}
