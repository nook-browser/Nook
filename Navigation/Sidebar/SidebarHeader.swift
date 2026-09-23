// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarHeader.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Header section of the sidebar (window controls, URL bar). Back, forward and reload sit in the
/// title row above it.
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    let isSidebarHovered: Bool

    var body: some View {
        VStack(spacing: NookDesign.Spacing.sectionGap) {
            windowControls

            if !nookSettings.topBarAddressView {
                urlBar
            }
        }
    }

    private var windowControls: some View {
        SidebarWindowControlsView()
            .environmentObject(browserManager)
            .environment(windowState)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }

    private var urlBar: some View {
        URLBarView(isSidebarHovered: isSidebarHovered)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }
}

// MARK: - Sidebar Window Controls
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        HStack(spacing: 0) {
            // One glass pill, the way the system groups neighbouring toolbar buttons.
            HStack(spacing: 0) {
                Button("Toggle Sidebar", systemImage: nookSettings.sidebarPosition == .left ? "sidebar.left" : "sidebar.right") {
                    browserManager.toggleSidebar(for: windowState)
                }

                if nookSettings.showAIAssistant {
                    Button("Toggle AI Assistant", systemImage: "sparkle") {
                        browserManager.toggleAISidebar(for: windowState)
                    }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle(radius: NookDesign.Size.iconButton / 2))
            .foregroundStyle(Color.primary)
            .nookControlGlass(in: Capsule())

            Spacer()
        }
        .frame(height: NookDesign.Size.navRow)
        .background(DoubleClickView { NSApp.keyWindow?.performZoom(nil) })
    }
}
