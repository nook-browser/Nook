//
//  SidebarHoverOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

struct SidebarHoverOverlayView: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(HoverSidebarManager.self) private var hoverManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) private var settings

    private var overlayWidth: CGFloat {
        windowState.isSidebarVisible ? windowState.sidebarWidth : browserManager.getSavedSidebarWidth(for: windowState)
    }
    private let cornerRadius: CGFloat = 12
    private let horizontalInset: CGFloat = 7
    private let verticalInset: CGFloat = 7

    var body: some View {
        // Only render overlay plumbing when the real sidebar is collapsed
        if !windowState.isSidebarVisible {
            ZStack(alignment: settings.sidebarPosition == .left ? .leading : .trailing) {
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
                        .environment(browserManager)
                        .environment(windowState)
                        .nookSettings(settings)
                        .frame(width: overlayWidth)
                        .frame(maxHeight: .infinity)
                        .background(BlurEffectView(material: .contentBackground, state: .active))
                        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                        // Force arrow cursor for the entire overlay region
                        .alwaysArrowCursor()
                        .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 0)
                        .padding(settings.sidebarPosition == .left ? .leading : .trailing, horizontalInset)
                        .padding(.vertical, verticalInset)
                        .transition(
                            .move(edge: settings.sidebarPosition == .left ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.sidebarPosition == .left ? .topLeading : .topTrailing)
            // Container remains passive; only overlay/hotspot intercept
        }
    }
}
