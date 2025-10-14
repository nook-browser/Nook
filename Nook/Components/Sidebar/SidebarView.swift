import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Sparkle

struct SidebarView: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.tabDragManager) private var dragManager
    @Environment(\.nookSettings) private var settings
    @Environment(\.nookDialog) private var dialogManager
    @State private var activeSpaceIndex: Int = 0
    @State private var currentScrollID: Int? = nil
    @State private var hasTriggeredHaptic = false
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
                    Menu {
                        ForEach(SidebarPosition.allCases) { position in
                            
                            Toggle(isOn: Binding(get: {
                                return settings.sidebarPosition == position
                            }, set: { Value in
                                settings.sidebarPosition = position
                            })) {
                                Label(position.displayName, systemImage: position.icon)
                            }
                        }
                    } label: {
                        Label("Sidebar Position", systemImage: settings.sidebarPosition.icon)
                    }
                    
                    Divider()
                    
                    Button {
                        showSpaceEditDialog(mode: .rename)
                    } label: {
                        Label("Rename Space", systemImage: "square.and.pencil")
                    }
                    
                    Button {
                        showSpaceEditDialog(mode: .icon)
                    } label: {
                        Label("Change Space Icon", systemImage: "pencil")
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
        browserManager.isActive(windowState)
        && !browserManager.isTransitioningProfile
        
        let content = VStack(spacing: 8) {
            // Only show navigation buttons if top bar address view is disabled
            if !settings.topBarAddressView {
                HStack(spacing: 2) {
                    NavButtonsView(effectiveSidebarWidth: effectiveWidth)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
            }
            
            // Only show URL bar in sidebar if top bar address view is disabled
            if !settings.topBarAddressView {
                URLBarView()
                    .padding(.horizontal, 8)
            }
            // Container to support PinnedGrid slide transitions without clipping
            ZStack {
                PinnedGrid(
                    width: availableContentWidth,
                    profileId: effectiveProfileId
                )
                .environment(browserManager)
                .environment(windowState)
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
                .environment(browserManager)
                .environment(windowState)
                .nookSettings(settings)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            
            // MARK: - Bottom
            ZStack {
                // Left side icons - anchored to left
                HStack {
                    ZStack {
                        Button("Menu", systemImage: "archivebox") {
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
                        .labelStyle(.iconOnly)
                        .buttonStyle(NavButtonStyle())
                        .foregroundStyle(Color.primary)
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
                }
                
                // Center content - space indicators
                SpacesList()
                    .environment(browserManager)
                    .environment(windowState)
                
                // Right side icons - anchored to right
                HStack {
                    Spacer()
                    
                    Button("New Space", systemImage: "plus") {
                        showSpaceCreationDialog()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(NavButtonStyle())
                    .foregroundStyle(Color.primary)
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
            if windowState.isSidebarMenuVisible {
                SidebarMenu()
                    .transition(.move(edge: settings.sidebarPosition == .left ? .leading : .trailing).combined(with: .opacity))
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
        dialogManager.showDialog(
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
                    
                    dialogManager.closeDialog()
                },
                onCancel: {
                    dialogManager.closeDialog()
                }
            )
        )
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
            .environment(browserManager)
            .environment(windowState)
            .environment(browserManager.splitManager)
            .id(space.id.uuidString + "-w\(Int(windowState.sidebarContentWidth))")
            Spacer()
        }
        .frame(width: effectiveWidth, alignment: .leading)
        .tag(index)
    }
    
    private func showSpaceEditDialog(mode: SpaceEditDialog.Mode) {
        guard let targetSpace = resolveCurrentSpace() else { return }
        
        dialogManager.showDialog(
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
                        
                        dialogManager.closeDialog()
                    } catch {
                        print("⚠️ Failed to update space \(spaceId.uuidString):", error)
                    }
                },
                onCancel: {
                    dialogManager.closeDialog()
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
    
    private func updateSidebarPosition(_ position: SidebarPosition) {
        guard settings.sidebarPosition != position else { return }
        settings.sidebarPosition = position
    }
}

// MARK: - Private helpers
