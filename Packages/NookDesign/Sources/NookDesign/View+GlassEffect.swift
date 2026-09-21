// Licensed under GPL-3.0. See LICENSE.
//
//  View+GlassEffect.swift
//  Nook
//
//  The only Liquid Glass entry point in the app. Every floating layer
//  (palette, toast, dialog, find bar, hover sidebar overlay, extension
//  panels, split card) goes through here so there is one recipe, not six.
//

import SwiftUI

public extension View {
    /// Liquid Glass layer that floats over content. Sidebar rows use `nookRowSelection`.
    @ViewBuilder
    func nookGlassEffect<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape).nookElevation(.floating)
    }

    @ViewBuilder
    func nookClearGlassEffect(tint: Color) -> some View {
        self.glassEffect(.regular.tint(tint), in: .circle)
    }

    /// The selected sidebar row: the one glass layer inside the sidebar. Branch-free
    /// (`.identity` when idle) so view identity is stable and the change animates.
    func nookRowSelection(_ isSelected: Bool) -> some View {
        modifier(RowSelection(isSelected: isSelected))
    }
}

private struct RowSelection: ViewModifier {
    let isSelected: Bool
    @Environment(\.nookInsideGlass) private var insideGlass

    func body(content: Content) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Radius.md)
        content
            // Never glass on glass: inside the hover overlay the row keeps its raised fill.
            .background {
                if isSelected && insideGlass {
                    shape.fill(NookDesign.Surface.raised)
                        .overlay(shape.strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth))
                }
            }
            .glassEffect(isSelected && !insideGlass ? .regular : .identity, in: shape)
    }
}

public extension EnvironmentValues {
    /// True for content drawn on a glass layer (the hover sidebar overlay).
    @Entry var nookInsideGlass: Bool = false
}
