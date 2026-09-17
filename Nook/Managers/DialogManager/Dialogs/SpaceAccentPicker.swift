//
//  SpaceAccentPicker.swift
//  Nook
//
//  Eight preset swatches plus a system color well for a custom accent.
//

import SwiftUI
import NookDesign

struct SpaceAccentPicker: View {
    @Binding var selectedHex: String

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: selectedHex) },
            set: { selectedHex = $0.toHexString() ?? selectedHex }
        )
    }

    var body: some View {
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
