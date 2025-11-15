//
//  SidebarBottomBar.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI

/// Bottom bar of the sidebar containing menu button, spaces list, and new space button
struct SidebarBottomBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Binding var isMenuButtonHovered: Bool
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void

    var body: some View {
        ZStack {
            // Left side - Menu button
            HStack {
                menuButton
                Spacer()
            }

            // Center - Space indicators
            SpacesList()
                .environmentObject(browserManager)
                .environment(windowState)

            // Right side - New space button
            HStack {
                Spacer()
                newSpaceButton
            }
        }
        .padding(.horizontal, 8)
    }

    private var menuButton: some View {
        ZStack {
            Button("Menu", systemImage: "archivebox") {
                onMenuTap()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .foregroundStyle(Color.primary)
            .onHover { isHovered in
                isMenuButtonHovered = isHovered
                onMenuHover(isHovered)
            }

            DownloadIndicator()
                .offset(x: 12, y: -12)
        }
    }

    private var newSpaceButton: some View {
        Button("New Space", systemImage: "plus") {
            onNewSpaceTap()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
    }
}
