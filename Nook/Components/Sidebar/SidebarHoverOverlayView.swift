//
//  SidebarHoverOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import UniversalGlass
import AppKit

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings

    private var overlayWidth: CGFloat {
        windowState.isSidebarVisible ? windowState.sidebarWidth : browserManager.getSavedSidebarWidth(for: windowState)
    }
    private let cornerRadius: CGFloat = 12
    private let horizontalInset: CGFloat = 7
    private let verticalInset: CGFloat = 7

    var body: some View {
        // Only render overlay plumbing when the real sidebar is collapsed
        if !windowState.isSidebarVisible {
            ZStack(alignment: nookSettings.sidebarPosition == .left ? .leading : .trailing) {
                // Edge hover hotspot
                Color.clear
                    .frame(width: hoverManager.triggerWidth)
                    .contentShape(Rectangle())
                    .onHover { isIn in
                        if isIn && !windowState.isSidebarVisible {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoverManager.isOverlayVisible = true
                            }
                        }
                        NSCursor.arrow.set()
                    }

                if hoverManager.isOverlayVisible {
                    SidebarView(forceVisible: true, forcedWidth: overlayWidth)
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .frame(width: overlayWidth)
                        .frame(maxHeight: .infinity)
                        .background{
                            
                            
                            SpaceGradientBackgroundView()
                                .environmentObject(browserManager)
                                .environmentObject(browserManager.gradientColorManager)
                                .environment(windowState)
                                .clipShape(.rect(cornerRadius: cornerRadius))
                            
                                Rectangle()
                                    .fill(Color.clear)
                                    .universalGlassEffect(.regular.tint(Color(.windowBackgroundColor).opacity(0.35)), in: .rect(cornerRadius: cornerRadius))
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
}
