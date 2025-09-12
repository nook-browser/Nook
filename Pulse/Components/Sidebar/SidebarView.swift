import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var currentScrollID: Int? = nil
    @State private var activeSpaceIndex: Int = 0
    @State private var hasTriggeredHaptic = false
    @State private var spaceName = ""
    @State private var spaceIcon = ""
    @State private var showHistory = false
    @State private var sidebarDraggedItem: UUID? = nil
    
    private var targetScrollPosition: Int {
        if let currentSpace = browserManager.tabManager.currentSpace,
           let index = browserManager.tabManager.spaces.firstIndex(where: { $0.id == currentSpace.id }) {
            return index
        }
        return 0
    }
    
    private var visibleSpaceIndices: [Int] {
        let totalSpaces = browserManager.tabManager.spaces.count
        
        guard totalSpaces > 0 else { return [] }
        
        var indices: [Int] = []
        
        if activeSpaceIndex == 0 {
            // First space: show [0, 1]
            indices.append(0)
            if totalSpaces > 1 {
                indices.append(1)
            }
        } else if activeSpaceIndex == totalSpaces - 1 {
            // Last space: show [last-1, last]
            indices.append(activeSpaceIndex - 1)
            indices.append(activeSpaceIndex)
        } else {
            // Middle space: show [current-1, current, current+1]
            indices.append(activeSpaceIndex - 1)
            indices.append(activeSpaceIndex)
            indices.append(activeSpaceIndex + 1)
        }
        
        print("🔍 visibleSpaceIndices - activeSpaceIndex: \(activeSpaceIndex), result: \(indices)")
        return indices
    }
    

    var body: some View {
        if browserManager.isSidebarVisible {
            sidebarContent
        }
    }
    
    private var sidebarContent: some View {
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
                    // Container to support PinnedGrid slide transitions without clipping
                    ZStack {
                        PinnedGrid(width: browserManager.sidebarWidth)
                    }
                    .modifier(FallbackDropBelowEssentialsModifier())
                    if showHistory {
                        historyView
                    } else {
                        spacesScrollView
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
            .frame(width: browserManager.sidebarWidth)
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
        ScrollView(.horizontal, showsIndicators: false) {
            spacesHStack
        }
        .frame(width: browserManager.sidebarWidth)
        .contentMargins(.horizontal, 0)
        .scrollTargetLayout()
        .coordinateSpace(name: "SidebarGlobal")
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentScrollID, anchor: .topLeading)
        // Keep the active space locked to the leading edge when resizing
        .onChange(of: browserManager.sidebarWidth) { _, _ in
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
            print("🔄 Initialized activeSpaceIndex: \(activeSpaceIndex), currentScrollID: \(targetScrollPosition)")
        }
        .onChange(of: browserManager.tabManager.currentSpace?.id) { _, _ in
            // Space was changed programmatically (e.g., clicking bottom icons)
            let newSpaceIndex = targetScrollPosition
            if newSpaceIndex != activeSpaceIndex {
                print("🎯 Programmatic space change - snapping to space \(newSpaceIndex)")
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
                hasTriggeredHaptic = false // Reset haptic flag
                if let newSpaceIndex = currentScrollID {
                    let space = browserManager.tabManager.spaces[newSpaceIndex]
                    print("🎯 Drag ended - Activating space: \(space.name) (index: \(newSpaceIndex))")
                    browserManager.tabManager.setActiveSpace(space)
                    activeSpaceIndex = newSpaceIndex  // Update visible window ONLY on drag end
                }
            }
        }
    }
    
    private var spacesHStack: some View {
        LazyHStack(spacing: 0) {
            ForEach(visibleSpaceIndices, id: \.self) { spaceIndex in
                let space = browserManager.tabManager.spaces[spaceIndex]
                SpaceView(
                    space: space,
                    isActive: browserManager.tabManager.currentSpace?.id == space.id,
                    width: browserManager.sidebarWidth,
                    onActivateTab: { browserManager.tabManager.setActiveTab($0) },
                    onCloseTab: { browserManager.tabManager.removeTab($0.id) },
                    onPinTab: { browserManager.tabManager.pinTab($0) },
                    onMoveTabUp: { browserManager.tabManager.moveTabUp($0.id) },
                    onMoveTabDown: { browserManager.tabManager.moveTabDown($0.id) },
                    onMuteTab: { $0.toggleMute() }
                )
                .id(spaceIndex)
                .frame(width: browserManager.sidebarWidth)
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
