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
            if(browserManager.settingsManager.isLiquidGlassEnabled) {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .fill(Color.clear)
                        .blur(radius: 40)
                        .glassEffect(in: .rect(cornerRadius: 0))
                } else {
                    BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active)
                        .overlay {
                            Color(hex: "#00000041")
                                .blendMode(.darken)
                        }
                }
            } else {
                BlurEffectView(material: browserManager.settingsManager.currentMaterial, state: .active)
                    .overlay {
                        Color(hex: "#00000041")
                            .blendMode(.darken)
                    }
            }
            
        }
        .backgroundDraggable()
    }
}
