//
//  PeekOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import AppKit

struct PeekOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.colorScheme) var colorScheme
        @State private var webView: PeekWebView?
    @State private var scale: CGFloat = 0.001
    @State private var opacity: Double = 0.0
    @State private var backgroundOpacity: Double = 0.0
    @State private var activateObserver: NSObjectProtocol?
    @State private var deactivateObserver: NSObjectProtocol?
    @State private var webContentOpacity: Double = 0.0

    private var isActive: Bool {
        browserManager.peekManager.isActive
    }

    private var session: PeekSession? {
        browserManager.peekManager.currentSession
    }

    private var currentSpaceColor: Color {
        if let spaceId = windowState.currentSpaceId,
           let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) {
            return space.gradient.primaryColor
        }
        return Color.accentColor // fallback
    }

    var body: some View {
        ZStack {
            // Always present but visibility controlled by opacity
            backgroundOverlay
                .opacity(backgroundOpacity)

            // Peek overlay container - always present but visibility controlled
            if let session = session {
                peekContent(session: session)
                    .scaleEffect(scale, anchor: .center)
                    .opacity(opacity)
                    .zIndex(1000)
            } else {
                // Loading state while session is being set up
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .frame(width: 600, height: 400)
                    .scaleEffect(scale, anchor: .center)
                    .opacity(opacity)
                    .zIndex(1000)
            }
        }
        .zIndex(9999) // Put it at the very top
        .allowsHitTesting(true) // Always allow hit testing
        .onAppear {
            // Sync initial state when view appears
            if browserManager.peekManager.isActive {
                presentPeek()
            }

            // Fallback: observe explicit activation notifications to bypass blocked @Published delivery
            activateObserver = NotificationCenter.default.addObserver(forName: .peekDidActivate, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    presentPeek()
                }
            }
            deactivateObserver = NotificationCenter.default.addObserver(forName: .peekDidDeactivate, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    dismissPeek()
                }
            }
        }
        .onDisappear {
            if let token = activateObserver {
                NotificationCenter.default.removeObserver(token)
                activateObserver = nil
            }
            if let token = deactivateObserver {
                NotificationCenter.default.removeObserver(token)
                deactivateObserver = nil
            }
        }
        .onChange(of: browserManager.peekManager.isActive) { _, isActive in
            if isActive {
                presentPeek()
            } else {
                dismissPeek()
            }
        }
        .onChange(of: browserManager.peekManager.currentSession?.id) { _, _ in
            // Session changed - no action needed
        }
    }

    // MARK: - State Management

    @MainActor
    private func presentPeek() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scale = 1.0
            opacity = 1.0
            backgroundOpacity = 1.0
        }
    }

    @MainActor
    private func dismissPeek() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scale = 0.001
            opacity = 0.0
            backgroundOpacity = 0.0
        }

        // Cleanup after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webView = nil
            webContentOpacity = 0.0
        }
    }

    @ViewBuilder
    private var backgroundOverlay: some View {
        Color.black.opacity(0.3)
            .contentShape(Rectangle()) // Ensure proper hit testing
            .allowsHitTesting(true) // Always block background interactions when Peek is active
            .onTapGesture {
                browserManager.peekManager.dismissPeek()
            }
    }

    @ViewBuilder
    private func peekContent(session: PeekSession) -> some View {
        GeometryReader { geometry in
            let (frame, cornerRadius) = calculateLayout(geometry: geometry)

            ZStack {
                // Themed placeholder behind web content
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(colorScheme == .dark ? Color.black : Color.white)

                // Peek webview with shadow
                webViewContainer(session: session)
                    .opacity(webContentOpacity)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(
                        color: Color.black.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )
                    .overlay(
                        // Invisible overlay that blocks all background webview interactions within Peek bounds
                        Color.clear
                            .contentShape(Rectangle())
                            .allowsHitTesting(true)
                            .onHover { hovering in
                                if hovering { NSCursor.arrow.set() }
                            }
                    )

                // Action buttons positioned outside the main content but within the scaled area
                actionButtons(session: session)
                    .position(
                        x: frame.width + 30,
                        y: 80
                    )
            }
            .frame(width: frame.width, height: frame.height) // Extend frame to include buttons
            .position(
                x: frame.minX + (frame.width / 2),
                y: geometry.size.height / 2
            )
        }
    }

    @ViewBuilder
    private func webViewContainer(session: PeekSession) -> some View {
        Group {
            if webView != nil {
                webView
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.15)) {
                            webContentOpacity = 1.0
                        }
                    }
                    .onPreferenceChange(PeekWebViewSizePreferenceKey.self) { size in
                        // Handle webview size preferences if needed
                    }
            } else {
                // Themed placeholder that matches system theme; this scales up during presentation
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
            }
        }
        .onAppear {
            if webView == nil {
                // Use the pre-created WebView from PeekManager
                if let preCreatedWebView = browserManager.peekManager.webView {
                    webView = preCreatedWebView
                    webContentOpacity = 0.0
                } else {
                    // Fallback: create WebView if not available
                    let peekWebView = browserManager.peekManager.createWebView()
                    webView = peekWebView
                    webContentOpacity = 0.0
                    browserManager.peekManager.updateWebView(peekWebView)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(session: PeekSession) -> some View {
        VStack(spacing: 12) {
            // Close button
            actionButton(
                icon: "xmark",
                action: { browserManager.peekManager.dismissPeek() },
                color: currentSpaceColor
            )

            // Split view button (disabled if already in split view)
            actionButton(
                icon: "square.split.2x1",
                action: { browserManager.peekManager.moveToSplitView() },
                color: currentSpaceColor,
                disabled: !browserManager.peekManager.canEnterSplitView
            )

            // New tab button
            actionButton(
                icon: "plus.square.on.square",
                action: { browserManager.peekManager.moveToNewTab() },
                color: currentSpaceColor
            )
        }
    }

    @ViewBuilder
    private func actionButton(
        icon: String,
        action: @escaping () -> Void,
        color: Color,
        disabled: Bool = false
    ) -> some View {
        HoverButton(icon: icon, action: action, color: color, disabled: disabled)
    }

    // MARK: - Hover Button
    private struct HoverButton: View {
        @Environment(\.colorScheme) var colorScheme
        let icon: String
        let action: () -> Void
        let color: Color
        let disabled: Bool
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(disabled ? Color.gray : color)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(nsColor: colorScheme == .dark ? NSColor.white : NSColor.black))
                            .opacity(disabled ? 0.5 : (isHovering ? 0.85 : 1.0))
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(disabled ? 0.3 : (isHovering ? 0.8 : 0.6)), lineWidth: 1)
                    )
            }
            .disabled(disabled)
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(disabled ? 0.9 : 1.0)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .animation(.easeInOut(duration: 0.1), value: disabled)
        }
    }

    // MARK: - Layout Calculation

    private func calculateLayout(geometry: GeometryProxy) -> (frame: CGRect, cornerRadius: CGFloat) {
        let windowSize = geometry.size
        let isSplit = browserManager.splitManager.isSplit(for: windowState.id)
        let sidebarPosition = browserManager.settingsManager.sidebarPosition

        // Compute the visible web content area by excluding the sidebar width
        let sidebarWidth: CGFloat = windowState.isSidebarVisible ? windowState.sidebarWidth : 0
        let webAreaWidth = max(0, windowSize.width - sidebarWidth)

        let webViewHeight = windowSize.height - 10 // Full height PLUS 10pts
        let cornerRadius: CGFloat = 16

        // Center within the web area (excluding sidebar) with 60pt margins
        let horizontalMargin: CGFloat = 60
        let peekWidth = max(0, webAreaWidth - (horizontalMargin * 2))
        let peekXWithinWebArea = (webAreaWidth - peekWidth) / 2 // equals horizontalMargin

        // Calculate peek X position based on sidebar position
        let peekX: CGFloat
        if sidebarPosition == .left {
            // Sidebar on left: peek window starts after sidebar
            peekX = sidebarWidth + peekXWithinWebArea
        } else {
            // Sidebar on right: peek window starts from left edge
            peekX = peekXWithinWebArea
        }

        // If split view, behavior remains the same as single; centering is relative to web area
        _ = isSplit // currently unused but kept for future adjustments

        return (
            frame: CGRect(
                x: peekX,
                y: 0,
                width: peekWidth,
                height: webViewHeight
            ),
            cornerRadius: cornerRadius
        )
    }
}

// Preference key for webview size tracking
struct PeekWebViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}
