//
//  SpaceIcon.swift
//  Nook
//
//  Space icons are SF Symbol names. Values saved before Phase 2 may be
//  emoji; those still render as text so nothing breaks on upgrade.
//

import AppKit
import SwiftUI

extension String {
    /// True when the string is an emoji glyph rather than an SF Symbol name.
    var isEmojiIcon: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

/// Renders a space icon: SF Symbol tinted with the space accent, or legacy emoji as text.
struct SpaceIconView: View {
    let icon: String
    var size: CGFloat = NookDesign.Size.spaceIcon
    var tint: Color = .secondary

    var body: some View {
        Group {
            if icon.isEmojiIcon || !Self.isSymbol(icon) {
                Text(icon)
                    .font(.system(size: size))
            } else {
                Image(systemName: icon.isEmpty ? "square.grid.2x2" : icon)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size + NookDesign.Spacing.sm, height: size + NookDesign.Spacing.sm)
    }

    /// Empty resolves to the default symbol; anything else must be a real SF Symbol name.
    private static func isSymbol(_ name: String) -> Bool {
        name.isEmpty || NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
