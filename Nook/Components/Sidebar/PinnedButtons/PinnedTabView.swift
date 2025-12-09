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
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.nookSettings) var nookSettings
    @State private var isHovered: Bool = false

    // Stroke overlay tunables
    private let faviconScale: CGFloat = 6.0      // favicon scale to fit the ring
    private let faviconBlur: CGFloat = 30.0      // blur applied to favicon

    var body: some View {
        let pinnedTabsConfiguration: PinnedTabsConfiguration = nookSettings.pinnedTabsLook
        Button(action: action) {
            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: pinnedTabsConfiguration.cornerRadius, style: .continuous)
                        .fill(
                            backgroundColor
                        )
                        .animation(.easeInOut(duration: 0.1), value: isHovered)
                        .overlay {
                            if isActive {
                                tabIcon
                                    .blur(radius: 30)
                                    .opacity(0.5)
                            }
          
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: pinnedTabsConfiguration.cornerRadius, style: .continuous))

                
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        tabIcon
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(height: pinnedTabsConfiguration.faviconHeight)
                        Spacer()
                    }

                    Spacer()
                }


                // Favicon-based stroke overlay
                if isActive {
                    faviconStrokeOverlay(
                        corner: pinnedTabsConfiguration.cornerRadius,
                        thickness: pinnedTabsConfiguration.strokeWidth,
                        scale: faviconScale,
                        blur: faviconBlur
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: pinnedTabsConfiguration.height)
            .frame(minWidth: pinnedTabsConfiguration.minWidth)
            .contentShape(RoundedRectangle(cornerRadius: pinnedTabsConfiguration.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    //MARK: - Colors
    private var backgroundColor: Color {
        if isActive {
            return colorScheme == .dark ? AppColors.pinnedTabActiveLight : AppColors.pinnedTabActiveDark
        } else if isHovered {
            return colorScheme == .dark ? AppColors.pinnedTabHoverLight : AppColors.pinnedTabHoverDark
        } else {
            return colorScheme == .dark ? AppColors.pinnedTabIdleLight : AppColors.pinnedTabIdleDark
        }
    }

    private var shadowColor: Color {
        if isActive {
            return colorScheme == .dark ? Color.clear : Color.black.opacity(0.15)
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
