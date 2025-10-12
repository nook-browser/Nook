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
            let contrastingShade = ((try? Garnish.contrastingShade(of: backgroundColor(), direction: .preferLight)) ?? textColor)
            let shadow = ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 3.5, direction: .forceDark)) ?? textColor)
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(contrastingShade)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background{
                    RoundedRectangle(cornerRadius: 14)
                        .fill(((backgroundColor().mix(with: contrastingShade, by: isHovering ? 0.2 : 0))
                            .shadow(.inner(color: ((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 2.5, direction: .forceDark)) ?? textColor), radius: 2, y: -2))
                            .shadow(.inner(color: .white.opacity(0.4), radius: 2, y: 2))
                        )
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke((((try? Garnish.contrastingShade(of: backgroundColor(), targetRatio: 4, direction: .forceDark)) ?? textColor)), lineWidth: 1)
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
                                .foregroundStyle(shadow)
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
        let gradient = SpaceGradient(id: UUID(), name: "Preview", primaryColor: color, nodes: [])
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
