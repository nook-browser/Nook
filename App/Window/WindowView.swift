//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import SwiftUI

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(WindowRegistry.self) private var windowRegistry
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

            // Hover-reveal Sidebar overlay (slides in over web content)
            SidebarHoverOverlayView()
                .environmentObject(hoverSidebarManager)
                .environment(windowState)

            CommandPaletteView()
            DialogView()

            // Peek overlay for external link previews
            PeekOverlayView()
        }
        // Find bar overlay - centered at top
        .overlay(alignment: .top) {
            if browserManager.findManager.isFindBarVisible {
                FindBarView(findManager: browserManager.findManager)
                    .frame(maxWidth: 500)
                    .padding(.top, 20)
            }
        }
        // System notification toasts - top trailing corner
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                // Profile switch toast
                if windowState.isShowingProfileSwitchToast,
                   let toast = windowState.profileSwitchToast
                {
                    ProfileSwitchToastView(toast: toast)
                        .transition(.scale(scale: 0.0, anchor: .top))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: windowState.isShowingProfileSwitchToast)
                        .onTapGesture {
                            browserManager.hideProfileSwitchToast(for: windowState)
                        }
                }

                // Tab closure toast
                if browserManager.showTabClosureToast && browserManager.tabClosureToastCount > 0 {
                    TabClosureToast()
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .transition(.scale(scale: 0.0, anchor: .top))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.showTabClosureToast)
                        .onTapGesture {
                            browserManager.hideTabClosureToast()
                        }
                }
                
                // Copy URL toast
                if windowState.isShowingCopyURLToast {
                    CopyURLToast()
                        .environment(windowState)
                        .transition(.scale(scale: 0.0, anchor: .top))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: windowState.isShowingCopyURLToast)
                        .onTapGesture {
                            windowState.isShowingCopyURLToast = false
                        }
                }
            }
            .padding(10)
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
        }
        .onDisappear {
            hoverSidebarManager.stop()
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
        let aiAppearsOnTrailingEdge = nookSettings.sidebarPosition == .left
        let sidebarVisible = windowState.isSidebarVisible
        let sidebarOnRight = nookSettings.sidebarPosition == .right
        let sidebarOnLeft = nookSettings.sidebarPosition == .left
        
        HStack(spacing: 0) {
            if aiAppearsOnTrailingEdge {
                SpacesSidebar()
                WebContent()
                if aiVisible {
                    AISidebar()
                }
            } else {
                if aiVisible {
                    AISidebar()
                }
                WebContent()
                SpacesSidebar()
            }
        }
        // Apply padding similar to regular sidebar: remove padding when sidebar/AI is visible on that side
        // When sidebar is on left, AI appears on right (trailing); when sidebar is on right, AI appears on left (leading)
        .padding(.trailing, (sidebarVisible && sidebarOnRight) || (aiVisible && sidebarOnLeft) ? 0 : 8)
        .padding(.leading, (sidebarVisible && sidebarOnLeft) || (aiVisible && sidebarOnRight) ? 0 : 8)
    }

    @ViewBuilder
    private func SpacesSidebar() -> some View {
        if windowState.isSidebarVisible {
            SpacesSideBarView()
                .frame(width: windowState.sidebarWidth)
                .overlay(alignment: nookSettings.sidebarPosition == .left ? .trailing : .leading) {
                    SidebarResizeView()
                        .frame(maxHeight: .infinity)
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .zIndex(2000)
                        .environment(windowState)
                }
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(commandPalette)
                .environmentObject(browserManager.gradientColorManager)
        }
    }

    @ViewBuilder
    private func WebContent() -> some View {
        let cornerRadius: CGFloat = {
            if #available(macOS 26.0, *) {
                return 8
            } else {
                return 8
            }
        }()
        
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
