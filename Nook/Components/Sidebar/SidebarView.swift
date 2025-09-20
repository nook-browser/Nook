import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.tabDragManager) private var dragManager
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var currentScrollID: Int? = nil
    @State private var activeSpaceIndex: Int = 0
    @State private var hasTriggeredHaptic = false
    @State private var spaceName = ""
    @State private var spaceIcon = ""
    @State private var sidebarDraggedItem: UUID? = nil
    @State private var isSidebarHovered: Bool = false

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
            if !isMenuButtonHovered && !isDownloadsHovered {
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
            HStack(spacing: 2) {
                NavButtonsView()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        DispatchQueue.main.async {
                            zoomCurrentWindow()
                        }
                    }
            )
            .backgroundDraggable()

            URLBarView()
                .padding(.horizontal, 8)
            // Container to support PinnedGrid slide transitions without clipping
            ZStack {
                PinnedGrid(
                    width: max(0, effectiveWidth - 16),
                    profileId: effectiveProfileId
                )
                .environmentObject(windowState)
            }
            .padding(.horizontal, 8)
            .modifier(FallbackDropBelowEssentialsModifier())
            spacesScrollView
            if showDownloadsMenu {
                SidebarMenuHoverDownloads(
                    isVisible: animateDownloadsMenu
                ) { completed in
                    if !completed {
                        print(completed)
                    }
                }
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

            // MARK: - Bottom
            HStack {
                ZStack {
                    NavButton(iconName: "archivebox") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            browserManager.isSidebarMenuVisible = true
                        }
                    }
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

                Spacer()

                SpacesList()
                    .environmentObject(windowState)

                Spacer()

                NavButton(iconName: "plus") {
                    showSpaceCreationDialog()
                }

            }
            .frame(height: 32)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .frame(width: effectiveWidth)
        .animation(
            shouldAnimate ? .easeInOut(duration: 0.18) : nil,
            value: essentialsCount
        )

        let finalContent = ZStack {
            if !browserManager.isSidebarMenuVisible {
                content
                    .transition(.scale.combined(with: .opacity))
            } else {
                SidebarMenu()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: effectiveWidth)

        return finalContent
    }

    private var spacesScrollView: some View {
        ZStack {
            spacesContent
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        )
    }

    private var spacesContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            spacesHStack
        }
        // Match the full sidebar width to avoid early clipping when swiping
        .frame(width: effectiveWidth)
        .contentMargins(.horizontal, 0)
        .scrollTargetLayout()
        .coordinateSpace(name: "SidebarGlobal")
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentScrollID, anchor: .topLeading)
        // Keep the active space locked to the leading edge when resizing
        .onChange(of: windowState.sidebarWidth) { _, _ in
            // Force a re-snap by clearing then restoring the target id without animation.
            // Some SwiftUI versions ignore setting the same id; this guarantees an update.
            let target = activeSpaceIndex
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                currentScrollID = nil
            }
            DispatchQueue.main.async {
                var t2 = Transaction()
                t2.disablesAnimations = true
                withTransaction(t2) {
                    currentScrollID = target
                }
            }
        }
        .onAppear {
            // Initialize to current active space
            activeSpaceIndex = targetScrollPosition
            currentScrollID = targetScrollPosition
            print(
                "🔄 Initialized activeSpaceIndex: \(activeSpaceIndex), currentScrollID: \(targetScrollPosition)"
            )
        }
        .onChange(of: windowState.currentSpaceId) { _, _ in
            // Space was changed programmatically (e.g., clicking bottom icons)
            let newSpaceIndex = targetScrollPosition
            if newSpaceIndex != activeSpaceIndex {
                print(
                    "🎯 Programmatic space change - snapping to space \(newSpaceIndex)"
                )
                // Step 1: clear scroll target without animation
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { currentScrollID = nil }
                // Step 2: update visible window immediately so target exists
                activeSpaceIndex = newSpaceIndex
                // Step 3: set target on next runloop tick
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentScrollID = newSpaceIndex
                    }
                }
            }
        }
        .onChange(of: browserManager.tabManager.spaces.count) { _, newCount in
            // Spaces were added or deleted - ensure activeSpaceIndex is valid
            let newSpaceIndex = targetScrollPosition
            if newSpaceIndex != activeSpaceIndex {
                print(
                    "🔄 Spaces count changed to \(newCount) - updating activeSpaceIndex from \(activeSpaceIndex) to \(newSpaceIndex)"
                )
                activeSpaceIndex = newSpaceIndex
                currentScrollID = newSpaceIndex
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if newPhase == .interacting && oldPhase == .idle {
                // Drag just started - fire haptic after short delay
                if !hasTriggeredHaptic {
                    hasTriggeredHaptic = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        let impact = NSHapticFeedbackManager.defaultPerformer
                        impact.perform(.alignment, performanceTime: .default)
                        print("🎯 Haptic 0.1s after drag start")
                    }
                }
            } else if newPhase == .idle && oldPhase != .idle {
                // Drag just ended - activate the space and update visible window
                hasTriggeredHaptic = false  // Reset haptic flag
                if let newSpaceIndex = currentScrollID {
                    let space = browserManager.tabManager.spaces[newSpaceIndex]
                    print(
                        "🎯 Drag ended - Activating space: \(space.name) (index: \(newSpaceIndex))"
                    )
                    browserManager.setActiveSpace(space, in: windowState)
                    activeSpaceIndex = newSpaceIndex  // Update visible window ONLY on drag end
                }
            }
        }
    }

    private var spacesHStack: some View {
        LazyHStack(spacing: 0) {
            ForEach(visibleSpaceIndices, id: \.self) { spaceIndex in
                let space = browserManager.tabManager.spaces[spaceIndex]
                VStack(spacing: 0) {
                    SpaceView(
                        space: space,
                        isActive: windowState.currentSpaceId == space.id,
                        width: effectiveWidth,
                        isSidebarHovered: isSidebarHovered,
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
                    .id(space.id)
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
                browserManager.tabManager.createSpace(
                    name: spaceName.isEmpty ? "New Space" : spaceName,
                    icon: spaceIcon.isEmpty ? "✨" : spaceIcon
                )

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
}

// MARK: - Private helpers
