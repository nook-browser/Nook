// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import NookDesign

public struct SpaceSeparator: View {
    @Binding var isHovering: Bool
    let onClear: () -> Void
    let onOrganize: (() -> Void)?
    let isOrganizing: Bool
    let tabCount: Int
    @State private var isClearHovered: Bool = false
    @State private var isOrganizeHovered: Bool = false

    public init(
        isHovering: Binding<Bool>,
        onClear: @escaping () -> Void,
        onOrganize: (() -> Void)?,
        isOrganizing: Bool,
        tabCount: Int
    ) {
        self._isHovering = isHovering
        self.onClear = onClear
        self.onOrganize = onOrganize
        self.isOrganizing = isOrganizing
        self.tabCount = tabCount
    }

    public var body: some View {
        let hasTabs = tabCount > 0
        HStack(spacing: 0) {
            Capsule()
                .fill(NookDesign.Surface.hairline)
                .frame(height: NookDesign.Size.hairlineWidth)
                .padding(.horizontal, NookDesign.Spacing.md)
                .animation(NookDesign.Motion.quick, value: isHovering)

            // Organize button (trailing side)
            if hasTabs && tabCount >= 5 && isHovering {
                if isOrganizing {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.horizontal, NookDesign.Spacing.xs)
                        .transition(.blur.animation(NookDesign.Motion.quick))
                } else if let onOrganize {
                    Button(action: onOrganize) {
                        HStack(spacing: NookDesign.Spacing.xs) {
                            Image(systemName: "wand.and.stars")
                                .font(NookDesign.Font.caption)
                            Text("Organize")
                                .font(NookDesign.Font.caption)
                        }
                        .foregroundStyle(isOrganizeHovered ? .primary : .tertiary)
                        .padding(.horizontal, NookDesign.Spacing.xs)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Organize tabs with AI")
                    .transition(.blur.animation(NookDesign.Motion.quick))
                    .onHoverTracking { state in
                        isOrganizeHovered = state
                    }
                }
            }

            // Clear button (trailing side)
            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: NookDesign.Spacing.xs) {
                        Image(systemName: "arrow.down")
                            .font(NookDesign.Font.caption)
                        Text("Clear")
                            .font(NookDesign.Font.caption)
                    }
                    .foregroundStyle(isClearHovered ? .primary : .tertiary)
                    .padding(.horizontal, NookDesign.Spacing.xs)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .transition(.blur.animation(NookDesign.Motion.quick))
                .onHoverTracking { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: NookDesign.Size.rowGlyph + NookDesign.Spacing.xxs)
        .frame(maxWidth: .infinity)
    }
}
 
