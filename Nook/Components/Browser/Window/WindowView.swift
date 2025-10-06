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
        return 20  // Accounts for navigation area height
    }

    // To reverse the sidebar and window, for left/right switching
    enum SidebarItems: String, CaseIterable, Identifiable {
        case sidebar,windowVStack

        var id: String { self.rawValue }
    }
    @State private var sidebarItems: [SidebarItems] = [.sidebar, .windowVStack]
    
    private var sortedSidebarItems: [SidebarItems] {
        browserManager.settingsManager.sidebarPosition == .left ? sidebarItems : sidebarItems.reversed()
    }

    var body: some View {
        let isDark = colorScheme == .dark
        GeometryReader { geometry in
            ZStack {
                // Gradient background for the current space (bottom-most layer)
                SpaceGradientBackgroundView()
                    .environmentObject(windowState)
                
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

                // Main content flush: sidebar touches left edge; webview touches sidebar
                HStack(spacing: 0) {
                    ForEach(sortedSidebarItems, id: \.self) { item in
                        switch item {
                        case .sidebar:
                            SidebarView()
                                .environmentObject(browserManager)
                                .environmentObject(windowState)
                        case .windowVStack:
                            VStack(spacing: 0) {
                                WebsiteLoadingIndicator()
                                WebsiteView()
                            }
                            .padding(.bottom, 8)
                            .zIndex(2000)

                        }
                    }

                }
                // Overlay the resize handle spanning the sidebar/webview boundary
                .overlay(alignment: browserManager.settingsManager.sidebarPosition == .left ? .topLeading : .topTrailing) {
                    if windowState.isSidebarVisible {
                        // Calculate dynamic webview height based on window size
                        let dynamicWebViewHeight = geometry.size.height - 40  // Subtract navigation area

                        // Position to span 14pts into sidebar and 2pts into web content (moved 6pts left)
                        SidebarResizeView()
                            .frame(height: dynamicWebViewHeight)  // Dynamic height based on window size
                            .offset(
                                x: browserManager.settingsManager.sidebarPosition == .left ? windowState.sidebarWidth : -windowState.sidebarWidth,
                                y: webViewYOffset
                            )  // Position to match webview
                            .zIndex(2000)  // Higher z-index to ensure it's above all other elements
                            .environmentObject(windowState)
                            .border(Color.red, width: 10)
                    }
                }

                // Mini command palette anchored exactly to URL bar's top-left
                MiniCommandPaletteOverlay()
                    .environmentObject(windowState)

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
                let fallbackY: CGFloat =
                    8 /* sidebar top padding */ + 30 /* nav bar */
                    + 8 /* vstack spacing */
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
