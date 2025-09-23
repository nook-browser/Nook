//
//  SidebarHoverOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
    @EnvironmentObject var windowState: BrowserWindowState

    private var overlayWidth: CGFloat {
        windowState.isSidebarVisible ? windowState.sidebarWidth : browserManager.getSavedSidebarWidth(for: windowState)
    }
    private let cornerRadius: CGFloat = 12
    private let horizontalInset: CGFloat = 8
    private let verticalInset: CGFloat = 10

    var body: some View {
        // Only render overlay plumbing when the real sidebar is collapsed
        if !windowState.isSidebarVisible {
            ZStack(alignment: .leading) {
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
                // Overlay sidebar inside a rounded, translucent container
                SidebarView(forceVisible: true, forcedWidth: overlayWidth)
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
                    .frame(width: overlayWidth)
                    .frame(maxHeight: .infinity)
                    .background(BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active))
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    // Force arrow cursor for the entire overlay region
                    .alwaysArrowCursor()
                    .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 0)
                    .padding(.leading, horizontalInset)
                    .padding(.vertical, verticalInset)
                    .offset(x: hoverManager.isOverlayVisible ? 0 : -(overlayWidth + horizontalInset + 16))
                    .animation(.easeInOut(duration: 0.2), value: hoverManager.isOverlayVisible)
                    .allowsHitTesting(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Container remains passive; only overlay/hotspot intercept
        }
    }
}
