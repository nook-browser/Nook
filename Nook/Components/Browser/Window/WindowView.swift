//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPaletteState.self) private var commandPalette
    @Environment(WindowRegistry.self) private var windowRegistry
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme

    // Calculate webview Y offset (where the web content starts)
    private var webViewYOffset: CGFloat {
        // Approximate Y offset for web content start (nav bar + URL bar + padding)
        if browserManager.settingsManager.topBarAddressView {
            return TopBarMetrics.height  // Top bar height
        } else {
            return 20  // Accounts for navigation area height
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpaceGradientBackgroundView()
                    .environment(windowState)
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

                // Main layout (webview extends full height when top bar is enabled)
                mainLayout

                // Hover-reveal Sidebar overlay (slides in over web content)
                SidebarHoverOverlayView()
                    .environmentObject(hoverSidebarManager)
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
                                    .environmentObject(browserManager)
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
                hoverSidebarManager.windowRegistry = windowRegistry
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
                    .environment(windowState)
                    .zIndex(2000)  // Higher z-index to ensure it's above all other elements
                    .environment(windowState)
            }
        }
            .environmentObject(browserManager)
            .environment(windowState)
    }

    @ViewBuilder
    private var websiteColumn: some View {
        let cornerRadius: CGFloat = {
            if #available(macOS 26.0, *) {
                return 12
            } else {
                return 6
            }
        }()
        
        let hasTopBar = browserManager.settingsManager.topBarAddressView
        
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
        .padding(.top, 0)
        .padding(.bottom, 8)
        .clipShape(websiteColumnClipShape(cornerRadius: cornerRadius, hasTopBar: hasTopBar))
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

    @ViewBuilder
    private var aiSidebar: some View {
        let handleAlignment: Alignment = browserManager.settingsManager.sidebarPosition == .left ? .leading : .trailing

        SidebarAIChat()
            .frame(width: windowState.aiSidebarWidth)
            .overlay(alignment: handleAlignment) {
                AISidebarResizeView()
                    .frame(maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
            .transition(
                .move(edge: browserManager.settingsManager.sidebarPosition == .left ? .trailing : .leading)
                    .combined(with: .opacity)
            )
            .environmentObject(browserManager)
            .environment(windowState)
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
