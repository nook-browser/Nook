//
//  TopBarView.swift
//  Nook
//
//  Created by Assistant on 23/09/2025.
//

import SwiftUI

struct TopBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @StateObject private var tabWrapper = ObservableTabWrapper()
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Far left: Mac traffic light buttons
            MacButtonsView()
                .frame(width: 70)
            
            // Left: Sidebar toggle button
            NavButton(iconName: browserManager.settingsManager.sidebarPosition == .left ? "sidebar.left" : "sidebar.right", disabled: false, action: {
                browserManager.toggleSidebar(for: windowState)
            })
            
            Spacer()
            
            // Center: Navigation controls + URL bar
            HStack(spacing: 12) {
                // Navigation controls
                HStack(spacing: 4) {
                    NavButton(
                        iconName: "arrow.backward",
                        disabled: !tabWrapper.canGoBack,
                        action: goBack
                    )
                    .contextMenu {
                        NavigationHistoryContextMenu(
                            historyType: .back,
                            windowState: windowState
                        )
                    }
                    
                    NavButton(
                        iconName: "arrow.forward",
                        disabled: !tabWrapper.canGoForward,
                        action: goForward
                    )
                    .contextMenu {
                        NavigationHistoryContextMenu(
                            historyType: .forward,
                            windowState: windowState
                        )
                    }
                    
                    RefreshButton(action: refreshCurrentTab)
                }
                
                // URL bar
                HStack(spacing: 8) {
                    if let currentTab = browserManager.currentTab(for: windowState) {
                        Image(systemName: "link")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textColor)
                        
                        Text(displayURL)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(textColor)
                        Text("Search or Enter URL...")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(textColor)
                    }
                    
                    Spacer()
                    
                    // PiP button (show when video content is available or PiP is active)
                    if let currentTab = browserManager.currentTab(for: windowState),
                       currentTab.hasVideoContent || browserManager.currentTabHasPiPActive() {
                        Button(action: {
                            currentTab.requestPictureInPicture()
                        }) {
                            Image(systemName: "pip.enter")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(textColor)
                                .frame(width: 20, height: 20)
                                .contentShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovering = hovering
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
                .onTapGesture {
                    browserManager.focusURLBar()
                }
                .frame(maxWidth: 400)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: URLBarFramePreferenceKey.self, value: geometry.frame(in: .named("WindowSpace")))
            }
        )
        .onAppear {
            tabWrapper.setContext(browserManager: browserManager, windowState: windowState)
            updateCurrentTab()
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            updateCurrentTab()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            updateCurrentTab()
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
    
    private var backgroundColor: Color {
        if isHovering {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabHoverDark : AppColors.pinnedTabHoverLight
        } else {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabIdleDark : AppColors.pinnedTabIdleLight
        }
    }
    
    private var textColor: Color {
        return browserManager.gradientColorManager.isDark ? AppColors.spaceTabTextDark : AppColors.spaceTabTextLight
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
}
