//
//  BoostFonts.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostFonts: View {
    @Binding var config: BoostConfig
    var onConfigChange: (BoostConfig) -> Void
    
    var body: some View {
        VStack {
            HStack(spacing: 0) {
                FontButton(font: .system(size: 11, weight: .medium)) {
                    config.fontFamily = nil
                    onConfigChange(config)
                }
                FontButton(font: .custom("Helvetica Neue", size: 11)) {
                    config.fontFamily = "Helvetica Neue"
                    onConfigChange(config)
                }
                FontButton(font: .custom("Avenir", size: 11)) {
                    config.fontFamily = "Avenir"
                    onConfigChange(config)
                }
                FontButton(font: .custom("Futura", size: 11)) {
                    config.fontFamily = "Futura"
                    onConfigChange(config)
                }

                FontButton(font: .custom("DIN Alternate", size: 11)) {
                    config.fontFamily = "DIN Alternate"
                    onConfigChange(config)
                }
            }
            HStack(spacing: 0) {
                FontButton(font: .custom("Arial Rounded MT Bold", size: 11)) {
                    config.fontFamily = "Arial Rounded MT Bold"
                    onConfigChange(config)
                }

                FontButton(font: .custom("PT Mono", size: 11)) {
                    config.fontFamily = "PT Mono"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Courier", size: 11)) {
                    config.fontFamily = "Courier"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Times New Roman", size: 11)) {
                    config.fontFamily = "Times New Roman"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Charter", size: 11)) {
                    config.fontFamily = "Charter"
                    onConfigChange(config)
                }
            }
            HStack(spacing: 0) {
                FontButton(font: .custom("Baskerville", size: 11)) {
                    config.fontFamily = "Baskerville"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Hoefler Text", size: 11)) {
                    config.fontFamily = "Hoefler Text"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Palatino", size: 11)) {
                    config.fontFamily = "Palatino"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Chalkboard", size: 11)) {
                    config.fontFamily = "Chalkboard"
                    onConfigChange(config)
                }

                FontButton(font: .custom("SignPainter", size: 11)) {
                    config.fontFamily = "SignPainter"
                    onConfigChange(config)
                }
            }
            HStack(spacing: 0) {
                FontButton(font: .custom("Snell Roundhand", size: 11)) {
                    config.fontFamily = "Snell Roundhand"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Papyrus", size: 11)) {
                    config.fontFamily = "Papyrus"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Palatino", size: 11)) {
                    config.fontFamily = "Palatino"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Apple Chancery", size: 11)) {
                    config.fontFamily = "Apple Chancery"
                    onConfigChange(config)
                }

                FontButton(font: .custom("Wingdings", size: 11)) {
                    config.fontFamily = "Wingdings"
                    onConfigChange(config)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(width: 147)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 0)
    }
}

#Preview {
    @Previewable @State var config = BoostConfig()
    BoostFonts(config: $config) { _ in }
        .frame(width: 300, height: 300)
        .background(.white)
}

struct FontButton: View {
    @State private var isHovered: Bool = false
    var font: Font
    var onClick: () -> Void

    var body: some View {
        Button {
            onClick()
        } label: {
            Text("Aa")
                .font(font)
                .foregroundStyle(.black.opacity(0.4))
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.linear(duration: 0.1), value: isHovered)
                .frame(width: 26, height: 26)
                .background(.black.opacity(isHovered ? 0.05 : 0.0))
                .clipShape(Circle())
        }
        .onHover { state in
            isHovered = state
        }
        .buttonStyle(.plain)
    }
}
