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
    var isUnloaded: Bool = false
    var action: () -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovered: Bool = false

    // Stroke overlay tunables
    private let faviconScale: CGFloat = 6.0      // favicon scale to fit the ring
    private let faviconBlur: CGFloat = 30.0      // blur applied to favicon

    var body: some View {
        Button(action: action) {
            ZStack {
                ZStack {
                    NookDesign.Radius.shape(NookDesign.Radius.lg)
                        .fill(
                            backgroundColor
                        )
                        .animation(NookDesign.Motion.quick, value: isHovered)
                        .overlay {
                            if isActive {
                                tabIcon
                                    .blur(radius: 30)
                                    .opacity(0.5)
                            }

                        }
                }
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))


                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        tabIcon
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(height: NookDesign.Size.essentialsFavicon)
                            .opacity(isUnloaded ? 0.5 : 1.0)
                        Spacer()
                    }

                    Spacer()
                }


                // Favicon-based stroke overlay
                if isActive {
                    faviconStrokeOverlay(
                        corner: NookDesign.Radius.lg,
                        thickness: NookDesign.Size.essentialsStroke,
                        scale: faviconScale,
                        blur: faviconBlur
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: NookDesign.Size.essentialsTile)
            .frame(minWidth: NookDesign.Size.essentialsTile)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            self.isHovered = hovering
        }
    }
    
    //MARK: - Colors
    private var backgroundColor: Color {
        isActive ? NookDesign.Surface.raised : (isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)
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
            let outerRect = NookDesign.Radius.shape(corner - (thickness))
            let innerRect = NookDesign.Radius.shape(max(0, corner - (thickness)))

            ZStack {
                let ringMask = ZStack {
                    outerRect
                        .fill(Color.white)

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
