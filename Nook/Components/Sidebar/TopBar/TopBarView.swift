//
//  TopBarView.swift
//  Nook
//
//  Created by Assistant on 23/09/2025.
//

import AppKit
import SwiftUI
import WebKit
import NookDesign
import NookWeb

enum TopBarMetrics {
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 5
}

struct TopBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.nookSettings) var nookSettings
    @State private var isHovering: Bool = false
    @State private var previousTabId: UUID? = nil

    var body: some View {
        let cornerRadius: CGFloat = NookDesign.Radius.md

        let currentTab = browserManager.tabs.selectedSession(in: windowState)
        let hasPiPControl =
            currentTab?.hasVideoContent == true
            || currentTab?.hasPiPActive == true

        ZStack {
            // Main content
            ZStack {
                HStack(spacing: 8) {
                    navigationControls

                    if hasPiPControl, let tab = currentTab {
                        pipButton(for: tab)
                    }

                    urlBar

                    Spacer()

                    if browserManager.nookSettings?.showAIAssistant ?? false
                        && !windowState.isSidebarAIChatVisible
                    {
                        ChatButton(navButtonColor: navButtonColor)
                    }

                }

            }
            .padding(.horizontal, TopBarMetrics.horizontalPadding)
            .padding(.vertical, TopBarMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: TopBarMetrics.height)
            .background(topBarBackgroundColor)
            .animation(
                shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
                value: topBarBackgroundColor
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottom) {
                // 1px bottom border - lighter when dark, darker when light
                Rectangle()
                    .fill(bottomBorderColor)
                    .frame(height: 1)
                    .animation(
                        shouldAnimateColorChange
                            ? NookDesign.Motion.standard : nil,
                        value: bottomBorderColor
                    )
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: URLBarFramePreferenceKey.self,
                        value: geometry.frame(in: .named("WindowSpace"))
                    )
            }
        )
        .onAppear {
            // Initialize previousTabId to the selection so the first color change doesn't animate
            previousTabId = windowState.selectedItemID
        }
        .onChange(of: windowState.selectedItemID) { oldId, newId in
            previousTabId = oldId
            // Update previousTabId after a brief delay so the next color change within this page animates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                previousTabId = newId
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 4) {
            Button("Go Back", systemImage: "chevron.backward", action: goBack)
                .labelStyle(.iconOnly)
                .buttonStyle(NookIconButtonStyle())
                .foregroundStyle(navButtonColor)
                .animation(
                    shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
                    value: navButtonColor
                )
                .disabled(!(session?.canGoBack ?? false))
                .opacity((session?.canGoBack ?? false) ? 1.0 : 0.4)
                .contextMenu {
                    NavigationHistoryContextMenu(
                        historyType: .back,
                        windowState: windowState
                    )
                }

            Button(
                "Go Forward",
                systemImage: "chevron.right",
                action: goForward
            )
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle())
            .foregroundStyle(navButtonColor)
            .animation(
                shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
                value: navButtonColor
            )
            .disabled(!(session?.canGoForward ?? false))
            .opacity((session?.canGoForward ?? false) ? 1.0 : 0.4)
            .contextMenu {
                NavigationHistoryContextMenu(
                    historyType: .forward,
                    windowState: windowState
                )
            }

            Button {
                if session?.isLoading == true {
                    session?.stop()
                } else {
                    refreshCurrentTab()
                }
            } label: {
                Image(systemName: session?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle())
            .foregroundStyle(navButtonColor)
            .animation(
                shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
                value: navButtonColor
            )
        }
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            if browserManager.tabs.selectedSession(in: windowState) != nil {
                // URL text area — tappable to open command palette
                Text(displayURL)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(urlBarTextColor)
                    .tracking(-0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let currentTab = browserManager.tabs.selectedSession(in: windowState) {
                            commandPalette.openWithCurrentURL(currentTab.url)
                        } else {
                            commandPalette.open()
                        }
                    }

                // Pinned extension buttons + library button (not covered by tap gesture)
                if let extensionManager = browserManager.extensionManager {
                    let pinnedIDs = browserManager.nookSettings?.pinnedExtensionIDs ?? []
                    let pinnedExtensions = extensionManager.installedExtensions.filter { pinnedIDs.contains($0.id) }

                    if !pinnedExtensions.isEmpty {
                        ExtensionActionView(extensions: pinnedExtensions)
                            .environmentObject(browserManager)
                    }

                    ExtensionLibraryButton()
                        .environmentObject(browserManager)
                        .onAppear {
                            let installedIDs = extensionManager.installedExtensions
                                .filter { $0.isEnabled }
                                .map { $0.id }
                            browserManager.nookSettings?.migrateExtensionPinStateIfNeeded(installedExtensionIDs: installedIDs)
                        }
                }
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(urlBarBackgroundColor)
        .animation(
            shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
            value: urlBarBackgroundColor
        )
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
    }

    /// Nil while another window holds the page: its controls stay inert until Move Here.
    private var session: PageSession? {
        browserManager.tabs.controllableSession(in: windowState)
    }

    /// This window's own view of the page, so a clone navigates in its window.
    private var windowWebView: WKWebView? {
        session.flatMap { browserManager.webViewCoordinator?.getWebView(for: $0.itemID, in: windowState.id) }
    }

    private func goBack() {
        if let webView = windowWebView { webView.goBack() } else { session?.goBack() }
    }

    private func goForward() {
        if let webView = windowWebView { webView.goForward() } else { session?.goForward() }
    }

    private func refreshCurrentTab() {
        session?.refresh()
    }

    // Determine if we should animate color changes (within same tab) or snap (tab switch)
    private var shouldAnimateColorChange: Bool {
        let selectedItemID = browserManager.tabs.selectedSession(in: windowState)?.id
        return selectedItemID == previousTabId
    }

    // Top bar background color - matches top-right pixel of webview
    private var topBarBackgroundColor: Color {
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let topBarColor = currentTab.topBarBackgroundColor
        {
            return Color(nsColor: topBarColor)
        }
        // Fallback to page background color if top bar color not available yet
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let pageColor = currentTab.pageBackgroundColor
        {
            return Color(nsColor: pageColor)
        }
        // Fallback to system theme colors when no tab or color available
        // This ensures the top bar has a proper background even before page loads
        return Color(nsColor: .windowBackgroundColor)
    }

    // Nav button color - light on dark backgrounds, dark on light backgrounds
    private var navButtonColor: Color {
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let topBarColor = currentTab.topBarBackgroundColor
        {
            return topBarColor.isPerceivedDark
                ? Color.white.opacity(0.9) : Color.black.opacity(0.8)
        }
        // Fallback to page background color
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let pageColor = currentTab.pageBackgroundColor
        {
            return pageColor.isPerceivedDark
                ? Color.white.opacity(0.9) : Color.black.opacity(0.8)
        }

        // Fallback
        return .primary
    }

    // URL bar background color - slightly adjusted for visual distinction
    private var urlBarBackgroundColor: Color {
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let topBarColor = currentTab.topBarBackgroundColor
        {
            let baseColor = Color(nsColor: topBarColor)
            if isHovering {
                // Slightly lighter/darker on hover
                return adjustColorBrightness(
                    baseColor,
                    factor: topBarColor.isPerceivedDark ? 1.15 : 0.95
                )
            } else {
                // Slightly darker/lighter for subtle distinction from top bar
                //                return adjustColorBrightness(baseColor, factor: topBarColor.isPerceivedDark ? 1.1 : 0.98)
                return .clear
            }
        }
        // Fallback to page background color
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let pageColor = currentTab.pageBackgroundColor
        {
            let baseColor = Color(nsColor: pageColor)
            if isHovering {
                // Slightly lighter/darker on hover
                return adjustColorBrightness(
                    baseColor,
                    factor: pageColor.isPerceivedDark ? 1.15 : 0.95
                )
            } else {
                // Slightly darker/lighter for subtle distinction from top bar
                return adjustColorBrightness(
                    baseColor,
                    factor: pageColor.isPerceivedDark ? 1.1 : 0.98
                )
            }
        }
        // Fallback to a surface token when no webview color available
        return isHovering ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill
    }

    // Text color for URL bar - ensures proper contrast
    private var urlBarTextColor: Color {
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let topBarColor = currentTab.topBarBackgroundColor
        {
            return topBarColor.isPerceivedDark
                ? Color.white.opacity(0.55) : Color.black.opacity(0.8)
        }
        // Fallback to page background color
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let pageColor = currentTab.pageBackgroundColor
        {
            return pageColor.isPerceivedDark
                ? Color.white.opacity(0.55) : Color.black.opacity(0.8)
        }
        // Fallback to original text color logic
        return .primary
    }

    // Bottom border color - lighter when dark, darker when light
    private var bottomBorderColor: Color {
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let topBarColor = currentTab.topBarBackgroundColor
        {
            let baseColor = Color(nsColor: topBarColor)
            // Make lighter if dark, darker if light
            return adjustColorBrightness(
                baseColor,
                factor: topBarColor.isPerceivedDark ? 1.2 : 0.85
            )
        }
        // Fallback to page background color
        if let currentTab = browserManager.tabs.selectedSession(in: windowState),
            let pageColor = currentTab.pageBackgroundColor
        {
            let baseColor = Color(nsColor: pageColor)
            return adjustColorBrightness(
                baseColor,
                factor: pageColor.isPerceivedDark ? 1.2 : 0.85
            )
        }
        // Fallback to system separator color
        return Color(nsColor: .separatorColor)
    }

    // Helper to adjust color brightness
    private func adjustColorBrightness(_ color: Color, factor: CGFloat) -> Color
    {
        #if canImport(AppKit)
            guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
                return color
            }
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)

            // Clamp values between 0 and 1
            r = min(1.0, max(0.0, r * factor))
            g = min(1.0, max(0.0, g * factor))
            b = min(1.0, max(0.0, b * factor))

            return Color(
                nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: a)
            )
        #else
            return color
        #endif
    }

    private var displayURL: AttributedString {
        guard let currentTab = browserManager.tabs.selectedSession(in: windowState)
        else {
            return ""
        }

        return formatURL(
            currentTab.url,
            title: currentTab.title,
            isHovering: isHovering
        )
    }

    private func formatURL(_ url: URL, title: String?, isHovering: Bool)
        -> AttributedString
    {
        if isHovering {
            guard let host = url.host else {
                return AttributedString(url.absoluteString)
            }

            let cleanHost =
                host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

            let hostString = AttributedString(cleanHost)

            var pathString = AttributedString()

            if !url.path.isEmpty {
                pathString += AttributedString(url.path)
            }

            if let query = url.query {
                pathString += AttributedString("?" + query)
            }

            pathString.foregroundColor = urlBarTextColor.opacity(0.35)

            return hostString + pathString
        }

        guard let host = url.host else {
            return AttributedString(url.absoluteString)
        }

        let cleanHost =
            host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        if url.path.isEmpty || url.path == "/" {
            return AttributedString(cleanHost)
        } else {
            let displayTitle = title ?? cleanHost
            var result = AttributedString(cleanHost)
            var titlePart = AttributedString(" / " + displayTitle)
            titlePart.foregroundColor = urlBarTextColor.opacity(0.35)
            result.append(titlePart)
            return result
        }
    }

    private func pipButton(for tab: PageSession) -> some View {
        Button(action: {
            tab.requestPictureInPicture()
        }) {
            Image(
                systemName: tab.hasPiPActive
                    ? "pip.exit" : "pip.enter"
            )
            .font(NookDesign.Font.secondary)
            .foregroundStyle(urlBarTextColor)
            .animation(
                shouldAnimateColorChange ? NookDesign.Motion.standard : nil,
                value: urlBarTextColor
            )
            .frame(width: 16, height: 16)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ChatButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovered: Bool = false

    var navButtonColor: Color
    
    


    var body: some View {
        Button {
            browserManager.toggleAISidebar(for: windowState)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "message.fill")
                Text("Chat")
            }
            .font(NookDesign.Font.body)
            .foregroundStyle(navButtonColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
            )
            .contentShape(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .onHoverTracking { state in
            isHovered = state
        }

    }
    
    private var backgroundColor: Color {
        let isDark = browserManager.tabs.selectedSession(in: windowState)?.topBarBackgroundColor?.isPerceivedDark == true
        if isHovered {
            return isDark ? .white.opacity(0.15) : .black.opacity(0.1)
        } else {
            return isDark ? .white.opacity(0.1) : .black.opacity(0.05)
        }
    }

}
