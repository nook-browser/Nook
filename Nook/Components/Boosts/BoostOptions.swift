//
//  BoostOptions.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostOptions: View {
    @Binding var brightness: Int
    @Binding var contrast: Int
    @Binding var tintStrength: Int

    @State private var showAdvancedOptions: Bool = false
    @State private var isLightMode: Bool = true

    var onValueChange: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                OptionButton(icon: "lightbulb", isActive: isLightMode) {
                    // Toggle between light/dark mode presets
                    isLightMode.toggle()
                    if isLightMode {
                        brightness = 100
                        contrast = 90
                    } else {
                        brightness = 110
                        contrast = 100
                    }
                    onValueChange?()
                }

                OptionButton(icon: "slider.horizontal.3", isActive: showAdvancedOptions) {
                    showAdvancedOptions.toggle()
                }
                .popover(isPresented: $showAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Advanced Options")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)

                        // Brightness
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "sun.max")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                Text("Brightness")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(brightness)%")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(brightness) },
                                    set: {
                                        brightness = Int($0)
                                        onValueChange?()
                                    }
                                ), in: 50...150, step: 1
                            )
                            .tint(.primary.opacity(0.3))
                        }

                        // Contrast
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                Text("Contrast")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(contrast)%")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(contrast) },
                                    set: {
                                        contrast = Int($0)
                                        onValueChange?()
                                    }
                                ), in: 50...150, step: 1
                            )
                            .tint(.primary.opacity(0.3))
                        }

                        // Tint Strength
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "paintpalette")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                Text("Tint Strength")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(tintStrength)%")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(tintStrength) },
                                    set: {
                                        tintStrength = Int($0)
                                        onValueChange?()
                                    }
                                ), in: 0...100, step: 1
                            )
                            .tint(.primary.opacity(0.3))
                        }
                    }
                    .padding(20)
                    .frame(width: 280)
                }

                OptionButton(icon: "arrow.counterclockwise", isActive: false) {
                    // Reset to default values
                    brightness = 100
                    contrast = 90
                    tintStrength = 30
                    isLightMode = true
                    onValueChange?()
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var brightness = 100
    @Previewable @State var contrast = 90
    @Previewable @State var tintStrength = 30

    return BoostOptions(
        brightness: $brightness,
        contrast: $contrast,
        tintStrength: $tintStrength
    )
    .frame(width: 300, height: 300)
    .background(.white)
}

struct OptionButton: View {
    var icon: String
    var isActive: Bool
    var action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    isActive ? .white.opacity(0.8) : .black.opacity(0.75)
                )
                .frame(width: 16, height: 16)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    isActive
                        ? .black.opacity(0.8)
                        : isHovered ? .black.opacity(0.1) : .black.opacity(0.07)
                )
                .animation(.linear(duration: 0.1), value: isActive)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ScaleButtonStyle())
        .onHover { state in
            isHovered = state
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(
                .easeInOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
