// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  WindowView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(AIService.self) private var aiService
    @Environment(TabOrganizerManager.self) private var tabOrganizerManager
    @Environment(\.nookSettings) var nookSettings
    @Environment(\.openSettings) private var openSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            WindowBackground()
                .contextMenu {
                    Button("Space Settings...") {
                        SettingsNavigation.shared.currentSettingsTab = .spaces
                        openSettings()
                    }
                    .disabled(windowState.spaceID.flatMap { tabs.space($0) } == nil)
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

            // Find bar - always rendered (24/7), visibility controlled via opacity
            FindBarView(findManager: browserManager.findManager)
                .zIndex(10000)

        }
        // In-window so the menus get the key window's active glass; see ExtensionLibraryOverlay.
        .overlayPreferenceValue(ExtensionLibraryAnchorKey.self) { anchor in
            ExtensionLibraryOverlay(anchor: anchor)
                .zIndex(9000)
        }
        // System notification toasts - top trailing corner
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                // Tab closure toast
                if browserManager.showTabClosureToast && browserManager.tabClosureToastCount > 0 {
                    TabClosureToast()
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
                    ShortcutConflictToast(
                        shortcut: conflictInfo.keyCombination.displayString,
                        websiteName: conflictInfo.websiteName,
                        nookActionName: conflictInfo.nookActionName
                    )
                        .environment(windowState)
                }
            }
            .padding(10)
            // Animate toast insertions/removals
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
            applyAccent(spaceAccentHex, animate: false)
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
        // The app-wide accent follows the active window's space.
        .onChange(of: spaceAccentHex) { _, hex in applyAccent(hex, animate: true) }
        .onChange(of: windowRegistry.activeWindowId) { _, _ in applyAccent(spaceAccentHex, animate: false) }
        // Handle organize tabs notification from keyboard shortcut manager
        .onReceive(NotificationCenter.default.publisher(for: .organizeTabsRequested)) { _ in
            guard windowRegistry.activeWindow?.id == windowState.id,
                  let spaceID = windowState.spaceID else { return }
            Task {
                await tabOrganizerManager.organizeTabs(in: spaceID, using: tabs)
            }
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.gradientColorManager)
        .environmentObject(browserManager.splitManager)
        .environmentObject(hoverSidebarManager)
        .preferredColorScheme(resolvedColorScheme)
    }

    /// Accent of the space this window shows; nil for private windows, which keep their own look.
    private var spaceAccentHex: String? {
        guard !windowState.isIncognito, let spaceID = windowState.spaceID else { return nil }
        return tabs.space(spaceID)?.accentHex
    }

    private func applyAccent(_ hex: String?, animate: Bool) {
        guard let hex, windowRegistry.activeWindowId == windowState.id else { return }
        let gradient = SpaceGradient.accent(hex: hex)
        if animate {
            browserManager.gradientColorManager.transition(to: gradient)
        } else {
            browserManager.gradientColorManager.setImmediate(gradient)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch nookSettings.appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil  // Follow system appearance
        }
    }

    // MARK: - Layout Components

    @ViewBuilder
    private func WindowBackground() -> some View {
        // Private windows keep the neutral incognito accent, never the space's color.
        let accent = windowState.isIncognito ? SpaceGradient.incognito.primaryColor : browserManager.gradientColorManager.accentColor
        let isActive = windowRegistry.activeWindowId == windowState.id

        NookDesign.Surface.containerGradient(accent: accent, isActive: isActive)
            // Private windows tint all chrome so they are never mistaken for a regular window.
            .overlay(windowState.isIncognito ? NookDesign.Surface.privateTint : Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundDraggable()
            .environment(windowState)
            .animation(NookDesign.Motion.standard, value: isActive)
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
            return 8
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

