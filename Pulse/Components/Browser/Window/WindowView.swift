//
//  WindowView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowView: View {
    @StateObject private var browserManager = BrowserManager()

    var body: some View {
        ZStack {
            WindowBackgroundView()

            HStack(spacing: 8) {
                SidebarView()
                EmptyWebsiteView()
                    .ignoresSafeArea()
            }

            .padding(8)
        }
        .environmentObject(browserManager)
    }

}
