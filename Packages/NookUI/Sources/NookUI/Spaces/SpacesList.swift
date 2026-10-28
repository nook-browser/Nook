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
            let count = CGFloat(max(visibleSpaces.count, 1))
            let width = max(geometry.size.width, 0)
            // Compress gaps first, then targets to the minimum; overflow remains scrollable.
            let gap = min(NookDesign.Spacing.md, max(0, (width - count * NookDesign.Size.spaceTarget) / max(count - 1, 1)))
            let target = max(NookDesign.Size.spaceTargetMin, min(NookDesign.Size.spaceTarget, width / count))
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .center, spacing: gap) {
                        ForEach(visibleSpaces, id: \.id) { space in
                            SpacesListItem(
                                space: space,
                                isActive: windowState.spaceID == space.id,
                                selection: selection(of: space.id),
                                isFaded: false,
                                buttonSize: target
                            )
                            .environment(windowState)
                            .id(space.id)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: geometry.size.width, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.center)
                .onChange(of: windowState.spaceID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                // Keep the scrolling content at button height, then center that viewport
                // in the footer. Extra footer height must not become scrollable content.
                .frame(height: NookDesign.Size.spaceTarget)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
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
