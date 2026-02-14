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
        HStack(alignment: .bottom, spacing: 10) {
            menuButton
            
            // Hide spaces list in incognito windows (only one ephemeral space)
            if !windowState.isIncognito {
                SpacesList()
                    .frame(maxWidth: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
            
            // Hide new space button in incognito windows
            if !windowState.isIncognito {
                newSpaceButton
            }
        }.fixedSize(horizontal: false, vertical: true)
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
        Menu{
            Button("New Space", systemImage: "square.grid.2x2") {
                onNewSpaceTap()
            }
            
            Button("New Folder", systemImage: "folder.badge.plus") {
                if let currentSpace = browserManager.tabManager.currentSpace {
                    browserManager.tabManager.createFolder(for: currentSpace.id)
                }
            }
            
            Divider()
            
            Button("New Profile", systemImage: "person.badge.plus") {
                // TODO: Show profile creation dialog
            }
        } label:{
            Label("Actions", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
    }
}
