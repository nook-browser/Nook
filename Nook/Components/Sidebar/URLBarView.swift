//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                    if(browserManager.tabManager.currentTab != nil) {
                        Text(
                            displayURL
                        )
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                        Text("Search or Enter URL...")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    // PiP button (show when video content is available or PiP is active)
                    if let currentTab = browserManager.tabManager.currentTab,
                       (currentTab.hasVideoContent || currentTab.hasPiPActive) {
                        Button(action: {
                            currentTab.requestPictureInPicture()
                        }) {
                            Image(systemName: currentTab.hasPiPActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textPrimary.opacity(currentTab.hasPiPActive ? 1.0 : 0.7))
                        }
                        .buttonStyle(.plain)
                        .help(currentTab.hasPiPActive ? "Exit Picture in Picture" : "Enter Picture in Picture")
                    }
                    
                    // Extension action buttons
                    if #available(macOS 15.5, *),
                       let extensionManager = browserManager.extensionManager {
                        ExtensionActionView(extensions: extensionManager.installedExtensions)
                            .environmentObject(browserManager)
                    }
                }
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(
            ZStack {
                BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active)
                Color.white.opacity(isHovering ? 0.2 : 0.1)
            }
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
    
    private var displayURL: String {
            guard let url = browserManager.tabManager.currentTab?.url else {
                return ""
            }
            return formatURL(url)
        }
        
        private func formatURL(_ url: URL) -> String {
            guard let host = url.host else {
                return url.absoluteString
            }
            
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            
            return cleanHost
        }
}
