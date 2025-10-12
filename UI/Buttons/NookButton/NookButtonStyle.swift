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

    enum Variant {
        case secondary  // Regular button
        case primary    // Prominent button
    }

    enum ShadowStyle {
        case none
        case subtle
        case prominent
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Main button content
            let contrastingShade = ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 3, direction: .preferLight, blendStyle: .strong)) ?? textColor)
            let background = (backgroundColor().mix(with: contrastingShade, by: isHovering ? 0.2 : 0))
            let shadow = ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 2)) ?? textColor)
            let highlight =  ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 2, direction: .preferLight)) ?? textColor)
            
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(contrastingShade)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background{
                    RoundedRectangle(cornerRadius: 14)
                        .fill(background)
                }
              
                .overlay(
                    Group{
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    highlight,
                                    .clear,
                                    highlight
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .opacity(!isEnabled ? 0 : configuration.isPressed ? 0.07 : isHovering ? 0.15 : 0.1)
                        .blendMode(.plusLighter)
                }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .offset(y: configuration.isPressed ? 2 : isHovering ? 0.5 : 0)
                .background{
                    if shadowStyle != .none && isEnabled {
                        ZStack{
                            RoundedRectangle(cornerRadius: 14)
                                .foregroundStyle(shadow)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .offset(y: 2)
                    }
                }
        }
        .compositingGroup()
        .opacity(isEnabled ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func backgroundColor() -> Color {
        if role == .destructive {
            return Color.red
        }

        switch variant {
        case .secondary:
            return Color.white.mix(with: .black, by: 0.8)
        case .primary:
            return gradientColorManager.primaryColor
        }
    }

    private var textColor: Color {
        switch variant {
        case .secondary:
            return Color.primary
        case .primary:
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
