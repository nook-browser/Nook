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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.nookSettings) var nookSettings

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
            .contextMenu {
                sidebarContextMenu
            }
            .onHover { state in
                isSidebarHovered = state
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

    private var mainSidebarContent: some View {
        let effectiveProfileId = windowState.currentProfileId ?? browserManager.currentProfile?.id
        let essentialsCount = effectiveProfileId.map { browserManager.tabManager.essentialTabs(for: $0).count } ?? 0
        let shouldAnimate = (windowRegistry.activeWindow?.id == windowState.id) && !browserManager.isTransitioningProfile

        return VStack(spacing: 8) {
            // Header (window controls, nav buttons, URL bar)
            SidebarHeader(isSidebarHovered: isSidebarHovered)
                .environmentObject(browserManager)
                .environment(windowState)

            // Pinned tabs grid
            PinnedGrid(
                width: windowState.sidebarContentWidth,
                profileId: effectiveProfileId
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .padding(.horizontal, 8)
            .modifier(FallbackDropBelowEssentialsModifier())

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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(
            shouldAnimate ? .easeInOut(duration: 0.18) : nil,
            value: essentialsCount
        )
    }

    // MARK: - Spaces Page View

    private var spacesPageView: some View {
        let spaces = browserManager.tabManager.spaces

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
            .onHover { isHovered in
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
            // add tab action here
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
                Label("Sidebar Position", systemImage: nookSettings.sidebarPosition.icon)
            }

            Divider()

            Button {
                showSpaceEditDialog(mode: .rename)
            } label: {
                Label("Edit Space", systemImage: "square.and.pencil")
            }
            if browserManager.tabManager.spaces.count > 1 {
                Divider()
                Button(role: .destructive) {
                    if let spaceId = browserManager.tabManager.currentSpace?.id {
                        browserManager.tabManager.removeSpace(spaceId)
                    }
                } label: {
                    Label("Delete Space", systemImage: "trash")
                }
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
            print("⚠️ Invalid space index: \(newIndex), spaces count: \(spaces.count)")
            return
        }

        let space = spaces[newIndex]
        print("🎯 Page changed to space: \(space.name) (index: \(newIndex))")

        // Trigger haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // Activate the space
        browserManager.setActiveSpace(space, in: windowState)
    }

    private func makeSpaceView(for space: Space, index: Int) -> some View {
        VStack(spacing: 0) {
            SpaceView(
                space: space,
                isActive: windowState.currentSpaceId == space.id,
                onActivateTab: { browserManager.selectTab($0, in: windowState) },
                onCloseTab: { browserManager.tabManager.removeTab($0.id) },
                onPinTab: { browserManager.tabManager.pinTab($0) },
                onMoveTabUp: { browserManager.tabManager.moveTabUp($0.id) },
                onMoveTabDown: { browserManager.tabManager.moveTabDown($0.id) },
                onMuteTab: { $0.toggleMute() }
            )
            .environmentObject(browserManager)
            .environment(windowState)
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
                onCreate: { name, icon in
                    let finalName = name.isEmpty ? "New Space" : name
                    let finalIcon = icon.isEmpty ? "✨" : icon
                    let newSpace = browserManager.tabManager.createSpace(
                        name: finalName,
                        icon: finalIcon
                    )

                    if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == newSpace.id }) {
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
                onSave: { newName, newIcon in
                    let spaceId = targetSpace.id

                    do {
                        if newIcon != targetSpace.icon {
                            try browserManager.tabManager.updateSpaceIcon(
                                spaceId: spaceId,
                                icon: newIcon
                            )
                        }

                        if newName != targetSpace.name {
                            try browserManager.tabManager.renameSpace(
                                spaceId: spaceId,
                                newName: newName
                            )
                        }

                        browserManager.dialogManager.closeDialog()
                    } catch {
                        print("⚠️ Failed to update space \(spaceId.uuidString):", error)
                    }
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func resolveCurrentSpace() -> Space? {
        if let current = browserManager.tabManager.currentSpace {
            return current
        }
        if let currentId = windowState.currentSpaceId {
            return browserManager.tabManager.spaces.first { $0.id == currentId }
        }
        return browserManager.tabManager.spaces.first
    }

    // MARK: - Computed Properties

    private var menuTransition: AnyTransition {
        .move(edge: nookSettings.sidebarPosition == .left ? .leading : .trailing)
            .combined(with: .opacity)
    }
}
