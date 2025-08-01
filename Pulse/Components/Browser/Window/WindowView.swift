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
                SidebarView()
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
        }
        .environmentObject(browserManager)
    }

}
