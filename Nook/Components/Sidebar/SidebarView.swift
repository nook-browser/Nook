import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Sparkle

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.tabDragManager) private var dragManager
    @State private var activeSpaceIndex: Int = 0
    @State private var currentScrollID: Int? = nil
    @State private var hasTriggeredHaptic = false
    @State private var spaceName = ""
    @State private var spaceIcon = ""
    @State private var sidebarDraggedItem: UUID? = nil
    @State private var activeTabRefreshTrigger: Bool = false

    // Downloads Menu Hover
    @State private var isMenuButtonHovered = false
    @State private var isDownloadsHovered = false
    @State private var showDownloadsMenu = false
    @State private var animateDownloadsMenu: Bool = false

    private var shouldShowDownloads: Bool {
        isMenuButtonHovered || isDownloadsHovered
    }
    // Force rendering even when the real sidebar is collapsed (used by hover overlay)
    var forceVisible: Bool = false
    // Override the width for overlay use; falls back to BrowserManager width
    var forcedWidth: CGFloat? = nil

    private var effectiveWidth: CGFloat {
        forcedWidth ?? windowState.sidebarWidth
    }

    private var availableContentWidth: CGFloat {
        effectiveWidth - 16 // Account for horizontal padding
    }

    private var targetScrollPosition: Int {
        if let currentSpaceId = windowState.currentSpaceId,
            let index = browserManager.tabManager.spaces.firstIndex(where: {
                $0.id == currentSpaceId
            })
        {
            return index
        }
        return 0
    }

    private var visibleSpaceIndices: [Int] {
        let totalSpaces = browserManager.tabManager.spaces.count

        guard totalSpaces > 0 else { return [] }

        // Ensure activeSpaceIndex is within bounds
        let safeActiveIndex = min(max(activeSpaceIndex, 0), totalSpaces - 1)

        // If the activeSpaceIndex is out of bounds, update it
        if activeSpaceIndex != safeActiveIndex {
            print(
                "⚠️ activeSpaceIndex out of bounds: \(activeSpaceIndex), correcting to: \(safeActiveIndex)"
            )
            DispatchQueue.main.async {
                self.activeSpaceIndex = safeActiveIndex
            }
        }

        var indices: [Int] = []

        if safeActiveIndex == 0 {
            // First space: show [0, 1]
            indices.append(0)
            if totalSpaces > 1 {
                indices.append(1)
            }
        } else if safeActiveIndex == totalSpaces - 1 {
            // Last space: show [last-1, last]
            indices.append(safeActiveIndex - 1)
            indices.append(safeActiveIndex)
        } else {
            // Middle space: show [current-1, current, current+1]
            indices.append(safeActiveIndex - 1)
            indices.append(safeActiveIndex)
            indices.append(safeActiveIndex + 1)
        }

        print(
            "🔍 visibleSpaceIndices - activeSpaceIndex: \(activeSpaceIndex), safeIndex: \(safeActiveIndex), totalSpaces: \(totalSpaces), result: \(indices)"
        )
        return indices
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

    var body: some View {
        if windowState.isSidebarVisible || forceVisible {
            sidebarContent
                .contextMenu {
                    Button {
                        // TODO: Implement space icon change ouside of SpaceTitle
                    } label: {
                        Label("Change Space Icon", systemImage: "pencil")
                    }

                    Button {
                        // TODO: Implement space renaming outside of SpaceTitle
                    } label: {
                        Label("Rename Space", systemImage: "face.smiling")
                    }
                    Button {
                        browserManager.showGradientEditor()
                    } label: {
                        Label("Edit Theme Color", systemImage: "paintpalette")
                    }
                    if browserManager.tabManager.spaces.count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            browserManager.tabManager.removeSpace(browserManager.tabManager.currentSpace!.id)
                        } label: {
                            Label("Delete Space", systemImage: "trash")
                        }
                    }
                }
        }
    }

    private var sidebarContent: some View {
        let effectiveProfileId =
            windowState.currentProfileId ?? browserManager.currentProfile?.id
        let essentialsCount =
            effectiveProfileId.map {
                browserManager.tabManager.essentialTabs(for: $0).count
            } ?? 0

        let shouldAnimate =
            (browserManager.activeWindowState?.id == windowState.id)
            && !browserManager.isTransitioningProfile

        let content = VStack(spacing: 8) {
            // Only show navigation buttons if top bar address view is disabled
            if !browserManager.settingsManager.topBarAddressView {
                HStack(spacing: 2) {
                    NavButtonsView(effectiveSidebarWidth: effectiveWidth)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
            }

            // Only show URL bar in sidebar if top bar address view is disabled
            if !browserManager.settingsManager.topBarAddressView {
                URLBarView()
                    .padding(.horizontal, 8)
            }
            // Container to support PinnedGrid slide transitions without clipping
            ZStack {
                PinnedGrid(
                    width: availableContentWidth,
                    profileId: effectiveProfileId
                )
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
            }
            .padding(.horizontal, 8)
            .modifier(FallbackDropBelowEssentialsModifier())

            ZStack {
                spacesScrollView
                    .zIndex(1)

                // Bottom spacer for window dragging - overlay that doesn't compete for space
                Color.clear
                    .contentShape(Rectangle())
                    .conditionalWindowDrag()
                    .frame(minHeight: 40)
                    .zIndex(0)
            }


            if showDownloadsMenu {
                SidebarMenuHoverDownloads(
                    isVisible: animateDownloadsMenu
                )
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

            // Update notification overlay
            SidebarUpdateNotification(downloadsMenuVisible: showDownloadsMenu)
                .environmentObject(browserManager)
                .environmentObject(windowState)
                .environment(browserManager.settingsManager)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            // MARK: - Bottom
            ZStack {
                // Left side icons - anchored to left
                HStack {
                    ZStack {
                        NavButton(iconName: "archivebox", disabled: false, action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                windowState.isSidebarMenuVisible = true
                                windowState.isSidebarAIChatVisible = false
                                let previousWidth = windowState.sidebarWidth
                                windowState.savedSidebarWidth = previousWidth
                                let newWidth: CGFloat = 400
                                windowState.sidebarWidth = newWidth
                                windowState.sidebarContentWidth = max(newWidth - 16, 0)
                            }
                        })
                        .onHover { isHovered in
                            isMenuButtonHovered = isHovered
                            if isHovered {
                                showDownloadsMenu = true
                                animateDownloadsMenu = true
                            } else {
                                hideMenuAfterDelay()
                            }
                        }

                        DownloadIndicator()
                            .offset(x: 12, y: -12)
                    }
                    
                    if browserManager.settingsManager.showAIAssistant {
                        NavButton(iconName: "sparkles", disabled: false, action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                windowState.isSidebarAIChatVisible = true
                                windowState.isSidebarMenuVisible = false
                                let previousWidth = windowState.sidebarWidth
                                windowState.savedSidebarWidth = previousWidth
                                let newWidth: CGFloat = 400
                                windowState.sidebarWidth = newWidth
                                windowState.sidebarContentWidth = max(newWidth - 16, 0)
                            }
                        })
                    }

                    Spacer()
                }

                // Center content - space indicators
                SpacesList()
                    .environmentObject(browserManager)
                    .environmentObject(windowState)

                // Right side icons - anchored to right
                HStack {
                    Spacer()

                    NavButton(iconName: "plus", disabled: false, action: {
                        showSpaceCreationDialog()
                    })
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(width: effectiveWidth)
        .animation(
            shouldAnimate ? .easeInOut(duration: 0.18) : nil,
            value: essentialsCount)
        
        let finalContent = ZStack {
                if windowState.isSidebarAIChatVisible {
                    SidebarAIChat()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .environmentObject(browserManager)
                        .environmentObject(windowState)
                        .environment(browserManager.settingsManager)
                } else if windowState.isSidebarMenuVisible {
                    SidebarMenu()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    content
                        .transition(.blur)
                }
            }
            .frame(width: effectiveWidth)

        return finalContent
    }

    private var spacesScrollView: some View {
        ZStack {
            spacesContent
        }
    }

    private var spacesContent: some View {
        Group {
            if browserManager.tabManager.spaces.isEmpty {
                emptyStateView
            } else {
                spacesPageView
            }
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
        .frame(width: effectiveWidth)
        .padding()
    }

    private var spacesPageView: some View {
        let spaces = browserManager.tabManager.spaces
        return PageView(selection: $activeSpaceIndex) {
            ForEach(spaces.indices, id: \.self) { index in
                if index >= 0 && index < spaces.count {
                    makeSpaceView(for: spaces[index], index: index)
                } else {
                    EmptyView()
                }
            }
        }
        .frame(width: effectiveWidth)
        .pageViewStyle(.scroll)
        .contentShape(Rectangle())
        .id(activeTabRefreshTrigger)
        .onAppear {
            // Initialize the selection
            if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                activeSpaceIndex = targetIndex
            }
        }
        .onChange(of: activeSpaceIndex) { _, newIndex in
            // Add explicit bounds checking to prevent index out of range crashes
            guard newIndex >= 0 && newIndex < browserManager.tabManager.spaces.count else {
                print("⚠️ Invalid space index in onChange: \(newIndex), spaces count: \(browserManager.tabManager.spaces.count)")
                return
            }
            let space = browserManager.tabManager.spaces[newIndex]
            print("🎯 Page changed to space: \(space.name) (index: \(newIndex))")

            // Trigger haptic feedback
            let impact = NSHapticFeedbackManager.defaultPerformer
            impact.perform(.alignment, performanceTime: .default)

            // Activate the space - BigUIPaging ensures newIndex is always valid
            browserManager.setActiveSpace(space, in: windowState)

            // Force hit testing refresh after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // This helps ensure proper hit testing after page transition
            }
        }
        .onChange(of: windowState.currentSpaceId) { _, _ in
            // Update selection when space changes externally
            if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                activeSpaceIndex = targetIndex
            }
            // Force PageView to recreate when SPACE changes (not tab changes)
            // This fixes hit testing issues after space switches while preserving scroll position
            activeTabRefreshTrigger.toggle()
        }
        .onChange(of: windowState.sidebarContentWidth) { _, _ in
            // Rebuild cached page views so width-sensitive content refreshes immediately
            activeTabRefreshTrigger.toggle()
        }
    }

    // this seems to be unused?
    private var spacesHStack: some View {
        LazyHStack(spacing: 0) {
            ForEach(visibleSpaceIndices, id: \.self) { spaceIndex in
                let space = browserManager.tabManager.spaces[spaceIndex]
                VStack(spacing: 0) {
                    SpaceView(
                        space: space,
                        isActive: windowState.currentSpaceId == space.id,
                        onActivateTab: {
                            browserManager.selectTab($0, in: windowState)
                        },
                        onCloseTab: {
                            browserManager.tabManager.removeTab($0.id)
                        },
                        onPinTab: { browserManager.tabManager.pinTab($0) },
                        onMoveTabUp: {
                            browserManager.tabManager.moveTabUp($0.id)
                        },
                        onMoveTabDown: {
                            browserManager.tabManager.moveTabDown($0.id)
                        },
                        onMuteTab: { $0.toggleMute() }
                    )
                    .id(space.id.uuidString + "-w\(Int(windowState.sidebarContentWidth))")
                    // Each page is exactly one sidebar-width wide for viewAligned snapping
                    .frame(width: effectiveWidth)
                }
                .id(spaceIndex)
            }
        }
        .scrollTargetLayout()
    }

    func scrollToSpace(_ space: Space, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(space.id, anchor: .center)
        }
    }

    private func showSpaceCreationDialog() {
        let dialog = SpaceCreationDialog(
            spaceName: $spaceName,
            spaceIcon: $spaceIcon,
            onSave: {
                // Create the space with the name from dialog
                let newSpace = browserManager.tabManager.createSpace(
                    name: spaceName.isEmpty ? "New Space" : spaceName,
                    icon: spaceIcon.isEmpty ? "✨" : spaceIcon
                )

                // Update the active space index to the newly created space
                if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == newSpace.id }) {
                    activeSpaceIndex = targetIndex
                }
                // Reset form
                spaceName = ""
                spaceIcon = ""
            },
            onCancel: {
                browserManager.dialogManager.closeDialog()

                // Reset form
                spaceName = ""
                spaceIcon = ""
            },
            onClose: {
                browserManager.dialogManager.closeDialog()
            }
        )

        browserManager.dialogManager.showDialog(dialog)
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
            .environmentObject(windowState)
            .environmentObject(browserManager.splitManager)
            .id(space.id.uuidString + "-w\(Int(windowState.sidebarContentWidth))")
            Spacer()
        }
        .frame(width: effectiveWidth, alignment: .leading)
        .tag(index)
    }
}

// MARK: - Private helpers
