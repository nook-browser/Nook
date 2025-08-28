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
            WindowBackgroundView()

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
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            CommandPaletteView()
            DialogView()
            
            // Global insertion line overlay - above everything including web view
            InsertionLineView(dragManager: TabDragManager.shared)
        }
        .environmentObject(browserManager)
    }

}
