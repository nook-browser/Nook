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
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isClearHovered: Bool = false
    @State private var isOrganizeHovered: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let hasTabs = tabCount > 0
        HStack(spacing: 0) {
            // Organize button (left side)
            if hasTabs && tabCount >= 5 && isHovering {
                if isOrganizing {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.horizontal, 4)
                        .transition(.blur.animation(.smooth(duration: 0.08)))
                } else if let onOrganize {
                    Button(action: onOrganize) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 9, weight: .bold))
                            Text("Organize")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(organizeColor)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Organize tabs with AI")
                    .transition(.blur.animation(.smooth(duration: 0.08)))
                    .onHoverTracking { state in
                        isOrganizeHovered = state
                    }
                }
            }

            RoundedRectangle(cornerRadius: 100)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.15))
                .frame(height: 1)
                .animation(.smooth(duration: 0.1), value: isHovering)

            // Clear button (right side)
            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("Clear")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(clearColor)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .transition(.blur.animation(.smooth(duration: 0.08)))
                .onHoverTracking { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }

    private var clearColor: Color {
        if isClearHovered {
            return browserManager.gradientColorManager.isDark ? Color.black.opacity(0.85) : Color.white
        }
        return browserManager.gradientColorManager.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.3)
    }

    private var organizeColor: Color {
        if isOrganizeHovered {
            return browserManager.gradientColorManager.isDark ? Color.black.opacity(0.85) : Color.white
        }
        return browserManager.gradientColorManager.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.3)
    }
}
 
