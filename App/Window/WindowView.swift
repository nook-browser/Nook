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
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.nookSettings) var nookSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme

    // Calculate webview Y offset (where the web content starts)
    private var webViewYOffset: CGFloat {
        // Approximate Y offset for web content start (nav bar + URL bar + padding)
        if nookSettings.topBarAddressView {
            return TopBarMetrics.height  // Top bar height
        } else {
            return 20  // Accounts for navigation area height
        }
    }
    
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
    
    @ViewBuilder
    func WindowBackground() -> some View{
        ZStack{
            SpaceGradientBackgroundView()
            
            Rectangle()
                .fill(Color.clear)
                .universalGlassEffect(.regular.tint(Color(.windowBackgroundColor).opacity(0.35)), in: .rect(cornerRadius: 0))
                .clipped()
        }
        .backgroundDraggable()
        .environment(windowState)
    }
    
    
    @ViewBuilder
    func SidebarWebViewStack() -> some View{
        let aiVisible = windowState.isSidebarAIChatVisible
        let aiAppearsOnTrailingEdge = nookSettings.sidebarPosition == .left
        
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
        .padding(.trailing, windowState.isSidebarVisible && nookSettings.sidebarPosition == .right ? 0 : aiVisible ? 0 : 8)
        .padding(.leading, windowState.isSidebarVisible && nookSettings.sidebarPosition == .left ? 0 : aiVisible ? 0 : 8)
    }
    
    @ViewBuilder
    func SpacesSidebar() -> some View{
        SidebarView()
            .overlay(alignment: nookSettings.sidebarPosition == .left ? .trailing : .leading) {
                if windowState.isSidebarVisible {
                    SidebarResizeView()
                        .frame(maxHeight: .infinity)
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .zIndex(2000)
                        .environment(windowState)
                }
            }
            .environmentObject(browserManager)
            .environment(windowState)
    }
    
    @ViewBuilder
    func WebContent() -> some View{
        let cornerRadius: CGFloat = {
            if #available(macOS 26.0, *) {
                return 12
            } else {
                return 6
            }
        }()
        
        let hasTopBar = nookSettings.topBarAddressView
        
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
    
    @ViewBuilder
    func AISidebar() -> some View{
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
