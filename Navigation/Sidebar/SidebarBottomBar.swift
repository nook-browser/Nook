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
    @State private var showCreateMenu = false
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let reserve = sideReserve
            ZStack {
                // The space dots sit on the bar's center line whatever the side clusters hold.
                if !windowState.isIncognito {
                    SpacesList()
                        .frame(width: max(geo.size.width - 2 * reserve, 0))
                        .environmentObject(browserManager)
                        .environment(windowState)
                }

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

                    Spacer(minLength: 0)

                    // Hide new space button in incognito windows
                    if !windowState.isIncognito {
                        newSpaceButton
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: NookDesign.Size.bottomBar)
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }

    /// Room kept clear on each side of the dots: the wider cluster plus a gap.
    private var sideReserve: CGFloat {
        let button = NookDesign.SidebarChrome.button, gap = NookDesign.SidebarChrome.gap
        let left = nookSettings.showAIAssistant ? 2 * button + gap : button
        return left + gap
    }

    private var menuButton: some View {
        ZStack {
            Button {
                onMenuTap()
            } label: {
                ZStack {
                    Image(systemName: isMenuButtonHovered ? "archivebox.fill" : "archivebox")
                        .shadow(color: Color.white.opacity(isMenuButtonHovered ? 0.5 : 0), radius: 6)
                    if isMenuButtonHovered {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(y: -8)
                            .shadow(color: .white.opacity(0.8), radius: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .accessibilityLabel("View Library")
            // A finished download bounces the button its icon flew into.
            .symbolEffect(.bounce, value: browserManager.downloadManager.completedCount)
            .nookSidebarIconButtons()
            .background(
                NookDesign.Radius.shape(NookDesign.Radius.md)
                    .fill(isMenuButtonHovered ? NookDesign.Surface.fillPressed : .clear)
            )
            .anchorPreference(key: DownloadsButtonAnchorKey.self, value: .bounds) { $0 }
            .onHoverTracking { isHovered in
                isMenuButtonHovered = isHovered
                if isHovered { browserManager.downloadManager.refreshSystemDownloads() }
                onMenuHover(isHovered)
            }
            // Arc's hint beside the button when no recent downloads peek is shown.
            .overlay(alignment: .leading) {
                if isMenuButtonHovered, browserManager.downloadManager.recentDownloads.isEmpty {
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
    
    /// Arc's create menu: `+` rotates to `×` and opens a popover above the button.
    private var newSpaceButton: some View {
        Button {
            showCreateMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .rotationEffect(.degrees(showCreateMenu ? 45 : 0))
                .animation(NookDesign.Motion.spring, value: showCreateMenu)
        }
        .accessibilityLabel(showCreateMenu ? "Close Menu" : "Actions")
        .nookSidebarIconButtons()
        .popover(isPresented: $showCreateMenu, arrowEdge: .top) {
            createMenuPopover
        }
    }

    private var createMenuPopover: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
            CreateMenuRow("New Space", systemImage: "plus.square.on.square") {
                showCreateMenu = false
                onNewSpaceTap()
            }

            CreateMenuRow("New Folder", systemImage: "folder.badge.plus") {
                showCreateMenu = false
                if let spaceID = windowState.spaceID {
                    tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            }

            Menu {
                ForEach(LiveFolderMenuItem.all, id: \.title) { entry in
                    Button(entry.title, systemImage: entry.symbol) {
                        showCreateMenu = false
                        if let spaceID = windowState.spaceID {
                            tabs.createLiveFolder(entry.source, in: spaceID)
                        }
                    }
                }
                Button("New Feed Folder…", systemImage: "dot.radiowaves.up.forward") {
                    showCreateMenu = false
                    if let spaceID = windowState.spaceID {
                        browserManager.presentFeedFolderPrompt(in: spaceID)
                    }
                }
            } label: {
                CreateMenuRowLabel("New Live Folder", systemImage: "folder.badge.gearshape", trailingChevron: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Divider()
                .padding(.vertical, NookDesign.Spacing.xs)
                .padding(.horizontal, NookDesign.Spacing.sm)

            CreateMenuRow("New Boost", systemImage: "wand.and.stars", disabled: !selectedPageIsWeb) {
                showCreateMenu = false
                browserManager.openBoostPanel(in: windowState)
            }

            Divider()
                .padding(.vertical, NookDesign.Spacing.xs)
                .padding(.horizontal, NookDesign.Spacing.sm)

            CreateMenuRow(
                "New Split",
                systemImage: "rectangle.split.2x1",
                disabled: windowState.selectedItemID == nil || windowState.split != nil
            ) {
                showCreateMenu = false
                if let itemID = tabs.open(url: TabsController.homeURL, in: windowState, placement: .background) {
                    browserManager.splitManager.enterSplit(with: itemID, in: windowState)
                }
            }

            CreateMenuRow("New Tab", systemImage: "plus.square", shortcut: "⌘T") {
                showCreateMenu = false
                commandPalette.open()
            }
        }
        .padding(NookDesign.Spacing.sm)
        .frame(width: 220)
    }

    private var selectedPageIsWeb: Bool {
        guard let url = tabs.selectedSession(in: windowState)?.url else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

/// One row inside the bottom-bar create popover.
private struct CreateMenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    init(_ title: String, systemImage: String, shortcut: String? = nil, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CreateMenuRowLabel(title, systemImage: systemImage, shortcut: shortcut)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

private struct CreateMenuRowLabel: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var trailingChevron: Bool = false
    @State private var isHovering = false

    init(_ title: String, systemImage: String, shortcut: String? = nil, trailingChevron: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.trailingChevron = trailingChevron
    }

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                .frame(width: NookDesign.Size.favicon)
            Text(title)
                .font(NookDesign.Font.label)
            Spacer(minLength: 0)
            if let shortcut {
                Text(shortcut)
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.tertiary)
            } else if trailingChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: NookDesign.Size.rowGlyph - 2, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(height: NookDesign.Tab.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.hover(hovering)) { isHovering = hovering }
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
