//
//  View+GlassEffect.swift
//  Nook
//

import SwiftUI

extension View {
    @ViewBuilder
    func nookGlassEffect<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape)
    }

    @ViewBuilder
    func nookClearGlassEffect(tint: Color) -> some View {
        self.glassEffect(.regular.tint(tint), in: .circle)
    }
}
