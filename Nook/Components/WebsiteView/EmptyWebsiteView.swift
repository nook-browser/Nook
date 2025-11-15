//
//  EmptyWebsiteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct EmptyWebsiteView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Match the exact background and styling of the real webview
                Color(nsColor: .windowBackgroundColor).opacity(0.2)
                    .clipShape(RoundedRectangle(cornerRadius: {
                        if #available(macOS 26.0, *) {
                            return 12
                        } else {
                            return 6
                        }
                    }(), style: .continuous))
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)

                VStack(spacing: 16) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 32, weight: .medium))
                        .blendMode(.overlay)

                    Text("Ah, peace.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
