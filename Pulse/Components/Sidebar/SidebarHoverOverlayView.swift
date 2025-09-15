//
//  SidebarHoverOverlayView.swift
//  Pulse
//
//  Created by Codex on 2025-09-13.
//

import SwiftUI
import AppKit

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager

    private var overlayWidth: CGFloat {
        browserManager.isSidebarVisible ? browserManager.sidebarWidth : browserManager.getSavedSidebarWidth()
    }

    var body: some View {
        // Only render overlay plumbing when the real sidebar is collapsed
        if !browserManager.isSidebarVisible {
            ZStack(alignment: .leading) {
                // Optional in-window hover hotspot (helps when app is active)
                Color.clear
                    .frame(width: hoverManager.triggerWidth)
                    .contentShape(Rectangle())
                    .onHover { isIn in
                        if isIn && !browserManager.isSidebarVisible {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoverManager.isOverlayVisible = true
                            }
                        }
                    }
                    .allowsHitTesting(true)

                // The overlay sidebar (full-featured SidebarView forced visible)
                SidebarView(forceVisible: true, forcedWidth: overlayWidth)
                    .frame(maxHeight: .infinity)
                    .background(
                        // Match app material choice so overlay feels native
                        BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active)
                            .ignoresSafeArea()
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1)
                    }
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 0)
                    .offset(x: hoverManager.isOverlayVisible ? 0 : -overlayWidth - 12)
                    .animation(.easeInOut(duration: 0.18), value: hoverManager.isOverlayVisible)
                    // Overlay must be fully interactive while visible
                    .allowsHitTesting(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Only capture input while the overlay is visible
            .allowsHitTesting(hoverManager.isOverlayVisible)
        }
    }
}
