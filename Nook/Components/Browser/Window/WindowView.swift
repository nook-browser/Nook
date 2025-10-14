//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.nookSettings) private var settings

    // Calculate webview Y offset (where the web content starts)
    private var webViewYOffset: CGFloat {
        // Approximate Y offset for web content start (nav bar + URL bar + padding)
        if settings.topBarAddressView {
            return 44  // Top bar height
        } else {
            return 20  // Accounts for navigation area height
        }
    }

    var body: some View {
        let isDark = colorScheme == .dark
        GeometryReader { geometry in
            ZStack {
                // Gradient background for the current space (bottom-most layer)
                SpaceGradientBackgroundView()
                    .environment(windowState)
                
                // Attach background context menu to the window background layer
                Color.white.opacity(isDark ? 0.3 : 0.4)
                    .ignoresSafeArea(.all)
                WindowBackgroundView()
                    .contextMenu {
                        Button("Customize Space Gradient...") {
                            browserManager.showGradientEditor()
                        }
                        .disabled(browserManager.tabManager.currentSpace == nil)
                    }

                // Top bar when enabled
                if settings.topBarAddressView {
                    VStack(spacing: 0) {
                        TopBarView()
                            .environment(browserManager)
                            .environment(windowState)
                            .background(Color.clear)
                        
                        mainLayout
                    }
                    
                    // TopBar Command Palette overlay
                    TopBarCommandPalette()
                        .environment(browserManager)
                        .environment(windowState)
                        .zIndex(3000)
                } else {
                    mainLayout
                }

                // Mini command palette anchored exactly to URL bar's top-left
                // Only show when topbar is disabled
                if !settings.topBarAddressView {
                    MiniCommandPaletteOverlay()
                        .environment(windowState)
                }

                // Hover-reveal Sidebar overlay (slides in over web content)
                SidebarHoverOverlayView()
                    .environment(hoverSidebarManager)
                    .environment(windowState)

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
                                    .environment(browserManager)
                                    .environment(windowState)
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
            .environment(browserManager)
            .environment(browserManager.splitManager)
            .environment(hoverSidebarManager)
        }
    }

    @ViewBuilder
    private var mainLayout: some View {
        let aiVisible = windowState.isSidebarAIChatVisible
        let aiAppearsOnTrailingEdge = settings.sidebarPosition == .left

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
        .padding(.trailing, windowState.isFullScreen ? 0 : (windowState.isSidebarVisible && settings.sidebarPosition == .right ? 0 : aiVisible ? 0 : 8))
        .padding(.leading, windowState.isFullScreen ? 0 : (windowState.isSidebarVisible && settings.sidebarPosition == .left ? 0 : aiVisible ? 0 : 8))
    }

    private var sidebarColumn: some View {
        SidebarView()
        // Overlay the resize handle spanning the sidebar/webview boundary
        .overlay(alignment: settings.sidebarPosition == .left ? .trailing : .leading) {
            if windowState.isSidebarVisible {
                // Position to span 14pts into sidebar and 2pts into web content (moved 6pts left)
                SidebarResizeView()
                
                    .frame(maxHeight: .infinity)
                    .environment(browserManager)
                    .environment(windowState)
                    .zIndex(2000)  // Higher z-index to ensure it's above all other elements
                    .environment(windowState)
            }
        }
            .environment(browserManager)
            .environment(windowState)
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
        let handleAlignment: Alignment = settings.sidebarPosition == .left ? .leading : .trailing

        SidebarAIChat()
            .frame(width: windowState.aiSidebarWidth)
            .overlay(alignment: handleAlignment) {
                AISidebarResizeView()
                    .frame(maxHeight: .infinity)
                    .environment(browserManager)
                    .environment(windowState)
            }
            .transition(
                .move(edge: settings.sidebarPosition == .left ? .trailing : .leading)
                    .combined(with: .opacity)
            )
            .environment(browserManager)
            .environment(windowState)
            .nookSettings(settings)
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
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) private var settings

    var body: some View {
        let isActiveWindow =
            browserManager.isActive(windowState)
        let isVisible =
            isActiveWindow && windowState.isMiniCommandPaletteVisible
            && !windowState.isCommandPaletteVisible

        ZStack(alignment: settings.sidebarPosition == .left ? .topLeading : .topTrailing) {
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
                let topBarHeight: CGFloat = settings.topBarAddressView ? 44 : 0
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
                .offset(x: settings.sidebarPosition == .left ? anchorX : -anchorX, y: anchorY)
                .zIndex(1)
            }
        }
        .allowsHitTesting(isVisible)
        .zIndex(999) // ensure above web content
    }
}
