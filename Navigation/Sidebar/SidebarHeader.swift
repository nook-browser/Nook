//
//  SidebarHeader.swift
//  Nook
//
//  Created by Claude on 15/11/2025.
//

import SwiftUI

/// Header section of the sidebar (window controls, navigation buttons, URL bar)
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    let sidebarWidth: CGFloat
    let isSidebarHovered: Bool

    var body: some View {
        VStack(spacing: 8) {
            if nookSettings.topBarAddressView {
                windowControls
            }

            if !nookSettings.topBarAddressView {
                navigationButtons
                urlBar
            }
        }
    }

    private var windowControls: some View {
        SidebarWindowControlsView()
            .environmentObject(browserManager)
            .environment(windowState)
            .padding(.horizontal, 8)
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            NavButtonsView(effectiveSidebarWidth: sidebarWidth)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private var urlBar: some View {
        URLBarView(isSidebarHovered: isSidebarHovered)
            .padding(.horizontal, 8)
    }
}

// MARK: - Sidebar Window Controls (Top Bar Mode)
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        HStack(spacing: 8) {
            MacButtonsView()
                .frame(width: 70)

            Button("Toggle Sidebar", systemImage: nookSettings.sidebarPosition == .left ? "sidebar.left" : "sidebar.right") {
                browserManager.toggleSidebar(for: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .foregroundStyle(Color.primary)

            if nookSettings.showAIAssistant {
                Button("Toggle AI Assistant", systemImage: "sparkle") {
                    browserManager.toggleAISidebar(for: windowState)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(Color.primary)
            }

            Spacer()
        }
        .frame(height: 28)
    }
}
