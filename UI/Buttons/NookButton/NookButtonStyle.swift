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
            // Main button content
            let contrastingShade = ((try? backgroundColor().contrastingShade()) ?? textColor)
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(contrastingShade)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background{
                    RoundedRectangle(cornerRadius: 14)
                        .fill(((backgroundColor().mix(with: contrastingShade, by: isHovering ? 0.2 : 0))
                            .shadow(.inner(color: ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 2.5)) ?? textColor), radius: 2, y: -2))
                            .shadow(.inner(color: .white.opacity(0.4), radius: 2, y: 2))
                        )
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke((((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 4)) ?? textColor)), lineWidth: 1)
                )
                .overlay(
                    // Top and left borders (highlight)
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(1.0),
                                    .clear,
                                    Color.white.opacity(1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .opacity(0.07)
                        .blendMode(.plusLighter)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .offset(y: configuration.isPressed ? 2 : isHovering ? 0.5 : 0)
                .background{
                    if shadowStyle != .none {
                        ZStack{
                            RoundedRectangle(cornerRadius: 14)
                                .foregroundStyle(((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 3.5)) ?? textColor))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .offset(y: 2)
                    }
                }
        }
        .opacity(isEnabled ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func backgroundColor() -> Color {
        switch variant {
        case .primary:
            return gradientColorManager.primaryColor
        case .secondary:
            return Color.white.mix(with: .black, by: 0.8)
        case .destructive:
            return Color.red
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
    .scaleEffect(3)
    .frame(width: 390, height: 1000)
    .environmentObject(GradientColorManager())
}
