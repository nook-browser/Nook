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
    @Environment(CommandPalette.self) private var commandPalette
    @Binding var isMenuButtonHovered: Bool
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: NookDesign.SidebarChrome.gap) {
            // Above the space dots, so its hint draws over them.
            menuButton
                .zIndex(1)

            if nookSettings.showAIAssistant {
                Button("Toggle AI Assistant", systemImage: "sparkle") {
                    browserManager.toggleAISidebar(for: windowState)
                }
                .nookSidebarIconButtons()
                .help("Toggle AI Assistant")
            }

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
            // Arc's hint beside the button: where it leads.
            .overlay(alignment: .leading) {
                if isMenuButtonHovered {
                    Text("View Library")
                        .font(NookDesign.Font.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, NookDesign.Spacing.md)
                        .frame(height: NookDesign.Size.iconButton)
                        .background(Color.black.opacity(0.85), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                        .fixedSize()
                        .offset(x: NookDesign.SidebarChrome.button + NookDesign.Spacing.xs)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .offset(x: -4)))
                }
            }
            .animation(NookDesign.Motion.quick, value: isMenuButtonHovered)
            .zIndex(1)

            DownloadIndicator()
                .offset(x: NookDesign.Spacing.lg, y: -NookDesign.Spacing.lg)
        }
    }
    
    /// Arc's create menu: space and folder, then page tools, then panes and tabs.
    private var newSpaceButton: some View {
        Menu {
            Button("New Space", systemImage: "plus.square.on.square") {
                onNewSpaceTap()
            }

            Button("New Folder", systemImage: "folder.badge.plus") {
                if let spaceID = windowState.spaceID {
                    tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            }

            Menu {
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
            } label: {
                Label("New Live Folder", systemImage: "folder.badge.gearshape")
            }

            Divider()

            Button("New Boost", systemImage: "wand.and.stars") {
                browserManager.openBoostPanel(in: windowState)
            }
            .disabled(!selectedPageIsWeb)

            Divider()

            Button("New Split", systemImage: "rectangle.split.2x1") {
                if let itemID = tabs.open(url: TabsController.homeURL, in: windowState, placement: .background) {
                    browserManager.splitManager.enterSplit(with: itemID, in: windowState)
                }
            }
            .disabled(windowState.selectedItemID == nil || windowState.split != nil)

            Button("New Tab", systemImage: "plus.square") {
                commandPalette.open()
            }
        } label: {
            Label("Actions", systemImage: "plus")
        }
        .menuStyle(.button)
        .nookSidebarIconButtons()
    }

    private var selectedPageIsWeb: Bool {
        guard let url = tabs.selectedSession(in: windowState)?.url else { return false }
        return url.scheme == "http" || url.scheme == "https"
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
