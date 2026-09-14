//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct SpaceSeparator: View {
    @Binding var isHovering: Bool
    let onClear: () -> Void
    let onOrganize: (() -> Void)?
    let isOrganizing: Bool
    let tabCount: Int
    @State private var isClearHovered: Bool = false
    @State private var isOrganizeHovered: Bool = false

    var body: some View {
        let hasTabs = tabCount > 0
        HStack(spacing: 0) {
            // Organize button (left side)
            if hasTabs && tabCount >= 5 && isHovering {
                if isOrganizing {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.horizontal, 4)
                        .transition(.blur.animation(NookDesign.Motion.quick))
                } else if let onOrganize {
                    Button(action: onOrganize) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(NookDesign.Font.caption)
                            Text("Organize")
                                .font(NookDesign.Font.caption)
                        }
                        .foregroundStyle(organizeColor)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Organize tabs with AI")
                    .transition(.blur.animation(NookDesign.Motion.quick))
                    .onHoverTracking { state in
                        isOrganizeHovered = state
                    }
                }
            }

            Capsule()
                .fill(NookDesign.Surface.hairline)
                .frame(height: 1)
                .animation(NookDesign.Motion.quick, value: isHovering)

            // Clear button (right side)
            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                            .font(NookDesign.Font.caption)
                        Text("Clear")
                            .font(NookDesign.Font.caption)
                    }
                    .foregroundStyle(clearColor)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .transition(.blur.animation(NookDesign.Motion.quick))
                .onHoverTracking { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }

    private var clearColor: Color {
        isClearHovered ? .primary : .secondary
    }

    private var organizeColor: Color {
        isOrganizeHovered ? .primary : .secondary
    }
}
 
