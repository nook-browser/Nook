// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarBottomBar.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

/// Bottom bar of the sidebar containing menu button, spaces list, and new space button
struct SidebarBottomBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Binding var isMenuButtonHovered: Bool
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: NookDesign.Spacing.xxs) {
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
        }
        .frame(height: NookDesign.Size.bottomBar)
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }
    
    private var menuButton: some View {
        ZStack {
            Button("Menu", systemImage: "archivebox") {
                onMenuTap()
            }
            // A finished download bounces the button its icon flew into.
            .symbolEffect(.bounce, value: browserManager.downloadManager.completedCount)
            .nookGlassControls(in: Circle())
            .anchorPreference(key: DownloadsButtonAnchorKey.self, value: .bounds) { $0 }
            .onHoverTracking { isHovered in
                isMenuButtonHovered = isHovered
                onMenuHover(isHovered)
            }
            
            DownloadIndicator()
                .offset(x: NookDesign.Spacing.lg, y: -NookDesign.Spacing.lg)
        }
    }
    
    private var newSpaceButton: some View {
        Menu{
            Button("New Space", systemImage: "square.grid.2x2") {
                onNewSpaceTap()
            }
            
            Button("New Folder", systemImage: "folder.badge.plus") {
                if let spaceID = windowState.spaceID {
                    tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            }
            
            Divider()
            
            Button("New Profile", systemImage: "person.badge.plus") {
                // TODO: Show profile creation dialog
            }
        } label:{
            Label("Actions", systemImage: "plus")
        }
        .menuStyle(.button)
        .nookGlassControls(in: Circle())
    }
}
