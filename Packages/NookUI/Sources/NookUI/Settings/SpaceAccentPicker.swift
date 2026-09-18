// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SpaceAccentPicker.swift
//  Nook
//
//  Eight preset swatches plus a system color well for a custom accent.
//

import SwiftUI
import NookDesign

public struct SpaceAccentPicker: View {
    @Binding var selectedHex: String

    @Environment(\.self) private var environment

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: selectedHex) },
            set: { selectedHex = $0.hexString(in: environment) }
        )
    }

    public init(selectedHex: Binding<String>) {
        self._selectedHex = selectedHex
    }

    public var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            ForEach(SpaceAccent.presets, id: \.hex) { preset in
                Button {
                    selectedHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                        .overlay {
                            if preset.hex.caseInsensitiveCompare(selectedHex) == .orderedSame {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                                    .padding(NookDesign.Spacing.xxs)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
            ColorPicker("", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")
        }
    }
}

// MARK: - Hex

extension Color {
    /// `#RRGGBB` for a colour the system picker returns. `Color(hex:)` is its inverse.
    func hexString(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        let byte = { (value: Float) in Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }
}
