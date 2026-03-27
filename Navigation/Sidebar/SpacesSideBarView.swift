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

struct SpacesSideBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.nookSettings) var nookSettings
    @Environment(CommandPalette.self) var commandPalette
    @Environment(TabOrganizerManager.self) var tabOrganizerManager

    // Space navigation
    @State private var activeSpaceIndex: Int = 0
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
        return VStack(spacing: 8) {
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
                    .frame(minHeight: 40)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            // Media controls
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
        .padding(.top, nookSettings.sidebarPosition == .left ? 30 : 8)
        .padding(.bottom, 8)
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
        let spaces = windowState.isIncognito
            ? windowState.ephemeralSpaces
            : tabManager.spaces

        return Group {
            if spaces.isEmpty {
                emptyStateView
            } else {
                spacesContent(spaces: spaces)
            }
        }
    }

    private func spacesContent(spaces: [Space]) -> some View {
        PageView(selection: $activeSpaceIndex) {
            ForEach(spaces.indices, id: \.self) { index in
                if index >= 0 && index < spaces.count {
                    makeSpaceView(for: spaces[index], index: index)
                } else {
                    EmptyView()
                }
            }
        }
        .pageViewStyle(.scroll)
        .contentShape(Rectangle())
        .id(activeTabRefreshTrigger)
        .onAppear {
            if let targetIndex = spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                activeSpaceIndex = targetIndex
            }
            browserManager.setActiveSpace(spaces[0], in: windowState)
        }
        .onChange(of: activeSpaceIndex) { _, newIndex in
            handleSpaceIndexChange(newIndex, spaces: spaces)
        }
        .onChange(of: windowState.currentSpaceId) { _, _ in
            if let targetIndex = spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                activeSpaceIndex = targetIndex
            }
            activeTabRefreshTrigger.toggle()
        }
        .onChange(of: windowState.sidebarContentWidth) { _, _ in
            activeTabRefreshTrigger.toggle()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
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
                if let currentSpace = tabManager.currentSpace {
                    tabManager.createFolder(for: currentSpace.id)
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
        withAnimation(.easeInOut(duration: 0.2)) {
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

    private func handleSpaceIndexChange(_ newIndex: Int, spaces: [Space]) {
        guard newIndex >= 0 && newIndex < spaces.count else {
            return
        }

        let space = spaces[newIndex]

        // Trigger haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // Activate the space
        browserManager.setActiveSpace(space, in: windowState)
    }

    @ViewBuilder
    private func makeSpaceView(for space: Space, index: Int) -> some View {
        VStack(spacing: 0) {
            if !windowState.isIncognito {
                PinnedGrid(
                    width: windowState.sidebarContentWidth,
                    profileId: space.profileId ?? browserManager.currentProfile?.id
                )
                .environmentObject(browserManager)
                .environmentObject(tabManager)
                .environment(windowState)
                .environment(windowRegistry)
                .environment(nookSettings)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .modifier(FallbackDropBelowEssentialsModifier())
            }

            SpaceView(
                space: space,
                isActive: windowState.currentSpaceId == space.id,
                isSidebarHovered: $isSidebarHovered,
                onActivateTab: { browserManager.selectTab($0, in: windowState) },
                onCloseTab: { tabManager.removeTab($0.id) },
                onPinTab: { tabManager.pinTab($0) },
                onMoveTabUp: { tabManager.moveTabUp($0.id) },
                onMoveTabDown: { tabManager.moveTabDown($0.id) },
                onMuteTab: { $0.toggleMute() }
            )
            .environmentObject(browserManager)
            .environmentObject(tabManager)
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
        .tag(index)
    }

    // MARK: - Dialogs

    private func showSpaceCreationDialog() {
        browserManager.dialogManager.showDialog(
            SpaceCreationDialog(
                onCreate: { name, icon, profileId in
                    let finalName = name.isEmpty ? "New Space" : name
                    let finalIcon = icon.isEmpty ? "✨" : icon
                    let newSpace = tabManager.createSpace(
                        name: finalName,
                        icon: finalIcon
                    )

                    // Assign profile if one was selected
                    if let profileId = profileId {
                        tabManager.assign(spaceId: newSpace.id, toProfile: profileId)
                    }

                    if let targetIndex = tabManager.spaces.firstIndex(where: { $0.id == newSpace.id }) {
                        activeSpaceIndex = targetIndex
                    }

                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func showSpaceEditDialog(mode: SpaceEditDialog.Mode) {
        guard let targetSpace = resolveCurrentSpace() else { return }

        browserManager.dialogManager.showDialog(
            SpaceEditDialog(
                space: targetSpace,
                mode: mode,
                onSave: { newName, newIcon, newProfileId in
                    let spaceId = targetSpace.id

                    do {
                        if newIcon != targetSpace.icon {
                            try tabManager.updateSpaceIcon(
                                spaceId: spaceId,
                                icon: newIcon
                            )
                        }

                        if newName != targetSpace.name {
                            try tabManager.renameSpace(
                                spaceId: spaceId,
                                newName: newName
                            )
                        }

                        // Update profile if changed
                        if newProfileId != targetSpace.profileId, let profileId = newProfileId {
                            tabManager.assign(spaceId: spaceId, toProfile: profileId)
                        }

                        browserManager.dialogManager.closeDialog()
                    } catch {
                    }
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func resolveCurrentSpace() -> Space? {
        // For incognito windows, use ephemeral spaces
        if windowState.isIncognito {
            if let currentId = windowState.currentSpaceId {
                return windowState.ephemeralSpaces.first { $0.id == currentId }
            }
            return windowState.ephemeralSpaces.first
        }
        
        if let current = tabManager.currentSpace {
            return current
        }
        if let currentId = windowState.currentSpaceId {
            return tabManager.spaces.first { $0.id == currentId }
        }
        return tabManager.spaces.first
    }

    // MARK: - Computed Properties

    private var menuTransition: AnyTransition {
        .move(edge: nookSettings.sidebarPosition == .left ? .leading : .trailing)
            .combined(with: .opacity)
    }
}
