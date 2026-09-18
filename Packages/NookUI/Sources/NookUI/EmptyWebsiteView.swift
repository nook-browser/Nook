//
//  EmptyWebsiteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import NookDesign
import NookWeb

public struct EmptyWebsiteView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) var windowRegistry
    @Environment(\.tabActions) private var actions

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Match the container background so this reads as chrome, not webview content.
                let accent = windowState.isIncognito ? NookDesign.Surface.incognitoAccent : (actions?.accentColor ?? .accentColor)
                let isActive = windowRegistry.activeWindowId == windowState.id

                NookDesign.Surface.containerGradient(accent: accent, isActive: isActive)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
                    .nookElevation(.raised)
                    .animation(NookDesign.Motion.standard, value: isActive)

                VStack(spacing: 16) {
                    Image(systemName: "moon.stars")
                        .font(NookDesign.Font.display)
                        .blendMode(.overlay)

                    Text("Ah, peace.")
                        .font(NookDesign.Font.title)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
