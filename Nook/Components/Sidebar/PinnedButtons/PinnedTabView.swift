//
//  PinnedButtonView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI
import AppKit

struct PinnedTabView: View {
    var tabName: String
    var tabURL: String
    var tabIcon: SwiftUI.Image
    var isActive: Bool
    var action: () -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovered: Bool = false

    // Layout tunables
    private let corner: CGFloat = 16
    private let iconSize: CGFloat = 20
    private let innerPadding: CGFloat = 16

    // Stroke overlay tunables
    private let strokeThickness: CGFloat = 2.5   // ring thickness
    private let faviconScale: CGFloat = 10.0      // favicon scale to fit the ring
    private let faviconBlur: CGFloat = 80.0      // blur applied to favicon

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(backgroundColor)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                    .shadow(color: shadowColor, radius: 1, y: 2)

                tabIcon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .padding(.vertical, innerPadding)

                // Favicon-based stroke overlay
                if isActive {
                    faviconStrokeOverlay(
                        corner: corner,
                        thickness: strokeThickness,
                        scale: faviconScale,
                        blur: faviconBlur
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    //MARK: - Colors
    private var backgroundColor: Color {
        if isActive {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabActiveDark : AppColors.pinnedTabActiveLight
        } else if isHovered {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabHoverDark : AppColors.pinnedTabHoverLight
        } else {
            return browserManager.gradientColorManager.isDark ? AppColors.pinnedTabIdleDark : AppColors.pinnedTabIdleLight
        }
    }
    
    private var shadowColor: Color {
        if isActive {
            return browserManager.gradientColorManager.isDark ? Color.black.opacity(0.15) : Color.clear
        } else {
            return Color.clear
        }
    }

    // MARK: - Favicon stroke overlay

    private func faviconStrokeOverlay(
        corner: CGFloat,
        thickness: CGFloat,
        scale: CGFloat,
        blur: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let outerRect = RoundedRectangle(cornerRadius: corner - (thickness), style: .continuous)
            let innerRect = RoundedRectangle(cornerRadius: max(0, corner - (thickness)), style: .continuous)

            ZStack {
                let ringMask = ZStack {
                    outerRect
                        .fill(Color.white)
                        .shadow(color: .clear, radius: 0)

                    innerRect
                        .inset(by: thickness)
                        .fill(Color.black)
                        .compositingGroup()
                        .blendMode(.destinationOut)
                }

                tabIcon
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(
                        width: min(size.width, size.height) * scale,
                        height: min(size.width, size.height) * scale
                    )
                    .blur(radius: blur)
                    .frame(width: size.width, height: size.height)
                    .mask(ringMask.frame(width: size.width, height: size.height))
            }
        }
    }
}
