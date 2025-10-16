//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var isHovering: Bool = false
  
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

                    // Tweak Panel button
                    if browserManager.currentTab(for: windowState) != nil {
                        Button(action: {
                            browserManager.toggleTweakPanel()
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(textColor)
                                .frame(width: 20, height: 20)
                                .contentShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Tweak Panel")
                    }
                    
                    // Extension action buttons
                    if #available(macOS 15.5, *),
                       let extensionManager = browserManager.extensionManager,
                       browserManager.settingsManager.experimentalExtensions {
                        ExtensionActionView(extensions: extensionManager.installedExtensions)
                            .environmentObject(browserManager)
                    }
                }
                .padding(.horizontal, 12)
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
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        // Focus URL bar when tapping anywhere in the bar
        .contentShape(Rectangle())
        .onTapGesture {
            browserManager.focusURLBar()
        }

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
