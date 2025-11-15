//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme

    // Calculate webview Y offset (where the web content starts)
    private var webViewYOffset: CGFloat {
        // Approximate Y offset for web content start (nav bar + URL bar + padding)
        if browserManager.settingsManager.topBarAddressView {
            return 44  // Top bar height
        } else {
            return 20  // Accounts for navigation area height
        }
    }

    
    private var isActiveWindow: Bool {
        browserManager.activeWindowState?.id == windowState.id
    }

    private var gradient: SpaceGradient {
        isActiveWindow ? browserManager.gradientColorManager.displayGradient : windowState.activeGradient
    }
    
    var body: some View {
        let isDark = colorScheme == .dark
        GeometryReader { geometry in
            ZStack {
                // Gradient background for the current space (bottom-most layer)
                Color(.windowBackgroundColor).opacity(max(0, (0.35 - gradient.opacity)))
                
                SpaceGradientBackgroundView()
                    .environmentObject(browserManager)
                    .environmentObject(browserManager.gradientColorManager)
                    .environmentObject(windowState)
//                // Attach background context menu to the window background layer
//                Color.white.opacity(isDark ? 0.3 : 0.4)
//                    .ignoresSafeArea(.all)
                WindowBackgroundView()
                    .contextMenu {
                        Button("Customize Space Gradient...") {
                            browserManager.showGradientEditor()
                        }
                        .disabled(browserManager.tabManager.currentSpace == nil)
                    }

                // Top bar when enabled
                if browserManager.settingsManager.topBarAddressView {
                    VStack(spacing: 0) {
                        TopBarView()
                            .environmentObject(browserManager)
                            .environmentObject(windowState)
                            .background(Color.clear)
                        
                        mainLayout
                    }
                    
                    // TopBar Command Palette overlay
                    TopBarCommandPalette()
                        .environmentObject(browserManager)
                        .environmentObject(windowState)
                        .zIndex(3000)
                } else {
                    mainLayout
                }

                // Mini command palette anchored exactly to URL bar's top-left
                // Only show when topbar is disabled
                if !browserManager.settingsManager.topBarAddressView {
                    MiniCommandPaletteOverlay()
                        .environmentObject(windowState)
                }

                // Hover-reveal Sidebar overlay (slides in over web content)
                SidebarHoverOverlayView()
                    .environmentObject(hoverSidebarManager)
                    .environmentObject(windowState)

                CommandPaletteView()
                DialogView()

                // Peek overlay for external link previews
                PeekOverlayView()

                // Find bar overlay - centered top bar
                if browserManager.findManager.isFindBarVisible {
                    VStack {
                        HStack {
                            Spacer()
                            FindBarView(findManager: browserManager.findManager)
                                .frame(maxWidth: 500)
                            Spacer()
                        }
                        .padding(.top, 20)
                        Spacer()
                    }
                }

                
                // Toast overlays (matches WebsitePopup style/presentation)
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            // Profile switch toast
                            if windowState.isShowingProfileSwitchToast,
                                let toast = windowState.profileSwitchToast
                            {
                                ProfileSwitchToastView(toast: toast)
                                    .animation(
                                        .spring(
                                            response: 0.5,
                                            dampingFraction: 0.8
                                        ),
                                        value: windowState
                                            .isShowingProfileSwitchToast
                                    )
                                    .onTapGesture {
                                        browserManager.hideProfileSwitchToast(
                                            for: windowState
                                        )
                                    }
                            }

                            // Tab closure toast
                            if browserManager.showTabClosureToast
                                && browserManager.tabClosureToastCount > 0
                            {
                                TabClosureToast()
                                    .environmentObject(browserManager)
                                    .environmentObject(windowState)
                                    .animation(
                                        .spring(
                                            response: 0.5,
                                            dampingFraction: 0.8
                                        ),
                                        value: browserManager
                                            .showTabClosureToast
                                    )
                                    .onTapGesture {
                                        browserManager.hideTabClosureToast()
                                    }
                            }

                            // Zoom popup toast
                            if browserManager.shouldShowZoomPopup {
                                ZoomPopupView(
                                    zoomManager: browserManager.zoomManager,
                                    onZoomIn: {
                                        browserManager.zoomInCurrentTab()
                                    },
                                    onZoomOut: {
                                        browserManager.zoomOutCurrentTab()
                                    },
                                    onZoomReset: {
                                        browserManager.resetZoomCurrentTab()
                                    },
                                    onZoomPresetSelected: { zoomLevel in
                                        browserManager.applyZoomLevel(zoomLevel)
                                    },
                                    onDismiss: {
                                        browserManager.shouldShowZoomPopup = false
                                    }
                                )
                                .animation(
                                    .spring(
                                        response: 0.5,
                                        dampingFraction: 0.8
                                    ),
                                    value: browserManager.shouldShowZoomPopup
                                )
                                .onTapGesture {
                                    browserManager.shouldShowZoomPopup = false
                                }
                            }
                        }
                        .padding(10)
                    }
                    Spacer()
                }
            }
            // Named coordinate space for geometry preferences
            .coordinateSpace(name: "WindowSpace")
            // Keep BrowserManager aware of URL bar frame in window space
            .onPreferenceChange(URLBarFramePreferenceKey.self) { frame in
                browserManager.urlBarFrame = frame
                windowState.urlBarFrame = frame
            }
            // Attach hover sidebar manager lifecycle
            .onAppear {
                hoverSidebarManager.attach(browserManager: browserManager)
                hoverSidebarManager.start()
            }
            .onDisappear {
                hoverSidebarManager.stop()
            }
            .environmentObject(browserManager)
            .environmentObject(browserManager.gradientColorManager)
            .environmentObject(browserManager.splitManager)
            .environmentObject(hoverSidebarManager)
        }
    }

    @ViewBuilder
    private var mainLayout: some View {
        let aiVisible = windowState.isSidebarAIChatVisible
        let aiAppearsOnTrailingEdge = browserManager.settingsManager.sidebarPosition == .left

        HStack(spacing: 0) {
            if aiAppearsOnTrailingEdge {
                sidebarColumn
                websiteColumn
                if aiVisible {
                    aiSidebar
                }
            } else {
                if aiVisible {
                    aiSidebar
                }
                websiteColumn
                sidebarColumn
            }
        }
        .padding(.trailing, windowState.isSidebarVisible && browserManager.settingsManager.sidebarPosition == .right ? 0 : aiVisible ? 0 : 8)
        .padding(.leading, windowState.isSidebarVisible && browserManager.settingsManager.sidebarPosition == .left ? 0 : aiVisible ? 0 : 8)
    }

    private var sidebarColumn: some View {
        SidebarView()
        // Overlay the resize handle spanning the sidebar/webview boundary
        .overlay(alignment: browserManager.settingsManager.sidebarPosition == .left ? .trailing : .leading) {
            if windowState.isSidebarVisible {
                // Position to span 14pts into sidebar and 2pts into web content (moved 6pts left)
                SidebarResizeView()
                
                    .frame(maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
                    .zIndex(2000)  // Higher z-index to ensure it's above all other elements
                    .environmentObject(windowState)
            }
        }
            .environmentObject(browserManager)
            .environmentObject(windowState)
    }

    private var websiteColumn: some View {
        VStack(spacing: 0) {
            WebsiteLoadingIndicator()
            WebsiteView()
        }
        .padding(.bottom, 8)
        .zIndex(2000)
    }

    @ViewBuilder
    private var aiSidebar: some View {
        let handleAlignment: Alignment = browserManager.settingsManager.sidebarPosition == .left ? .leading : .trailing

        SidebarAIChat()
            .frame(width: windowState.aiSidebarWidth)
            .overlay(alignment: handleAlignment) {
                AISidebarResizeView()
                    .frame(maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environmentObject(windowState)
            }
            .transition(
                .move(edge: browserManager.settingsManager.sidebarPosition == .left ? .trailing : .leading)
                    .combined(with: .opacity)
            )
            .environmentObject(browserManager)
            .environmentObject(windowState)
            .environment(browserManager.settingsManager)
    }

}

// MARK: - Profile Switch Toast View
private struct ProfileSwitchToastView: View {
    let toast: BrowserManager.ProfileSwitchToast

    var body: some View {
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
        .padding(12)
        .background(Color(hex: "3E4D2E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 2)
        }
        .transition(.scale(scale: 0.0, anchor: .top))
    }
}

// MARK: - Mini Command Palette Overlay (above sidebar and webview)
private struct MiniCommandPaletteOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState

    var body: some View {
        let isActiveWindow =
            browserManager.activeWindowState?.id == windowState.id
        let isVisible =
            isActiveWindow && windowState.isMiniCommandPaletteVisible
            && !windowState.isCommandPaletteVisible

        ZStack(alignment: browserManager.settingsManager.sidebarPosition == .left ? .topLeading : .topTrailing) {
            if isVisible {
                // Click-away hit target
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        browserManager.hideMiniCommandPalette(for: windowState)
                    }

                // Use reported URL bar frame when reliable; otherwise compute manual fallback
                let barFrame = windowState.urlBarFrame
                let hasFrame = barFrame.width > 1 && barFrame.height > 1
                // Match sidebar's internal 8pt padding when geometry is unavailable
                let fallbackX: CGFloat = 8
                let topBarHeight: CGFloat = browserManager.settingsManager.topBarAddressView ? 44 : 0
                let fallbackY: CGFloat =
                    8 /* sidebar top padding */ + 30 /* nav bar */
                    + 8 /* vstack spacing */ + topBarHeight
                let anchorX = hasFrame ? barFrame.minX : fallbackX
                let anchorY = hasFrame ? barFrame.minY : fallbackY
                // let width = hasFrame ? barFrame.width : browserManager.sidebarWidth

                MiniCommandPaletteView(
                    forcedWidth: 400,
                    forcedCornerRadius: 12
                )
                .offset(x: browserManager.settingsManager.sidebarPosition == .left ? anchorX : -anchorX, y: anchorY)
                .zIndex(1)
            }
        }
        .allowsHitTesting(isVisible)
        .zIndex(999) // ensure above web content
    }
}
