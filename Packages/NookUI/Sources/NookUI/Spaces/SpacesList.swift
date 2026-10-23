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
                    HStack(spacing: 3) {
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
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)

            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center)

        }
        .animation(NookDesign.Motion.standard, value: visibleSpaces.count)
    }


}
