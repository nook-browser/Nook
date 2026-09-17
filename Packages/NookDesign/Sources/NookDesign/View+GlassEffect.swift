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
    /// Liquid Glass layer that floats over content. Never sidebar rows.
    @ViewBuilder
    func nookGlassEffect<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape).nookElevation(.floating)
    }

    @ViewBuilder
    func nookClearGlassEffect(tint: Color) -> some View {
        self.glassEffect(.regular.tint(tint), in: .circle)
    }
}
