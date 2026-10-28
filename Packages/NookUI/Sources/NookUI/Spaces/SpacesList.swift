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
                ForEach(visibleSpaces, id: \.id) { space in
                    SpacesListItem(
                        space: space,
                        isActive: windowState.spaceID == space.id,
                        selection: selection(of: space.id),
                        isFaded: false,
                        buttonSize: size,
                        forceDot: compact
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
                    .clipped()
            }
        }
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
