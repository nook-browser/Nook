// Licensed under GPL-3.0. See LICENSE.
//
//  SpacesSideBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Refactored by Aether on 15/11/2025.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Sparkle
import NookDesign
import NookSettings
import NookTabsCore
import NookWeb
import NookUI

struct SpacesSideBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.nookSettings) var nookSettings
    @Environment(CommandPalette.self) var commandPalette
    @Environment(TabOrganizerManager.self) var tabOrganizerManager

    // Space navigation. Keyed by space id: an index outlives the space it pointed at.
    @State private var activeSpaceID: UUID?
    @State private var activeTabRefreshTrigger: Bool = false

    // Hover states
    @State private var isSidebarHovered: Bool = false
    @State private var isMenuButtonHovered = false
    @State private var isDownloadsHovered = false
    @State private var showDownloadsMenu = false
    @State private var animateDownloadsMenu: Bool = false

    var body: some View {
        sidebarContent
            .contentShape(Rectangle())
            .onHoverTracking { state in
                isSidebarHovered = state
            }
            .contextMenu {
                sidebarContextMenu
            }
    }

    // MARK: - Main Content

    private var sidebarContent: some View {
        ZStack {
            if windowState.isSidebarMenuVisible {
                SidebarMenu()
                    .transition(menuTransition)
            } else {
                mainSidebarContent
                    .transition(.opacity)
            }
        }
    }

    @ObservedObject private var dragSession = NookDragSessionManager.shared

    private var mainSidebarContent: some View {
        return VStack(spacing: NookDesign.Spacing.sectionGap) {
            // Space title: shares the traffic-light row on the left, its own row on the right.
            if nookSettings.sidebarPosition != .left {
                spaceSwitcherTitle
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NookDesign.Spacing.sidebarInset)
            }

            // Header (window controls, nav buttons, URL bar)
            SidebarHeader(isSidebarHovered: isSidebarHovered)
                .environmentObject(browserManager)
                .environment(windowState)

            // Spaces page view with draggable spacer
            ZStack {
                spacesPageView
                    .zIndex(1)

                // Bottom spacer for window dragging
                Color.clear
                    .contentShape(Rectangle())
                    .conditionalWindowDrag()
                    .frame(minHeight: NookDesign.Size.bottomBar)
                    .zIndex(0)
            }

            // Downloads menu hover overlay
            if showDownloadsMenu {
                downloadsMenuOverlay
            }

            // Update notification
            SidebarUpdateNotification(downloadsMenuVisible: showDownloadsMenu)
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(nookSettings)
                .padding(.horizontal, NookDesign.Spacing.sidebarInset)
                .padding(.bottom, NookDesign.Spacing.sidebarInset)

            // Video left playing in another tab, directly above the media controls
            SidebarPiPView()
                .environmentObject(browserManager)
                .environment(windowState)

            // Media controls. Hides itself while the video is showing above it.
            MediaControlsView()
                .environmentObject(browserManager)
                .environment(windowState)

            // Bottom bar (menu, spaces indicators, new space)
            SidebarBottomBar(
                isMenuButtonHovered: $isMenuButtonHovered,
                onMenuTap: handleMenuTap,
                onNewSpaceTap: showSpaceCreationDialog,
                onMenuHover: handleMenuHover
            )
            .environmentObject(browserManager)
            .environment(windowState)
        }
        // Extra top padding when sidebar is on the left to avoid overlapping native traffic light buttons
        .padding(.top, nookSettings.sidebarPosition == .left ? NookDesign.Spacing.sidebarTop : NookDesign.Spacing.sidebarInset)
        .overlay(alignment: .topLeading) {
            if nookSettings.sidebarPosition == .left {
                spaceSwitcherTitle
                    .frame(height: NookDesign.Spacing.sidebarTop)
                    .padding(.leading, NookDesign.Spacing.trafficLights)
            }
        }
        .padding(.bottom, NookDesign.Spacing.sidebarInset)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updateSidebarScreenFrame(geo)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, _ in
                        updateSidebarScreenFrame(geo)
                    }
            }
        )
    }

    private func updateSidebarScreenFrame(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        guard let window = windowState.window ?? NSApp.windows.first(where: { $0.isVisible }),
              let contentView = window.contentView else { return }
        let appKitY = contentView.bounds.height - frame.maxY
        let bottomLeft = NSPoint(x: frame.origin.x, y: appKitY)
        let screenBottomLeft = window.convertPoint(toScreen: bottomLeft)
        dragSession.sidebarScreenFrame = CGRect(
            x: screenBottomLeft.x,
            y: screenBottomLeft.y,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - Spaces Page View

    private var spacesPageView: some View {
        let spaces = tabs.switchableSpaces(for: windowState)

        return Group {
            if spaces.isEmpty {
                emptyStateView
            } else {
                spacesContent(spaces: spaces)
            }
        }
    }

    private func spacesContent(spaces: [SpaceRecord]) -> some View {
        // A deleted (or private-window) space falls back to the first one still here.
        let selection = Binding<UUID> {
            spaces.first { $0.id == activeSpaceID }?.id ?? spaces[0].id
        } set: { activeSpaceID = $0 }

        return PageView(selection: selection) {
            ForEach(spaces) { space in
                makeSpaceView(for: space)
            }
        }
        .pageViewStyle(.scroll)
        .contentShape(Rectangle())
        // Pages are cached hosting views; a different set of spaces needs new pages.
        .id("\(activeTabRefreshTrigger)|\(spaces.map(\.id.uuidString).joined(separator: ","))")
        .onAppear {
            activeSpaceID = windowState.spaceID
            if !spaces.contains(where: { $0.id == windowState.spaceID }) {
                tabs.setSpace(spaces[0].id, in: windowState)
            }
        }
        .onChange(of: activeSpaceID) { _, newID in
            handleSpaceSelectionChange(newID, spaces: spaces)
        }
        .onChange(of: windowState.spaceID) { _, newID in
            activeSpaceID = newID
            activeTabRefreshTrigger.toggle()
        }
        .onChange(of: windowState.sidebarContentWidth) { _, _ in
            activeTabRefreshTrigger.toggle()
        }
    }


    private var emptyStateView: some View {
        VStack(spacing: NookDesign.Spacing.xl) {
            Image(systemName: "square.grid.2x2")
                .font(NookDesign.Font.hero)
                .foregroundColor(.secondary)
            VStack(spacing: NookDesign.Spacing.md) {
                Text("No Spaces")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Create a space to start browsing")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Button(action: showSpaceCreationDialog) {
                Label("Create Space", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Downloads Menu

    private var downloadsMenuOverlay: some View {
        SidebarMenuHoverDownloads(isVisible: animateDownloadsMenu)
            .onHoverTracking { isHovered in
                isDownloadsHovered = isHovered
                if isHovered {
                    showDownloadsMenu = true
                    animateDownloadsMenu = true
                } else {
                    hideMenuAfterDelay()
                }
            }
    }

    // MARK: - Context Menu

    private var sidebarContextMenu: some View {
        Group {
            Button {
                commandPalette.open()
            } label: {
                Label("New Tab", systemImage: "plus")
            }

            Button {
                if let spaceID = windowState.spaceID {
                    tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Menu {
                ForEach(SidebarPosition.allCases) { position in
                    Toggle(isOn: Binding(
                        get: { nookSettings.sidebarPosition == position },
                        set: { _ in nookSettings.sidebarPosition = position }
                    )) {
                        Label(position.displayName, systemImage: position.icon)
                    }
                }
            } label: {
                Label("Position", systemImage: nookSettings.sidebarPosition.icon)
            }
        }
    }

    // MARK: - Helper Functions

    private func handleMenuTap() {
        withAnimation(NookDesign.Motion.standard) {
            windowState.isSidebarMenuVisible = true
            windowState.isSidebarAIChatVisible = false
            let previousWidth = windowState.sidebarWidth
            windowState.savedSidebarWidth = previousWidth
            let newWidth: CGFloat = 400
            windowState.sidebarWidth = newWidth
            windowState.sidebarContentWidth = max(newWidth - 16, 0)
        }
    }

    private func handleMenuHover(_ isHovered: Bool) {
        if isHovered {
            showDownloadsMenu = true
            animateDownloadsMenu = true
        } else {
            hideMenuAfterDelay()
        }
    }

    private func hideMenuAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !isMenuButtonHovered, !isDownloadsHovered {
                animateDownloadsMenu = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showDownloadsMenu = false
                }
            }
        }
    }

    private func handleSpaceSelectionChange(_ newID: UUID?, spaces: [SpaceRecord]) {
        guard let newID, newID != windowState.spaceID, spaces.contains(where: { $0.id == newID }) else { return }
        // Haptic fires during swipe at 15% offset in PlatformPageView
        tabs.setSpace(newID, in: windowState)
    }

    @ViewBuilder
    private func makeSpaceView(for space: SpaceRecord) -> some View {
        VStack(spacing: 0) {
            if !windowState.isIncognito {
                PinnedGrid(
                    width: windowState.sidebarContentWidth,
                    spaceID: space.id
                )
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(windowRegistry)
                .environment(nookSettings)
                .padding(.horizontal, NookDesign.Spacing.sidebarInset)
                .padding(.bottom, NookDesign.Spacing.sectionGap)
            }

            SpaceView(
                spaceID: space.id,
                isActive: windowState.spaceID == space.id,
                isSidebarHovered: $isSidebarHovered
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .environment(windowRegistry)
            .environment(commandPalette)
            .environment(tabOrganizerManager)
            .environment(nookSettings)
            .environmentObject(browserManager.gradientColorManager)
            .environmentObject(browserManager.splitManager)
            .id(space.id.uuidString + "-w\(Int(windowState.sidebarContentWidth))")
            Spacer()
        }
    }

    private var spaceSwitcherTitle: some View {
        SpaceSwitcherTitle(onNewSpace: showSpaceCreationDialog)
            .environmentObject(browserManager)
            .environment(windowState)
    }

    // MARK: - Dialogs

    private func showSpaceCreationDialog() {
        browserManager.dialogManager.showDialog(
            SpaceCreationDialog(
                onCreate: { name, accentHex in
                    if let spaceID = tabs.createSpace(
                        name: name.isEmpty ? "New Space" : name,
                        icon: "square.grid.2x2",
                        accentHex: accentHex,
                        after: tabs.orderedSpaces.last?.id
                    ) {
                        tabs.setSpace(spaceID, in: windowState)
                    }
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }


    // MARK: - Computed Properties

    private var menuTransition: AnyTransition {
        .move(edge: nookSettings.sidebarPosition == .left ? .leading : .trailing)
            .combined(with: .opacity)
    }
}
