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
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor(isPressed: configuration.isPressed))
                .frame(width: size, height: size)

            configuration.label
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
        }
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var size: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }

    private var iconSize: CGFloat {
        switch controlSize {
        case .mini: 12
        case .small: 14
        case .regular: 16
        case .large: 20
        case .extraLarge: 24
        @unknown default: 16
        }
    }

    private var cornerRadius: CGFloat {
        6
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? AppColors.iconHoverLight : AppColors.iconHoverDark
        } else {
            return Color.clear
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Default
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "arrow.left")
        }
        .buttonStyle(NavButtonStyle())

        // With foregroundStyle
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "heart.fill")
        }
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(.red)

        // Different sizes
        HStack {
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .controlSize(.mini)

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .controlSize(.small)

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .controlSize(.large)
        }

        // Disabled
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(NavButtonStyle())
        .disabled(true)
    }
    .padding()
}
