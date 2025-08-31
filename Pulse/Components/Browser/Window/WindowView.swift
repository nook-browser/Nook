//
//  WindowView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack {
            // Gradient background for the current space (bottom-most layer)
            SpaceGradientBackgroundView()

            // Attach background context menu to the window background layer
            WindowBackgroundView()
                .contextMenu {
                    Button("Customize Space Gradient...") {
                        browserManager.showGradientEditor()
                    }
                    .disabled(browserManager.tabManager.currentSpace == nil)
                }

            HStack(spacing: 0) {
                DragEnabledSidebarView()
                if browserManager.isSidebarVisible {
                    SidebarResizeView()
                }
                VStack(spacing: 0) {
                    WebsiteLoadingIndicator()

                    WebsiteView()

                }
            }
            // Keep primary content interactive; background menu only triggers on empty areas
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            // Mini command palette anchored exactly to URL bar's top-left
            MiniCommandPaletteOverlay()

            CommandPaletteView()
            DialogView()
            
            // Working insertion line overlay
            InsertionLineView(dragManager: TabDragManager.shared)
        }
        // Named coordinate space for geometry preferences
        .coordinateSpace(name: "WindowSpace")
        // Keep BrowserManager aware of URL bar frame in window space
        .onPreferenceChange(URLBarFramePreferenceKey.self) { frame in
            browserManager.urlBarFrame = frame
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.gradientColorManager)
    }

}

// MARK: - Mini Command Palette Overlay (above sidebar and webview)
private struct MiniCommandPaletteOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            if browserManager.isMiniCommandPaletteVisible && !browserManager.isCommandPaletteVisible {
                // Click-away hit target
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { browserManager.isMiniCommandPaletteVisible = false }

                // Use reported URL bar frame when reliable; otherwise compute manual fallback
                let barFrame = browserManager.urlBarFrame
                let hasFrame = barFrame.width > 1 && barFrame.height > 1
                let fallbackX: CGFloat = 8 // Window horizontal content padding
                let fallbackY: CGFloat = 8 /* sidebar top padding */ + 30 /* nav bar */ + 8 /* vstack spacing */
                let anchorX = hasFrame ? barFrame.minX : fallbackX
                let anchorY = hasFrame ? barFrame.minY : fallbackY
                // let width = hasFrame ? barFrame.width : browserManager.sidebarWidth

                MiniCommandPaletteView(
                    forcedWidth: 400,
                    forcedCornerRadius: 12
                )
                .offset(x: anchorX, y: anchorY)
                    .zIndex(1)
            }
        }
        .allowsHitTesting(browserManager.isMiniCommandPaletteVisible)
        .zIndex(999) // ensure above web content
    }
}
