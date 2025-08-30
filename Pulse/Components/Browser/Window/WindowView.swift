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

            CommandPaletteView()
            DialogView()
            
            // Working insertion line overlay
            InsertionLineView(dragManager: TabDragManager.shared)
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.gradientColorManager)
    }

}
