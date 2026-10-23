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
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(visibleSpaces, id: \.id) { space in
                        SpacesListItem(
                            space: space,
                            isActive: windowState.spaceID == space.id,
                            isFaded: false
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
            // Keep the scrolling content at button height, then center that viewport
            // in the footer. Extra footer height must not become scrollable content.
            .frame(height: 32)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .animation(NookDesign.Motion.standard, value: visibleSpaces.count)
    }
}
