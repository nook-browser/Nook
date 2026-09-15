//
//  PinnedButtonView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI
import AppKit

struct PinnedTabView<Icon: View>: View {
    var tabName: String
    var tabURL: String
    var tabIcon: Icon
    var isActive: Bool
    var isUnloaded: Bool = false
    /// The favorite's open page has left its home URL.
    var showsLeftHomeDot: Bool = false
    var action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                NookDesign.Radius.shape(NookDesign.Radius.lg)
                    .fill(backgroundColor)
                    .animation(NookDesign.Motion.quick, value: isHovered)

                tabIcon
                    .frame(height: NookDesign.Size.essentialsFavicon)
                    .opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)

                if isActive {
                    NookDesign.Radius.shape(NookDesign.Radius.lg)
                        .strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsLeftHomeDot {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: NookDesign.Size.statusDot, height: NookDesign.Size.statusDot)
                        .padding(NookDesign.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: NookDesign.Size.essentialsTile)
            .frame(minWidth: NookDesign.Size.essentialsTile)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
            .nookElevation(isActive ? .raised : .flat)
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
}
