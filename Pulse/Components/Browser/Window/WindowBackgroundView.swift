//
//  WindowBackgroundView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowBackgroundView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                if browserManager.settingsManager.isLiquidGlassEnabled {
                    Rectangle()
                        .fill(.clear)
                        .background(.thinMaterial)  // Use thinMaterial for liquid glass effect for better compatability
                        .blur(radius: 40)
                } else {
                    BlurEffectView(
                        material: browserManager.settingsManager
                            .currentMaterial,
                        state: .active
                    )
                    .overlay(
                        Color.black.opacity(0.25)
                            .blendMode(.darken)
                    )
                }
            } else {
                // Pre-macOS 15 fallback
                BlurEffectView(
                    material: browserManager.settingsManager.currentMaterial,
                    state: .active
                )
                .overlay(
                    Color.black.opacity(0.25)
                        .blendMode(.darken)
                )
            }
        }
        .backgroundDraggable()
    }
}

