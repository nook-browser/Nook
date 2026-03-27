//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import SwiftUI
import UniversalGlass

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(AIService.self) private var aiService
    @Environment(\.nookSettings) var nookSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            WindowBackground()
                .contextMenu {
                    Button("Customize Space Gradient...") {
                        browserManager.showGradientEditor()
                    }
                    .disabled(browserManager.tabManager.currentSpace == nil)
                }

            SidebarWebViewStack()

            CommandPaletteView()
            DialogView()

            // Peek overlay for external link previews
            PeekOverlayView()

            // Find bar - always rendered (24/7), visibility controlled via opacity
            FindBarView(findManager: browserManager.findManager)
                .zIndex(10000)

        }
        // System notification toasts - top trailing corner
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                // Profile switch toast
                if windowState.isShowingProfileSwitchToast,
                   let toast = windowState.profileSwitchToast
                {
                    ProfileSwitchToastView(toast: toast)
                        .environment(windowState)
                        .environmentObject(browserManager)
                }

                // Tab closure toast
                if browserManager.showTabClosureToast && browserManager.tabClosureToastCount > 0 {
                    TabClosureToast()
                        .environmentObject(browserManager)
                }

                // Copy URL toast
                if windowState.isShowingCopyURLToast {
                    CopyURLToast()
                        .environment(windowState)
                }
                
                // Shortcut conflict toast
                if windowState.isShowingShortcutConflictToast,
                   let conflictInfo = windowState.shortcutConflictInfo
                {
                    ShortcutConflictToast(conflictInfo: conflictInfo)
                        .environment(windowState)
                }
            }
            .padding(10)
            // Animate toast insertions/removals
            .animation(.smooth(duration: 0.25), value: windowState.isShowingProfileSwitchToast)
            .animation(.smooth(duration: 0.25), value: browserManager.showTabClosureToast)
            .animation(.smooth(duration: 0.25), value: windowState.isShowingCopyURLToast)
            .animation(.smooth(duration: 0.25), value: windowState.isShowingShortcutConflictToast)
        }
        // Zoom control popup - separate from system toasts
        .overlay(alignment: .topTrailing) {
            if browserManager.shouldShowZoomPopup {
                ZoomPopupView(
                    zoomManager: browserManager.zoomManager,
                    onZoomIn: { browserManager.zoomInCurrentTab() },
                    onZoomOut: { browserManager.zoomOutCurrentTab() },
                    onZoomReset: { browserManager.resetZoomCurrentTab() },
                    onZoomPresetSelected: { zoomLevel in browserManager.applyZoomLevel(zoomLevel) },
                    onDismiss: { browserManager.shouldShowZoomPopup = false }
                )
                .transition(.scale(scale: 0.0, anchor: .top))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.shouldShowZoomPopup)
                .onTapGesture {
                    browserManager.shouldShowZoomPopup = false
                }
                .padding(10)
            }
        }
        // Lifecycle management
        .onAppear {
            hoverSidebarManager.attach(browserManager: browserManager)
            hoverSidebarManager.windowRegistry = windowRegistry
            hoverSidebarManager.nookSettings = nookSettings
            hoverSidebarManager.start()
            windowState.hoverSidebarManager = hoverSidebarManager
        }
        .onDisappear {
            hoverSidebarManager.stop()
        }
        // Handle shortcut conflict notifications
        .onReceive(NotificationCenter.default.publisher(for: .shortcutConflictDetected)) { notification in
            if let conflictInfo = notification.userInfo?["conflictInfo"] as? ShortcutConflictInfo,
               conflictInfo.windowId == windowState.id {
                windowState.shortcutConflictInfo = conflictInfo
                windowState.isShowingShortcutConflictToast = true
                
                // Auto-dismiss after 1.5 seconds (slightly longer than the 1s timeout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if windowState.shortcutConflictInfo?.timestamp == conflictInfo.timestamp {
                        windowState.isShowingShortcutConflictToast = false
                    }
                }
            }
        }
        // Handle shortcut conflict dismissal
        .onReceive(NotificationCenter.default.publisher(for: .shortcutConflictDismissed)) { notification in
            if let windowId = notification.userInfo?["windowId"] as? UUID,
               windowId == windowState.id {
                windowState.isShowingShortcutConflictToast = false
            }
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.gradientColorManager)
        .environmentObject(browserManager.splitManager)
        .environmentObject(hoverSidebarManager)
        .preferredColorScheme(windowState.gradient.primaryColor.isPerceivedDark ? .dark : .light)
    }

    // MARK: - Layout Components

    @ViewBuilder
    private func WindowBackground() -> some View {
        ZStack {
            
            BlurEffectView(material: nookSettings.currentMaterial, state: .followsWindowActiveState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SpaceGradientBackgroundView()


//            Rectangle()
//                .fill(Color.clear)
////                .universalGlassEffect(.regular.tint(Color(.windowBackgroundColor).opacity(0.35)), in: .rect(cornerRadius: 0))
//                .clipped()
        }
        .backgroundDraggable()
        .environment(windowState)
    }

    @ViewBuilder
    private func SidebarWebViewStack() -> some View {
        let aiVisible = windowState.isSidebarAIChatVisible
        let sidebarVisible = windowState.isSidebarVisible
        let sidebarOnLeft = nookSettings.sidebarPosition == .left

        // Fixed-order layout: [LeftSpacer] [WebContent] [RightSpacer]
        // WebContent always stays in the middle with stable view identity.
        // Spacer widths push content based on what's on each side.
        let leftWidth: CGFloat = {
            if sidebarOnLeft {
                return sidebarVisible ? windowState.sidebarWidth : 0
            } else {
                return aiVisible ? windowState.aiSidebarWidth : 0
            }
        }()

        let rightWidth: CGFloat = {
            if sidebarOnLeft {
                return aiVisible ? windowState.aiSidebarWidth : 0
            } else {
                return sidebarVisible ? windowState.sidebarWidth : 0
            }
        }()

        // Determine edge padding: remove padding when sidebar/AI is visible on that side
        let hasLeftContent = (sidebarOnLeft && sidebarVisible) || (!sidebarOnLeft && aiVisible)
        let hasRightContent = (!sidebarOnLeft && sidebarVisible) || (sidebarOnLeft && aiVisible)

        ZStack {
            // When pinned: sidebar sits below web content (zIndex 0) so position
            // swaps slide it under. When floating: above (zIndex 2) so it hovers.
            UnifiedSidebar()
                .zIndex(windowState.isSidebarVisible ? 0 : 2)

            if aiVisible {
                AISidebar()
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: sidebarOnLeft ? .trailing : .leading)
                    .zIndex(0)
            }

            // Web content column — above pinned sidebars so they slide under it
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: leftWidth)
                    .allowsHitTesting(false)
                WebContent()
                Color.clear
                    .frame(width: rightWidth)
                    .allowsHitTesting(false)
            }
            .padding(.leading, hasLeftContent ? 0 : 8)
            .padding(.trailing, hasRightContent ? 0 : 8)
            .zIndex(1)
        }
        .animation(.smooth(duration: 0.3), value: nookSettings.sidebarPosition)
    }

    /// Single sidebar instance rendered as an overlay — always the same view identity.
    /// When floating, uses offset to slide in/out (preserving view identity without removal).
    @ViewBuilder
    private func UnifiedSidebar() -> some View {
        let isPinned = windowState.isSidebarVisible
        let isFloatingVisible = hoverSidebarManager.isOverlayVisible && !isPinned
        let shouldShow = isPinned || isFloatingVisible
        let onLeft = nookSettings.sidebarPosition == .left
        // Slide offset: push sidebar fully off-screen in the appropriate direction
        // Total floating inset = 7pt padding × 2 sides (horizontal padding around the floating panel)
        let floatingInset: CGFloat = 14
        let slideOffset: CGFloat = {
            if isPinned || isFloatingVisible { return 0 }
            // Slide out to the left or right edge (sidebar width + both sides of floating padding)
            return onLeft ? -(windowState.sidebarWidth + floatingInset) : (windowState.sidebarWidth + floatingInset)
        }()

        ZStack(alignment: onLeft ? .leading : .trailing) {
            // Edge hover trigger zone — always present when sidebar is unpinned
            if !isPinned {
                Color.clear
                    .frame(width: hoverSidebarManager.triggerWidth)
                    .contentShape(Rectangle())
                    .onHover { isIn in
                        if isIn && !windowState.isSidebarVisible {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoverSidebarManager.isOverlayVisible = true
                            }
                        }
                        NSCursor.arrow.set()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: onLeft ? .leading : .trailing)
            }

            // The single sidebar panel — slides in/out when floating, always visible when pinned
            sidebarPanel(isPinned: isPinned)
                .offset(x: isPinned ? 0 : slideOffset)
                .allowsHitTesting(shouldShow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: onLeft ? .leading : .trailing)
        .animation(.easeInOut(duration: 0.15), value: isFloatingVisible)
        .animation(.smooth(duration: 0.3), value: nookSettings.sidebarPosition)
        // Briefly flash the floating sidebar on its new side after a position swap
        .onChange(of: nookSettings.sidebarPosition) { _, _ in
            guard !isPinned else { return }
            hoverSidebarManager.peekOverlay(for: 2.0)
        }
    }

    /// Wraps `SpacesSideBarView` with mode-dependent styling.
    @ViewBuilder
    private func sidebarPanel(isPinned: Bool) -> some View {
        let cornerRadius: CGFloat = isPinned ? 0 : 12
        let inset: CGFloat = isPinned ? 0 : 7
        let resizeHandleAlignment: Alignment = nookSettings.sidebarPosition == .left ? .trailing : .leading

        SpacesSideBarView()
            .frame(width: windowState.sidebarWidth)
            .frame(maxHeight: .infinity)
            .alwaysArrowCursor(when: !isPinned)
            .overlay(alignment: resizeHandleAlignment) {
                SidebarResizeView()
                    .frame(maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .zIndex(2000)
                    .opacity(isPinned ? 1 : 0)
                    .allowsHitTesting(isPinned)
            }
            .background {
                if !isPinned {
                    SpaceGradientBackgroundView()
                        .environmentObject(browserManager)
                        .environmentObject(browserManager.gradientColorManager)
                        .environment(windowState)
                        .clipShape(.rect(cornerRadius: cornerRadius))

                    Rectangle()
                        .fill(Color.clear)
                        .universalGlassEffect(.regular.tint(Color(.windowBackgroundColor).opacity(0.35)), in: .rect(cornerRadius: cornerRadius))
                }
            }
            .padding(nookSettings.sidebarPosition == .left ? .leading : .trailing, inset)
            .padding(.vertical, inset)
            .environmentObject(browserManager)
            .environment(windowState)
            .environment(commandPalette)
            .environmentObject(browserManager.gradientColorManager)
    }

    @ViewBuilder
    private func WebContent() -> some View {
        let cornerRadius: CGFloat = 8
        
        let hasTopBar = nookSettings.topBarAddressView
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if hasTopBar {
                    WebsiteLoadingIndicator()
                        .zIndex(3000)
                    
                    TopBarView()
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .zIndex(2500)
                } else {
                    WebsiteLoadingIndicator()
                }
                
                WebsiteView()
                    .zIndex(2000)
            }
            
            // Shadow shape positioned behind both top bar and webview
            // The webview will block the bottom shadow, leaving only top/left/right shadows visible
            if hasTopBar {
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius + 1,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius + 1,
                    style: .continuous
                )
                .frame(height: TopBarMetrics.height)
                .frame(maxWidth: .infinity)
                .offset(y: 8)
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                .allowsHitTesting(false)
                .zIndex(-1)
            }
        }
        .overlay {
            if aiService.isExecutingTools {
                ToolExecutionGlowView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func AISidebar() -> some View {
        let handleAlignment: Alignment = nookSettings.sidebarPosition == .left ? .leading : .trailing
        
        SidebarAIChat()
            .frame(width: windowState.aiSidebarWidth)
            .overlay(alignment: handleAlignment) {
                AISidebarResizeView()
                    .frame(maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
            .transition(
                .move(edge: nookSettings.sidebarPosition == .left ? .trailing : .leading)
                .combined(with: .opacity)
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .environment(nookSettings)
    }

    private func websiteColumnClipShape(cornerRadius: CGFloat, hasTopBar: Bool) -> AnyShape {
        if hasTopBar {
            return AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            ))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Profile Switch Toast View
private struct ProfileSwitchToastView: View {
    let toast: BrowserManager.ProfileSwitchToast
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ToastView {
            HStack {
                Text("Switched to \(toast.toProfile.name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .padding(4)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    }
            }
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                browserManager.hideProfileSwitchToast(for: windowState)
            }
        }
        .onTapGesture {
            browserManager.hideProfileSwitchToast(for: windowState)
        }
    }
}
