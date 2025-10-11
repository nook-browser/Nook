//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct NavButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @State private var isHovering: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor(isPressed: configuration.isPressed))
                .frame(width: 32, height: 32)

            configuration.label
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
        }
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? AppColors.iconHoverLight : AppColors.iconHoverDark
        } else {
            return Color.clear
        }
    }

    private var iconColor: Color {
        if isEnabled {
            return colorScheme == .dark ? AppColors.iconActiveLight : AppColors.iconActiveDark
        } else {
            return colorScheme == .dark ? AppColors.iconDisabledLight : AppColors.iconDisabledDark
        }
    }
}
