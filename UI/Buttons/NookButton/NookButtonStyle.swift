//
//  NookButtonStyle.swift
//  Nook
//
//  Created by Aether Aurelia on 11/10/2025.
//

import SwiftUI
import Garnish

struct NookButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @EnvironmentObject var gradientColorManager: GradientColorManager

    let variant: Variant
    let shadowStyle: ShadowStyle
    let role: ButtonRole?

    @State private var isHovering: Bool = false

    // MARK: - Constants

    private let cornerRadius: CGFloat = 14
    private let verticalPadding: CGFloat = 12
    private let horizontalPadding: CGFloat = 12

    // Hover and press effects
    private let hoverMixAmount: CGFloat = 0.2
    private let pressedOffset: CGFloat = 2
    private let hoverOffset: CGFloat = 0.5

    // Highlight opacity values
    private let highlightOpacityDefault: CGFloat = 0.1
    private let highlightOpacityHover: CGFloat = 0.15
    private let highlightOpacityPressed: CGFloat = 0.07

    // Stroke widths
    private let highlightStrokeWidth: CGFloat = 2

    // Disabled state
    private let disabledOpacity: CGFloat = 0.3

    enum Variant {
        case secondary  // Regular button
        case primary    // Prominent button
    }

    enum ShadowStyle {
        case none
        case subtle
        case prominent
    }

    // MARK: - Body

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Calculate colors using Garnish for contrast
            let baseColor = backgroundColor()
            let contrastingShade = contrastingTextColor(for: baseColor)
            let backgroundWithHover = baseColor.mix(with: contrastingShade, by: isHovering ? hoverMixAmount : 0)
            let shadowColor = shadowColorForBackground(baseColor)
            let highlightColor = highlightColorForBackground(baseColor)

            // Main button label with background
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(contrastingShade)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .background(backgroundWithHover)
                .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .compositingGroup()
        .opacity(isEnabled ? 1.0 : disabledOpacity)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Helper Methods

    /// Returns the contrasting text color for the given background
    private func contrastingTextColor(for background: Color) -> Color {
        (try? Garnish.contrastingShade(
            of: background,
            targetRatio: 2,
            direction: .preferLight,
            blendStyle: .strong
        )) ?? textColor
    }

    /// Returns the shadow color for the given background
    private func shadowColorForBackground(_ background: Color) -> Color {
        (try? Garnish.contrastingShade(
            of: background,
            targetRatio: 1.5,
            direction: .forceDark
        )) ?? textColor
    }

    /// Returns the highlight color for the given background
    private func highlightColorForBackground(_ background: Color) -> Color {
        (try? Garnish.contrastingShade(
            of: background,
            targetRatio: 2,
            direction: .preferLight
        )) ?? textColor
    }

    /// Returns the highlight opacity based on button state
    private func highlightOpacity(isPressed: Bool) -> CGFloat {
        if !isEnabled {
            return 0
        } else if isPressed {
            return highlightOpacityPressed
        } else if isHovering {
            return highlightOpacityHover
        } else {
            return highlightOpacityDefault
        }
    }

    /// Returns the vertical offset based on button state
    private func verticalOffset(isPressed: Bool) -> CGFloat {
        if isPressed {
            return pressedOffset
        } else if isHovering {
            return hoverOffset
        } else {
            return 0
        }
    }

    /// Returns the base background color based on variant and role
    private func backgroundColor() -> Color {
        // Destructive role overrides variant colors
        if role == .destructive {
            return Color.red
        }

        switch variant {
        case .secondary:
            // Neutral gray for secondary buttons
            return Color.white.mix(with: .black, by: colorScheme == .dark ? 0.8 : 0.06).opacity(0.7)
        case .primary:
            // Use accent color from gradient manager
            return gradientColorManager.primaryColor
        }
    }

    /// Fallback text color when Garnish contrast calculation fails
    private var textColor: Color {
        switch variant {
        case .secondary:
            return Color.primary
        case .primary:
            return Color.white
        }
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == NookButtonStyle {
    static var nookButton: NookButtonStyle {
        NookButtonStyle(variant: .secondary, shadowStyle: .subtle, role: nil)
    }

    static func nookButton(role: ButtonRole?) -> NookButtonStyle {
        NookButtonStyle(variant: .secondary, shadowStyle: .subtle, role: role)
    }

    static var nookButtonProminent: NookButtonStyle {
        NookButtonStyle(variant: .primary, shadowStyle: .prominent, role: nil)
    }

    static func nookButtonProminent(role: ButtonRole?) -> NookButtonStyle {
        NookButtonStyle(variant: .primary, shadowStyle: .prominent, role: role)
    }
}

#Preview {
    let colors = [Color.blue, Color.purple, Color.green, Color.orange, Color.pink, Color.red]

    return ScrollView {
        VStack(spacing: 40) {
            ForEach(colors, id: \.self) { color in
                ButtonPreviewSection(color: color)
            }
        }
        .padding()
    }
    .frame(width: 390, height: 1000)
}

private struct ButtonPreviewSection: View {
    let color: Color

    var body: some View {
        VStack(spacing: 20) {
            Text(colorName)
                .font(.headline)
                .foregroundStyle(.secondary)

            buttonStack
        }
        .padding()
        .background(.background.opacity(0.5))
        .cornerRadius(12)
        .environmentObject(makeColorManager())
    }

    private var colorName: String {
        color.description.capitalized
    }

    private func makeColorManager() -> GradientColorManager {
        let manager = GradientColorManager()
#if canImport(AppKit)
        let hex = color.toHexString(includeAlpha: true) ?? "#FFFFFFFF"
#else
        let hex = "#FFFFFFFF"
#endif
        let n1 = GradientNode(colorHex: hex, location: 0.0)
        let n2 = GradientNode(colorHex: hex, location: 1.0)
        let gradient = SpaceGradient(angle: 45.0, nodes: [n1, n2], grain: 0.05, opacity: 1.0)
        manager.setImmediate(gradient)
        return manager
    }

    private var buttonStack: some View {
        VStack(spacing: 20) {
            Button("Create Space", systemImage: "plus") {
                print("Create")
            }
            .buttonStyle(.nookButtonProminent)
            .background(.red)

            Button("Cancel") {
                print("Cancel")
            }
            .buttonStyle(.nookButton)

            Button("Delete", systemImage: "trash") {
                print("Delete")
            }
            .buttonStyle(.nookButton(role: .destructive))

            Button("Erase Everything", systemImage: "flame") {
                print("Erase")
            }
            .buttonStyle(.nookButtonProminent(role: .destructive))

            Button("Disabled") {
                print("Disabled")
            }
            .buttonStyle(.nookButtonProminent)
            .disabled(true)
        }
    }
}
#if DEBUG
#Preview("Dialog Example") {
    DialogManagerPreviewSurface()
        .environment(GradientColorManager())
}
#endif
