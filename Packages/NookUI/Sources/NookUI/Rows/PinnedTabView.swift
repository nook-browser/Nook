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
    var action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        tabName: String,
        tabURL: String,
        tabIcon: Icon,
        isActive: Bool,
        isUnloaded: Bool = false,
        hasLeftPinnedURL: Bool = false,
        onResetToPinnedURL: @escaping () -> Void = {},
        action: @escaping () -> Void
    ) {
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

                tabIcon
                    .frame(height: NookDesign.Size.essentialsFavicon)
                    .opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)
            }
            .overlay(alignment: .topTrailing) {
                if hasLeftPinnedURL && isHovered {
                    Button(action: onResetToPinnedURL) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
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
    /// Clear when selected: the glass is the surface, and a fill in front of it would flatten it.
    private var backgroundColor: Color {
        isActive ? .clear : (isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)
    }
}
