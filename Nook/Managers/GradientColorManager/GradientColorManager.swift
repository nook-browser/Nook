// Licensed under GPL-3.0. See LICENSE.
//
//  GradientColorManager.swift
//  Nook
//
//  Publishes the active space's accent color. The type name predates the
//  Phase 2 remodel; it no longer holds a gradient, only the one color
//  derived from it.
//

import AppKit
import SwiftUI
import NookDesign

@MainActor
final class GradientColorManager: ObservableObject {
    @Published private(set) var accentColor: Color = SpaceGradient.default.primaryColor
    @Published private(set) var accentNSColor: NSColor = NSColor(SpaceGradient.default.primaryColor)

    /// Set the accent with no animation (window setup, non-active windows).
    func setImmediate(_ gradient: SpaceGradient) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            accentColor = gradient.primaryColor
            accentNSColor = NSColor(gradient.primaryColor)
        }
    }

    /// Animate to a space's accent (active window space switch).
    func transition(to gradient: SpaceGradient) {
        withAnimation(NookDesign.Motion.standard) {
            accentColor = gradient.primaryColor
            accentNSColor = NSColor(gradient.primaryColor)
        }
    }
}
