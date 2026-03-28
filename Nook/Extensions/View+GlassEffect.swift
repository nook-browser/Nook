//
//  View+GlassEffect.swift
//  Nook
//

import SwiftUI

extension View {
    @ViewBuilder
    func nookGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func nookClearGlassEffect(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: .circle)
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
