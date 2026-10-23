// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarHoverOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit
import NookDesign
import NookWeb
import NookTabsCore
import NookUI

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.nookSettings) var nookSettings

    private let cornerRadius: CGFloat = NookDesign.Radius.lg
    private let horizontalInset: CGFloat = NookDesign.Spacing.md
    private let verticalInset: CGFloat = NookDesign.Spacing.md

    var body: some View {
        // Only render overlay plumbing when the real sidebar is collapsed
        if !windowState.isSidebarVisible {
            ZStack(alignment: nookSettings.sidebarPosition == .left ? .leading : .trailing) {
                // Edge hover hotspot
                Color.clear
                    .frame(width: hoverManager.triggerWidth)
                    .contentShape(Rectangle())
                    .onHoverTracking { isIn in
                        if isIn && !windowState.isSidebarVisible {
                            withAnimation(NookDesign.Motion.quick) {
                                hoverManager.isOverlayVisible = true
                            }
                        }
                        NSCursor.arrow.set()
                    }

                if hoverManager.isOverlayVisible {
                    SpacesSideBarView()
                        .frame(width: windowState.sidebarWidth)
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .environment(commandPalette)
                        .environmentObject(browserManager.gradientColorManager)
                        .frame(maxHeight: .infinity)
                        // Clip the floating surface, not descendants: the expanded address
                        // panel is anchored here but deliberately extends over the page.
                        .background {
                            sidebarBackground
                                .nookFloatingSurface(in: NookDesign.Radius.shape(cornerRadius))
                        }
                        .alwaysArrowCursor()
                        .padding(nookSettings.sidebarPosition == .left ? .leading : .trailing, horizontalInset)
                        .padding(.vertical, verticalInset)
                        .transition(
                            .move(edge: nookSettings.sidebarPosition == .left ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: nookSettings.sidebarPosition == .left ? .topLeading : .topTrailing)
            // Container remains passive; only overlay/hotspot intercept
        }
    }

    /// The docked sidebar's own background, so the overlay reads as the same sidebar.
    private var sidebarBackground: some View {
        let appearance = windowState.isIncognito
            ? SpaceAppearance(accentHex: "#8E8E93")
            : windowState.spaceCreationAppearance ?? windowState.spaceID.flatMap { browserManager.tabs.space($0)?.resolvedAppearance } ?? SpaceAppearance(accentHex: "#7C7C7C")
        let isAgent = !windowState.isCreatingSpace && windowState.spaceID != nil && windowState.spaceID == browserManager.tabs.agentSpaceID
        return SpaceThemeSurface(appearance: appearance, isActive: true)
            .overlay(windowState.isIncognito ? NookDesign.Surface.privateTint : Color.clear)
            .overlay(Rectangle().fill(NookDesign.Surface.agentGradient).opacity(isAgent ? NookDesign.Surface.agentChromeOpacity : 0))
    }
}
