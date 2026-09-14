//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 11/10/2025.
//

import SwiftUI

/// Square icon button. Hover shows a fill, press shows a stronger fill and a 0.95 scale.
/// Pass size: or radius: only where a call site needs a non-default (media controls 24, URL bar and space title 28, space switcher radius lg).
struct NookIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let size: CGFloat
    let radius: CGFloat

    init(size: CGFloat = NookDesign.Size.iconButton, radius: CGFloat = NookDesign.Radius.md) {
        self.size = size
        self.radius = radius
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            NookDesign.Radius.shape(radius)
                .fill(fill(isPressed: configuration.isPressed))
                .frame(width: size, height: size)
            configuration.label
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
        .opacity(isEnabled ? 1.0 : 0.3)
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(NookDesign.Motion.quick, value: configuration.isPressed)
        .animation(NookDesign.Motion.quick, value: isHovering)
        .onHoverTracking { hovering in isHovering = hovering }
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if isPressed { return NookDesign.Surface.fillPressed }
        if isHovering { return NookDesign.Surface.fill }
        return .clear
    }
}

/// Rectangular, labeled variant of NookIconButtonStyle that allows custom widths
/// Use this for buttons that need to be wider than square (e.g., "New Space" button)
struct RectNavButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background {
                NookDesign.Radius.shape(cornerRadius)
                    .fill(.primary.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))
            }
            .contentShape(.rect)
            .opacity(isEnabled ? 1.0 : 0.3)
            .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
            .animation(NookDesign.Motion.quick, value: isHovering)
            .onHoverTracking { hovering in
                isHovering = hovering
            }
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini: 8
        case .small: 10
        case .regular: 12
        case .large: 16
        case .extraLarge: 20
        @unknown default: 12
        }
    }

    private var cornerRadius: CGFloat {
        NookDesign.Radius.md
    }

    private func backgroundColorOpacity(isPressed: Bool) -> Double {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? 0.2 : 0.1
        } else {
            return 0.0
        }
    }
}

#Preview("Square Buttons") {
    VStack(spacing: 20) {
        // Default
        Button {
        } label: {
            Image(systemName: "arrow.left")
        }
        .buttonStyle(NookIconButtonStyle())
        .foregroundStyle(Color.primary)

        // With foregroundStyle
        Button {
        } label: {
            Image(systemName: "heart.fill")
        }
        .buttonStyle(NookIconButtonStyle())
        .foregroundStyle(.red)

        // Different sizes
        HStack {
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NookIconButtonStyle(size: 24))
                .foregroundStyle(Color.pink)

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NookIconButtonStyle(size: 28))
                .foregroundStyle(Color.purple)

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NookIconButtonStyle())
                .foregroundStyle(Color.yellow)

            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NookIconButtonStyle(size: 40))
                .foregroundStyle(Color.orange)
        }

        // Disabled
        Button {
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(NookIconButtonStyle())
        .foregroundStyle(Color.primary)
        .disabled(true)
    }
    .padding()
}

#Preview("Rectangular Buttons") {
    VStack(spacing: 20) {
        // Icon with text
        Button {
        } label: {
            Label("New Space", systemImage: "plus")
        }
        .buttonStyle(RectNavButtonStyle())
        .foregroundStyle(Color.primary)

        // Icon only (still rectangular due to padding)
        Button {
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(RectNavButtonStyle())
        .foregroundStyle(Color.primary)

        // Different sizes
        VStack(spacing: 12) {
            Button { } label: { Label("Mini", systemImage: "star") }
                .buttonStyle(RectNavButtonStyle())
                .foregroundStyle(Color.pink)
                .controlSize(.mini)

            Button { } label: { Label("Small", systemImage: "star") }
                .buttonStyle(RectNavButtonStyle())
                .foregroundStyle(Color.purple)
                .controlSize(.small)

            Button { } label: { Label("Regular", systemImage: "star") }
                .buttonStyle(RectNavButtonStyle())
                .foregroundStyle(Color.yellow)

            Button { } label: { Label("Large", systemImage: "star") }
                .buttonStyle(RectNavButtonStyle())
                .foregroundStyle(Color.orange)
                .controlSize(.large)
        }

        // Disabled
        Button {
        } label: {
            Label("Disabled", systemImage: "xmark")
        }
        .buttonStyle(RectNavButtonStyle())
        .foregroundStyle(Color.primary)
        .disabled(true)
    }
    .padding()
}
