//
//  TopBarView.swift
//  Nook
//
//  Created by Assistant on 23/09/2025.
//

import SwiftUI
import AppKit

enum TopBarMetrics {
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 20
}

struct TopBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @StateObject private var tabWrapper = ObservableTabWrapper()
    @State private var isHovering: Bool = false
    @State private var showZoomPopup: Bool = false
    @State private var previousTabId: UUID? = nil
    
    var body: some View {
        let cornerRadius: CGFloat = {
            if #available(macOS 26.0, *) {
                return 12
            } else {
                return 6
            }
        }()
        
        let currentTab = browserManager.currentTab(for: windowState)
        let hasPiPControl = currentTab?.hasVideoContent == true || browserManager.currentTabHasPiPActive()
        
        ZStack {
            HStack(spacing: 12) {
                navigationControls
                
                if hasPiPControl, let tab = currentTab {
                    pipButton(for: tab)
                }
                
                if currentTab != nil {
                    zoomButton
                }
                
                Spacer()
            }
            .padding(.vertical, TopBarMetrics.verticalPadding)
            
            urlBar
                .padding(.vertical, TopBarMetrics.verticalPadding)
        }
        .padding(.horizontal, TopBarMetrics.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: TopBarMetrics.height)
        .background(topBarBackgroundColor)
        .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: topBarBackgroundColor)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: cornerRadius,
            style: .continuous
        ))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: URLBarFramePreferenceKey.self, value: geometry.frame(in: .named("WindowSpace")))
            }
        )
        .onAppear {
            tabWrapper.setContext(browserManager: browserManager, windowState: windowState)
            updateCurrentTab()
            // Initialize previousTabId to current tab so first color change doesn't animate
            previousTabId = browserManager.currentTab(for: windowState)?.id
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { oldId, newId in
            previousTabId = oldId
            updateCurrentTab()
            // Update previousTabId after a brief delay so next color change within this tab will animate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                previousTabId = newId
            }
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.pageBackgroundColor) { _, _ in
            // Color changes will trigger animations automatically via computed properties
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            updateCurrentTab()
        }
        .overlay(
            Group {
                if showZoomPopup {
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
                            showZoomPopup = false
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16)
                    .padding(.top, 60)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showZoomPopup)
        )
    }

    private var navigationControls: some View {
        HStack(spacing: 12) {
            Button("Go Back", systemImage: "arrow.backward", action: goBack)
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(navButtonColor)
                .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: navButtonColor)
                .disabled(!tabWrapper.canGoBack)
                .opacity(tabWrapper.canGoBack ? 1.0 : 0.4)
                .contextMenu {
                    NavigationHistoryContextMenu(
                        historyType: .back,
                        windowState: windowState
                    )
                }
            
            Button("Go Forward", systemImage: "arrow.forward", action: goForward)
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(navButtonColor)
                .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: navButtonColor)
                .disabled(!tabWrapper.canGoForward)
                .opacity(tabWrapper.canGoForward ? 1.0 : 0.4)
                .contextMenu {
                    NavigationHistoryContextMenu(
                        historyType: .forward,
                        windowState: windowState
                    )
                }
            
            Button("Reload", systemImage: "arrow.clockwise", action: refreshCurrentTab)
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(navButtonColor)
                .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: navButtonColor)
        }
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            if browserManager.currentTab(for: windowState) != nil {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(urlBarTextColor)
                    .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
                
                Text(displayURL)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(urlBarTextColor)
                    .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(urlBarTextColor)
                    .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
                Text("Search or Enter URL...")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(urlBarTextColor)
                    .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(urlBarBackgroundColor)
        .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            browserManager.openCommandPaletteWithCurrentURL()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private func updateCurrentTab() {
        tabWrapper.updateTab(browserManager.currentTab(for: windowState))
    }
    
    private func goBack() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goBack()
        } else {
            tabWrapper.tab?.goBack()
        }
    }
    
    private func goForward() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goForward()
        } else {
            tabWrapper.tab?.goForward()
        }
    }
    
    private func refreshCurrentTab() {
        tabWrapper.tab?.refresh()
    }
    
    // Determine if we should animate color changes (within same tab) or snap (tab switch)
    private var shouldAnimateColorChange: Bool {
        let currentTabId = browserManager.currentTab(for: windowState)?.id
        return currentTabId == previousTabId
    }
    
    // Top bar background color - matches webview background
    private var topBarBackgroundColor: Color {
        if let currentTab = browserManager.currentTab(for: windowState),
           let pageColor = currentTab.pageBackgroundColor {
            return Color(nsColor: pageColor)
        }
        // Fallback to gradient-based color when no tab or color available
        // This ensures the top bar still has a background even before color extraction
        return browserManager.gradientColorManager.isDark ? 
            Color(nsColor: .windowBackgroundColor).opacity(0.95) : 
            Color(nsColor: .windowBackgroundColor).opacity(0.98)
    }
    
    // Nav button color - light on dark backgrounds, dark on light backgrounds
    private var navButtonColor: Color {
        if let currentTab = browserManager.currentTab(for: windowState),
           let pageColor = currentTab.pageBackgroundColor {
            return pageColor.isPerceivedDark ? 
                Color.white.opacity(0.9) : 
                Color.black.opacity(0.8)
        }
        
        // Fallback
        return browserManager.gradientColorManager.isDark ? 
            Color.white.opacity(0.9) : 
            Color.black.opacity(0.8)
    }
    
    // URL bar background color - slightly adjusted for visual distinction
    private var urlBarBackgroundColor: Color {
        if let currentTab = browserManager.currentTab(for: windowState),
           let pageColor = currentTab.pageBackgroundColor {
            let baseColor = Color(nsColor: pageColor)
            if isHovering {
                // Slightly lighter/darker on hover
                return adjustColorBrightness(baseColor, factor: pageColor.isPerceivedDark ? 1.15 : 0.95)
            } else {
                // Slightly darker/lighter for subtle distinction from top bar
                return adjustColorBrightness(baseColor, factor: pageColor.isPerceivedDark ? 1.1 : 0.98)
            }
        }
        // Fallback to original AppColors when no webview color available
        if isHovering {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabHoverDark : AppColors.pinnedTabHoverLight
        } else {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabIdleDark : AppColors.pinnedTabIdleLight
        }
    }
    
    // Text color for URL bar - ensures proper contrast
    private var urlBarTextColor: Color {
        if let currentTab = browserManager.currentTab(for: windowState),
           let pageColor = currentTab.pageBackgroundColor {
            return pageColor.isPerceivedDark ? 
                Color.white.opacity(0.9) : 
                Color.black.opacity(0.8)
        }
        // Fallback to original text color logic
        return browserManager.gradientColorManager.isDark ? AppColors.spaceTabTextDark : AppColors.spaceTabTextLight
    }
    
    // Helper to adjust color brightness
    private func adjustColorBrightness(_ color: Color, factor: CGFloat) -> Color {
        #if canImport(AppKit)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return color }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Clamp values between 0 and 1
        r = min(1.0, max(0.0, r * factor))
        g = min(1.0, max(0.0, g * factor))
        b = min(1.0, max(0.0, b * factor))
        
        return Color(nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: a))
        #else
        return color
        #endif
    }
    
    private var displayURL: String {
        guard let currentTab = browserManager.currentTab(for: windowState) else {
            return ""
        }
        return formatURL(currentTab.url)
    }
    
    private func formatURL(_ url: URL) -> String {
        guard let host = url.host else {
            return url.absoluteString
        }
        
        let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        
        return cleanHost
    }
    
    private func pipButton(for tab: Tab) -> some View {
        Button(action: {
            tab.requestPictureInPicture()
        }) {
            Image(systemName: browserManager.currentTabHasPiPActive() ? "pip.exit" : "pip.enter")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(urlBarTextColor)
                .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
                .frame(width: 16, height: 16)
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var zoomButton: some View {
        Button(action: {
            showZoomPopup.toggle()
        }) {
            HStack(spacing: 2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                Text(browserManager.getCurrentZoomPercentage())
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(urlBarTextColor)
            .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(urlBarBackgroundColor.opacity(0.9))
            )
            .animation(shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil, value: urlBarBackgroundColor)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
