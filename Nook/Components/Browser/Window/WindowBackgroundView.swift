//
//  WindowBackgroundView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct WindowBackgroundView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                if browserManager.settingsManager.isLiquidGlassEnabled {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: .rect(cornerRadius: 0))
                } else {
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(
                            Color.black.opacity(0.15)
                        )
                }
            } else {
                if browserManager.settingsManager.isLiquidGlassEnabled {
                    Rectangle()
                        .fill(.thinMaterial)
                } else {
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(
                            Color.black.opacity(0.15)
                        )
                }
            }
        }
        .backgroundDraggable()
    }
}

