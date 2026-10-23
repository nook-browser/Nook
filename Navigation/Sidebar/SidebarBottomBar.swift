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
    @Environment(\.nookSettings) private var nookSettings
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Binding var isMenuButtonHovered: Bool
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: NookDesign.SidebarChrome.gap) {
            menuButton
            if nookSettings.showAIAssistant {
                Button("Toggle AI Assistant", systemImage: "sparkle") {
                    browserManager.toggleAISidebar(for: windowState)
                }
                .nookSidebarIconButtons()
                .help("Toggle AI Assistant")
            }
            if !windowState.isIncognito {
                SpacesList()
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .frame(maxWidth: .infinity)
                newSpaceButton
            } else {
                Spacer(minLength: 0)
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
            .nookSidebarIconButtons()
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
        Button("New Space", systemImage: "plus", action: onNewSpaceTap)
            .nookSidebarIconButtons()
            .disabled(windowState.isCreatingSpace)
            .help("Create a Space")
            .contextMenu {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    if let spaceID = windowState.spaceID {
                        tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                    }
                }
                ForEach(LiveFolderMenuItem.all, id: \.title) { entry in
                    Button(entry.title, systemImage: entry.symbol) {
                        if let spaceID = windowState.spaceID {
                            tabs.createLiveFolder(entry.source, in: spaceID)
                        }
                    }
                }
                Button("New Feed Folder…", systemImage: "dot.radiowaves.up.forward") {
                    if let spaceID = windowState.spaceID {
                        browserManager.presentFeedFolderPrompt(in: spaceID)
                    }
                }
            }
    }

}

/// The live folder sources the sidebar's create menus offer, besides feeds.
struct LiveFolderMenuItem {
    let title: String
    let symbol: String
    let source: LiveSource

    static let all = [
        LiveFolderMenuItem(title: "New Pull Requests Folder", symbol: "arrow.triangle.pull", source: .githubPulls),
        LiveFolderMenuItem(title: "New Issues Folder", symbol: "smallcircle.filled.circle", source: .githubIssues),
        LiveFolderMenuItem(title: "New Notifications Folder", symbol: "bell", source: .githubNotifications),
        LiveFolderMenuItem(title: "New Asana Tasks Folder", symbol: "checkmark.circle", source: .asanaTasks),
    ]
}
