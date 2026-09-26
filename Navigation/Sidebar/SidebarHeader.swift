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

/// Header section of the sidebar containing the URL bar.
struct SidebarHeader: View {
    @Environment(\.nookSettings) var nookSettings
    let isSidebarHovered: Bool

    var body: some View {
        if !nookSettings.topBarAddressView {
            urlBar
        }
    }

    private var urlBar: some View {
        URLBarView(isSidebarHovered: isSidebarHovered)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }
}

// MARK: - Sidebar Window Controls
/// The sidebar and AI toggles, grouped as one toolbar control.
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
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
        .imageScale(.large)
        .buttonStyle(NookIconButtonStyle())
        .frame(height: NookDesign.Size.iconButton)
        .background(DoubleClickView { NSApp.keyWindow?.performZoom(nil) })
    }
}
