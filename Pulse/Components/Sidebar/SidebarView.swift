import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager
    @State private var selectedSpaceID: UUID?
    @State private var isProgrammaticScroll = false
    @State private var spaceName = ""
    @State private var spaceIcon = ""
    @State private var showHistory = false

    var body: some View {
        if browserManager.isSidebarVisible {
            ZStack {
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        NavButtonsView()
                    }
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
                    PinnedGrid()
                    if showHistory {
                        // History View - only loaded when needed
                        HistoryView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        // Spaces View - default view
                        ZStack {
                            // Horizontal pages
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(
                                        browserManager.tabManager.spaces,
                                        id: \.id
                                    ) { space in
                                        SpaceView(
                                            space: space,
                                            isActive: browserManager.tabManager
                                                .currentSpace?.id == space.id,
                                            width: browserManager.sidebarWidth,
                                            onActivateTab: {
                                                browserManager.tabManager
                                                    .setActiveTab($0)
                                            },
                                            onCloseTab: {
                                                browserManager.tabManager.removeTab($0.id)
                                            },
                                            onPinTab: {
                                                browserManager.tabManager.pinTab($0)
                                            },
                                            onMoveTabUp: {
                                                browserManager.tabManager.moveTabUp($0.id)
                                            },
                                            onMoveTabDown: {
                                                browserManager.tabManager.moveTabDown($0.id)
                                            },
                                            onMuteTab: { tab in
                                                tab.toggleMute()
                                            }
                                        )
                                        .id(space.id)
                                        .frame(width: browserManager.sidebarWidth)
                                        .scrollTargetLayout()
                                    }
                                }
                            }
                            .frame(width: browserManager.sidebarWidth)
                            .contentMargins(.horizontal, 0)
                            .scrollTargetBehavior(.viewAligned)
                            .scrollIndicators(.hidden)
                            .scrollPosition(
                                id: Binding(
                                    get: { selectedSpaceID },
                                    set: { newID in
                                        guard !isProgrammaticScroll else {
                                            // Accept programmatic updates silently
                                            selectedSpaceID = newID
                                            isProgrammaticScroll = false
                                            return
                                        }
                                        // If user drags via some other means, just mirror the id
                                        selectedSpaceID = newID
                                    }
                                ),
                                anchor: .center
                            )

                            // Trackpad two-finger swipe detector overlay
                            TwoFingerSwipeDetector(
                                threshold: 80,
                                onSwipe: { dir in
                                    stepSpace(dir)
                                },
                                onDelta: { dx in
                                    print("🧭 TwoFinger deltaX=\(String(format: "%.2f", dx))")
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .onChange(
                            of: browserManager.tabManager.currentSpace?.id
                        ) { _, newID in
                            // Keep scroll position in sync with model changes
                            guard let newID else { return }
                            if selectedSpaceID != newID {
                                isProgrammaticScroll = true
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedSpaceID = newID
                                }
                            }
                        }
                        .onAppear {
                            if selectedSpaceID == nil {
                                selectedSpaceID = browserManager.tabManager.currentSpace?.id
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                    //MARK: - Bottom
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
                        
                        if !showHistory {
                            SpacesList()
                        } else {
                            Text("History")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
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
                .padding(.top, 8)
                .frame(width: browserManager.sidebarWidth)
            }
            .frame(width: browserManager.sidebarWidth)
        }
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
                browserManager.dialogManager.closeDialog()
                
                // Reset form
                spaceName = ""
                spaceIcon = ""
            },
            onCancel: {
                browserManager.dialogManager.closeDialog()
                
                // Reset form
                spaceName = ""
                spaceIcon = ""
            }
        )
        
        browserManager.dialogManager.showDialog(dialog)
    }
}

// MARK: - Private helpers
extension SidebarView {
    fileprivate func stepSpace(_ direction: TwoFingerSwipeDetector.Direction) {
        let spaces = browserManager.tabManager.spaces
        guard !spaces.isEmpty else { return }

        let currentID = browserManager.tabManager.currentSpace?.id ?? selectedSpaceID ?? spaces.first!.id
        guard let currentIndex = spaces.firstIndex(where: { $0.id == currentID }) else { return }

        let nextIndex: Int
        switch direction {
        case .left:
            // Swipe left → visually move right
            nextIndex = min(currentIndex + 1, spaces.count - 1)
        case .right:
            // Swipe right → visually move left
            nextIndex = max(currentIndex - 1, 0)
        }

        guard nextIndex != currentIndex else { return }
        let nextSpace = spaces[nextIndex]

        // Haptic + logging
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(.alignment, performanceTime: .now)
        print("🔁 Switching space: #\(currentIndex) \(spaces[currentIndex].name) → #\(nextIndex) \(nextSpace.name) [gesture: \(direction == .left ? "left" : "right")]")

        // Update model and scroll alignment
        browserManager.tabManager.setActiveSpace(nextSpace)
        isProgrammaticScroll = true
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedSpaceID = nextSpace.id
        }
    }
}
