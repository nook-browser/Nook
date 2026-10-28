// Licensed under GPL-3.0. See LICENSE.
//
//  PinnedButtonView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI
import NookDesign

public struct PinnedTabView<Icon: View>: View {
    var tabName: String
    var tabURL: String
    var tabIcon: Icon
    var isActive: Bool
    var isUnloaded: Bool = false
    /// The favorite's open page has left its pinned URL; hovering shows a reset button.
    var hasLeftPinnedURL: Bool = false
    var onResetToPinnedURL: () -> Void = {}
    /// The icon's own colors; a selected tile glows with them, as Arc's do.
    var tint: [Color] = []
    var action: () -> Void

    @State private var isHovered: Bool = false
    private let glowWidth: CGFloat = 1.5

    public init(
        tabName: String,
        tabURL: String,
        tabIcon: Icon,
        isActive: Bool,
        isUnloaded: Bool = false,
        hasLeftPinnedURL: Bool = false,
        onResetToPinnedURL: @escaping () -> Void = {},
        tint: [Color] = [],
        action: @escaping () -> Void
    ) {
        self.tint = tint
        self.tabName = tabName
        self.tabURL = tabURL
        self.tabIcon = tabIcon
        self.isActive = isActive
        self.isUnloaded = isUnloaded
        self.hasLeftPinnedURL = hasLeftPinnedURL
        self.onResetToPinnedURL = onResetToPinnedURL
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                NookDesign.Radius.shape(NookDesign.Radius.lg)
                    .fill(backgroundColor)
                    .animation(NookDesign.Motion.quick, value: isHovered)

                // Lit from within by the icon's own color when selected: a faint wash over the tile
                // and a soft glow around its inside edge.
                if isActive, !tint.isEmpty {
                    let shape = NookDesign.Radius.shape(NookDesign.Radius.lg)
                    let rim = AngularGradient(colors: tint + [tint[0]], center: .center)
                    shape.fill(LinearGradient(colors: tint.map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.strokeBorder(rim, lineWidth: glowWidth * 2)
                        .blur(radius: glowWidth * 2)
                        .opacity(0.9)
                        .clipShape(shape)
                    shape.strokeBorder(rim, lineWidth: glowWidth)
                }

                tabIcon
                    .frame(height: NookDesign.Size.essentialsFavicon)
                    // A little lift, so the icon sits on the tile rather than printed on it.
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)
            }
            .animation(NookDesign.Motion.standard, value: isActive)
            .overlay(alignment: .topTrailing) {
                if hasLeftPinnedURL && isHovered {
                    Button(action: onResetToPinnedURL) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.primary)
                            .frame(width: NookDesign.Size.cornerButton, height: NookDesign.Size.cornerButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to Pinned URL")
                    .padding(NookDesign.Spacing.xxs)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: NookDesign.Size.essentialsTile)
            .frame(minWidth: NookDesign.Size.essentialsTile)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
            .nookRowSelection(isActive, radius: NookDesign.Radius.lg)
            .nookElevation(isActive ? .raised : .flat)
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            self.isHovered = hovering
        }
    }

    //MARK: - Colors
    /// Clear when selected: `nookRowSelection` draws the raised surface.
    private var backgroundColor: Color {
        isActive ? .clear : (isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)
    }
}
