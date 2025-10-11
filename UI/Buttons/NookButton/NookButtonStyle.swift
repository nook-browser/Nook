//
//  NookButtonStyle.swift
//  Nook
//
//  Created by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct NookButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @EnvironmentObject var gradientColorManager: GradientColorManager

    let variant: Variant
    let shadowStyle: ShadowStyle

    @State private var isHovering: Bool = false

    enum Variant {
        case primary
        case secondary
        case destructive
    }

    enum ShadowStyle {
        case none
        case subtle
        case prominent
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Shadow outline (bottom layer)
            if shadowStyle != .none {
                configuration.label
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clear)
                    .padding(.vertical, shadowStyle == .prominent ? 11 : 12)
                    .padding(.horizontal, 12)
                    .background(shadowBackgroundColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(shadowStrokeColor, lineWidth: 1)
                    )
                    .offset(shadowOffset)
            }

            // Main button content
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(backgroundColor(isPressed: configuration.isPressed))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .overlay(
                    // Top and left borders (highlight)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .offset(y: configuration.isPressed ? 2 : 0)
        }
        .opacity(isEnabled ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isHovering ? gradientColorManager.primaryColor.opacity(0.8) : gradientColorManager.primaryColor
        case .secondary:
            return isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)
        case .destructive:
            return isHovering ? Color.red.opacity(0.8) : Color.red
        }
    }

    private var textColor: Color {
        switch variant {
        case .primary:
            return Color.white
        case .secondary:
            return Color.primary
        case .destructive:
            return Color.white
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary, .destructive:
            return Color.clear
        case .secondary:
            return isHovering ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .primary, .destructive:
            return 0
        case .secondary:
            return 1
        }
    }

    private var shadowBackgroundColor: Color {
        switch shadowStyle {
        case .none:
            return Color.clear
        case .subtle:
            return Color.clear
        case .prominent:
            return Color.gray
        }
    }

    private var shadowStrokeColor: Color {
        switch shadowStyle {
        case .none:
            return Color.clear
        case .subtle:
            return Color.black.opacity(0.3)
        case .prominent:
            return Color.white.opacity(1)
        }
    }

    private var shadowOffset: CGSize {
        switch shadowStyle {
        case .none:
            return CGSize.zero
        case .subtle:
            return CGSize(width: 0, height: 2)
        case .prominent:
            return CGSize(width: 0, height: 6)
        }
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == NookButtonStyle {
    static var nookPrimary: NookButtonStyle {
        NookButtonStyle(variant: .primary, shadowStyle: .subtle)
    }

    static var nookSecondary: NookButtonStyle {
        NookButtonStyle(variant: .secondary, shadowStyle: .subtle)
    }

    static var nookDestructive: NookButtonStyle {
        NookButtonStyle(variant: .destructive, shadowStyle: .subtle)
    }

    static var nookProminent: NookButtonStyle {
        NookButtonStyle(variant: .primary, shadowStyle: .prominent)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Primary
        Button("Save", systemImage: "checkmark") {
            print("Save")
        }
        .buttonStyle(.nookPrimary)

        // Secondary
        Button("Cancel") {
            print("Cancel")
        }
        .buttonStyle(.nookSecondary)

        // Destructive
        Button("Delete", systemImage: "trash") {
            print("Delete")
        }
        .buttonStyle(.nookDestructive)

        // Prominent (create button)
        Button("Create Space", systemImage: "plus") {
            print("Create")
        }
        .buttonStyle(.nookProminent)

        // Disabled
        Button("Disabled") {
            print("Disabled")
        }
        .buttonStyle(.nookPrimary)
        .disabled(true)
    }
    .padding()
    .environmentObject(GradientColorManager())
}
