//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering: Bool = false
    var isSidebarHovered: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                    if browserManager.currentTab(for: windowState) != nil {
                        Text(
                            displayURL
                        )
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
                       (currentTab.hasVideoContent || currentTab.hasPiPActive) {
                        Button(action: {
                            currentTab.requestPictureInPicture()
                        }) {
                            Image(systemName: currentTab.hasPiPActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 12))
                                .foregroundStyle(textColor.opacity(currentTab.hasPiPActive ? 1.0 : 0.7))
                        }
                        .buttonStyle(.plain)
                        .help(currentTab.hasPiPActive ? "Exit Picture in Picture" : "Enter Picture in Picture")
                    }
                    
                    // Extension action buttons
                    if isSidebarHovered {
                        if #available(macOS 15.5, *),
                           let extensionManager = browserManager.extensionManager,
                           nookSettings.experimentalExtensions {
                            ExtensionActionView(extensions: extensionManager.installedExtensions)
                                .environmentObject(browserManager)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 5)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(
           backgroundColor
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Report the frame in the window space so we can overlay the mini palette above all content
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: URLBarFramePreferenceKey.self,
                    value: proxy.frame(in: .named("WindowSpace"))
                )
            }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        // Focus URL bar when tapping anywhere in the bar
        .contentShape(Rectangle())
        .onTapGesture {
            let currentURL = browserManager.currentTab(for: windowState)?.url.absoluteString ?? ""
            windowState.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
        }
        
    }
    
    private var backgroundColor: Color {
        if isHovering {
            return colorScheme == .dark ? AppColors.pinnedTabHoverLight : AppColors.pinnedTabHoverDark
        } else {
            return colorScheme == .dark ? AppColors.pinnedTabIdleLight : AppColors.pinnedTabIdleDark
        }
    }
    private var textColor: Color {
        return colorScheme == .dark ? AppColors.iconActiveLight : AppColors.iconActiveDark
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
