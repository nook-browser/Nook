//
//  SidebarHeader.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI

/// Header section of the sidebar (window controls, navigation buttons, URL bar)
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    let isSidebarHovered: Bool
    @State private var sidebarWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: NookDesign.Spacing.sectionGap) {
            if nookSettings.topBarAddressView {
                windowControls
            }

            if !nookSettings.topBarAddressView {
                navigationButtons
                urlBar
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            sidebarWidth = newWidth
        }
    }

    private var windowControls: some View {
        SidebarWindowControlsView()
            .environmentObject(browserManager)
            .environment(windowState)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }

    private var navigationButtons: some View {
        HStack(spacing: NookDesign.Spacing.xxs) {
            NavButtonsView(effectiveSidebarWidth: sidebarWidth)
        }
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .frame(height: NookDesign.Size.navRow)
    }

    private var urlBar: some View {
        URLBarView(isSidebarHovered: isSidebarHovered)
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }
}

// MARK: - Sidebar Window Controls (Top Bar Mode)
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button("Toggle Sidebar", systemImage: nookSettings.sidebarPosition == .left ? "sidebar.left" : "sidebar.right") {
                browserManager.toggleSidebar(for: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle())
            .foregroundStyle(Color.primary)

            if nookSettings.showAIAssistant {
                Button("Toggle AI Assistant", systemImage: "sparkle") {
                    browserManager.toggleAISidebar(for: windowState)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NookIconButtonStyle())
                .foregroundStyle(Color.primary)
            }

            Spacer()
        }
        .frame(height: NookDesign.Size.navRow)
    }
}
