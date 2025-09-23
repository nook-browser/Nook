import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BigUIPaging

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.tabDragManager) private var dragManager
    @State private var activeSpaceIndex: Int = 0
    @State private var hasTriggeredHaptic = false
    @State private var spaceName = ""
    @State private var spaceIcon = ""
    @State private var showHistory = false
    @State private var sidebarDraggedItem: UUID? = nil
    @State private var activeTabRefreshTrigger: Bool = false
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
    

    var body: some View {
        if windowState.isSidebarVisible || forceVisible {
            sidebarContent
        }
    }
    
    private var sidebarContent: some View {
        let effectiveProfileId = windowState.currentProfileId ?? browserManager.currentProfile?.id
        let essentialsCount = effectiveProfileId.map { browserManager.tabManager.essentialTabs(for: $0).count } ?? 0

        let shouldAnimate = (browserManager.activeWindowState?.id == windowState.id) && !browserManager.isTransitioningProfile

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
                    width: availableContentWidth,
                    profileId: effectiveProfileId
                )
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
            }
            .padding(.horizontal, 8)
            .modifier(FallbackDropBelowEssentialsModifier())

            if showHistory {
                historyView
                    .padding(.horizontal, 8)
            } else {
                spacesScrollView
                    .padding(.horizontal, 8)
            }

            // MARK: - Bottom
            ZStack {
                // Left side icons - anchored to left
                HStack {
                    NavButton(iconName: "square.and.arrow.down") {
                        print("Downloads button pressed")
                    }

                    NavButton(iconName: "clock") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showHistory.toggle()
                        }
                    }

                    Spacer()
                }

                // Center content - space indicators or history text
                if !showHistory {
                    SpacesList()
                        .environmentObject(browserManager)
                        .environmentObject(windowState)
                } else {
                    Text("History")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Right side icons - anchored to right
                HStack {
                    Spacer()

                    if !showHistory {
                        NavButton(iconName: "plus") {
                            showSpaceCreationDialog()
                        }
                    } else {
                        NavButton(iconName: "arrow.left") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showHistory = false
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 8)
        .frame(width: effectiveWidth)

        return content.animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: essentialsCount)
    }
    
    private var historyView: some View {
        HistoryView()
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
    }
    
    private var spacesScrollView: some View {
        ZStack {
            spacesContent
        }
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }
    
    private var spacesContent: some View {
        Group {
            if browserManager.tabManager.spaces.isEmpty {
                // Empty state when no spaces exist
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
            } else {
                // Use BigUIPaging PageView for space navigation
                PageView(selection: $activeSpaceIndex) {
                    ForEach(browserManager.tabManager.spaces.indices, id: \.self) { index in
                        let space = browserManager.tabManager.spaces[index]
                        VStack(spacing: 0) {
                            SpaceView(
                                space: space,
                                isActive: windowState.currentSpaceId == space.id,
                                width: availableContentWidth,
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
                        }
                        .frame(maxWidth: effectiveWidth)
                        .tag(index)
                    }
                }
                .frame(maxWidth: effectiveWidth)
                .pageViewStyle(.scroll)
                .contentShape(Rectangle())
                .id(activeTabRefreshTrigger)
                .onChange(of: activeSpaceIndex) { _, newIndex in
                    // BigUIPaging will handle the bounds checking automatically
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
                .onAppear {
                    // Initialize the selection
                    if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                        activeSpaceIndex = targetIndex
                    }
                }
                .onChange(of: windowState.currentSpaceId) { _, _ in
                    // Update selection when space changes externally
                    if let targetIndex = browserManager.tabManager.spaces.firstIndex(where: { $0.id == windowState.currentSpaceId }) {
                        activeSpaceIndex = targetIndex
                    }
                }
                .onChange(of: windowState.currentTabId) { _, _ in
                    // Force PageView to recreate when active tab changes
                    // This fixes hit testing issues after space/tab switches
                    activeTabRefreshTrigger.toggle()
                }
            }
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
}

// MARK: - Private helpers
