// Licensed under GPL-3.0. See LICENSE.
//
//  PeekOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb
import AppKit
import NookUI

struct PeekOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.nookSettings) var nookSettings

    private var peek: PeekManager { browserManager.peekManager }

    /// Peek belongs to the window that opened it; the others show nothing.
    private var page: PageSession? {
        peek.windowId == windowState.id ? peek.page : nil
    }

    private var currentSpaceColor: Color {
        windowState.spaceID.flatMap { tabs.space($0)?.accentColor } ?? Color.accentColor
    }

    var body: some View {
        ZStack {
            if let page {
                backgroundOverlay
                    .transition(.opacity)
                peekContent(page: page)
                    .transition(.scale(scale: 0.001).combined(with: .opacity))
                    .zIndex(1000)
            }
        }
        .zIndex(9999) // Put it at the very top
        .animation(NookDesign.Motion.spring, value: page?.itemID)
    }

    private var backgroundOverlay: some View {
        Color.black.opacity(0.3)
            .contentShape(Rectangle()) // Ensure proper hit testing
            .onTapGesture { peek.dismissPeek() }
    }

    private func peekContent(page: PageSession) -> some View {
        GeometryReader { geometry in
            let (frame, cornerRadius) = calculateLayout(geometry: geometry)

            ZStack {
                // The card's surface and shadow sit behind the page, never on it: see DetachedPageHost.
                NookDesign.Radius.shape(cornerRadius)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .nookElevation(.floating)

                DetachedPageHost(page: page, cornerRadius: cornerRadius)
                    .id(page.itemID)

                if let webView = page.webView {
                    PageLoadBar(webView: webView, tint: currentSpaceColor)
                        .padding(.horizontal, cornerRadius)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .id(page.itemID)
                }

                // Action buttons in the margin left of the card, within the scaled area
                actionButtons
                    .position(
                        x: -30,
                        y: 80
                    )
            }
            .frame(width: frame.width, height: frame.height)
            .position(
                x: frame.minX + (frame.width / 2),
                y: geometry.size.height / 2
            )
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Close button
            actionButton(
                icon: "xmark",
                action: { peek.dismissPeek() },
                color: currentSpaceColor
            )

            // Split view button (disabled if already in split view)
            actionButton(
                icon: "square.split.2x1",
                action: { peek.moveToSplitView() },
                color: currentSpaceColor,
                disabled: !peek.canEnterSplitView
            )

            // New tab button
            actionButton(
                icon: "plus.square.on.square",
                action: { peek.moveToNewTab() },
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
                    .font(NookDesign.Font.label)
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
            .onHoverTracking { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .animation(NookDesign.Motion.quick, value: isHovering)
            .animation(NookDesign.Motion.quick, value: disabled)
        }
    }

    // MARK: - Layout Calculation

    private func calculateLayout(geometry: GeometryProxy) -> (frame: CGRect, cornerRadius: CGFloat) {
        let windowSize = geometry.size
        let sidebarPosition = nookSettings.sidebarPosition

        // Compute the visible web content area by excluding the sidebar width
        let sidebarWidth: CGFloat = windowState.isSidebarVisible ? windowState.sidebarWidth : 0
        let webAreaWidth = max(0, windowSize.width - sidebarWidth)

        // 80% of the web area wide and 90% of the window tall, so the page behind stays in view.
        let webViewHeight = windowSize.height * 0.9
        let cornerRadius: CGFloat = NookDesign.Radius.xl

        // Center within the web area (excluding sidebar)
        let peekWidth = webAreaWidth * 0.8
        let peekXWithinWebArea = (webAreaWidth - peekWidth) / 2

        // Calculate peek X position based on sidebar position
        let peekX: CGFloat
        if sidebarPosition == .left {
            // Sidebar on left: peek window starts after sidebar
            peekX = sidebarWidth + peekXWithinWebArea
        } else {
            // Sidebar on right: peek window starts from left edge
            peekX = peekXWithinWebArea
        }


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
