//
//  URLBarView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import AppKit

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    @State private var isHovering: Bool = false
    @State private var showCheckmark: Bool = false
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
                    
                    // Copy link button (show on hover when tab is selected)
                    if isHovering, let currentTab = browserManager.currentTab(for: windowState) {
                        Button("Copy Link", systemImage: showCheckmark ? "checkmark" : "link") {
                            copyURLToClipboard(currentTab.url.absoluteString)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(URLBarButtonStyle())
                        .foregroundStyle(Color.primary)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .contentTransition(.symbolEffect(.replace))
                    }
                    
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
                    if isSidebarHovered || browserManager.isExtensionPopupActive {
                        if #available(macOS 15.5, *),
                           let extensionManager = browserManager.extensionManager,
                           nookSettings.experimentalExtensions {
                            ExtensionActionView(extensions: extensionManager.installedExtensions)
                                .environmentObject(browserManager)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
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
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabHoverDark : AppColors.pinnedTabHoverLight
        } else {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabIdleDark : AppColors.pinnedTabIdleLight
        }
    }
    private var textColor: Color {
        return browserManager.gradientColorManager.isDark ? AppColors.iconActiveDark : AppColors.iconActiveLight
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
    
    private func copyURLToClipboard(_ urlString: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        
        // Show checkmark icon briefly
        withAnimation(.easeInOut(duration: 0.2)) {
            showCheckmark = true
        }
        
        // Show toast notification
        windowState.isShowingCopyURLToast = true
        
        // Reset checkmark after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCheckmark = false
            }
        }
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            windowState.isShowingCopyURLToast = false
        }
    }
}

// MARK: - URL Bar Button Style
struct URLBarButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @State private var isHovering: Bool = false
    
    private let cornerRadius: CGFloat = 12
    private let size: CGFloat = 28
    private let borderInset: CGFloat = 4
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.primary.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))
                .frame(width: size, height: size)
            
            configuration.label
                .foregroundStyle(.primary)
        }
        .opacity(isEnabled ? 1.0 : 0.3)
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func backgroundColorOpacity(isPressed: Bool) -> Double {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? 0.2 : 0.1
        } else {
            return 0.0
        }
    }
}
