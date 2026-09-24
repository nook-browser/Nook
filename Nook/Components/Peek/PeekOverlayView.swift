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
            }
            .frame(width: frame.width, height: frame.height)
            // The buttons sit in the margin left of the card, level with its top.
            .overlay(alignment: .topLeading) {
                actionButtons
                    .alignmentGuide(.leading) { $0[.trailing] + NookDesign.Spacing.lg }
            }
            .position(
                x: frame.minX + (frame.width / 2),
                y: geometry.size.height / 2
            )
        }
    }

    /// Close, split and new tab as one glass group, like the sidebar's history buttons.
    private var actionButtons: some View {
        VStack(spacing: 0) {
            Button(action: { peek.dismissPeek() }) {
                Image(systemName: "xmark")
            }
            divider
            // Disabled while the window is already split.
            Button(action: { peek.moveToSplitView() }) {
                Image(systemName: "square.split.2x1")
            }
            .disabled(!peek.canEnterSplitView)
            divider
            Button(action: { peek.moveToNewTab() }) {
                Image(systemName: "plus.square.on.square")
            }
        }
        // Dividers take any width offered; the group is the buttons' width.
        .frame(width: NookDesign.Size.glassControl)
        .nookGlassControls(in: Capsule())
    }

    private var divider: some View {
        Divider().padding(.horizontal, NookDesign.Spacing.sm)
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
