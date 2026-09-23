// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct SidebarMenuTab: View {
    var image: String
    var activeImage: String
    var title: String
    var isActive: Bool = true
    let action: () -> Void
    @State private var isHovering: Bool = false
    @State private var shouldWiggle: Bool = false

    private let height: CGFloat = 80

    var body: some View {
        Button {
            action()
            shouldWiggle.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .onHoverTracking { state in
            isHovering = state
        }
    }

    private var label: some View {
        VStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: isActive ? activeImage : image)
                .font(NookDesign.Font.titleLarge)
                .foregroundStyle(isActive ? .green : .primary)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.wiggle, value: shouldWiggle)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))

            Text(title)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.primary)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        // The chosen tab is glass, like the selected sidebar row, so it takes no fill of its own.
        .background(!isActive && isHovering ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.xl))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.xl))
        .nookRowSelection(isActive, radius: NookDesign.Radius.xl)
        .animation(NookDesign.Motion.quick, value: isHovering)
        .animation(NookDesign.Motion.standard, value: isActive)
    }
}
