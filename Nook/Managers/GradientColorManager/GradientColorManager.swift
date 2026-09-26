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

    // Current accent color accessible across AppKit components for consistent selection highlights
    private(set) static var currentAccentNSColor: NSColor = NSColor(SpaceGradient.default.primaryColor)

    init() {
        Self.currentAccentNSColor = NSColor(SpaceGradient.default.primaryColor)
        Self.installSelectionColorHook()
    }

    /// Set the accent with no animation (window setup, non-active windows).
    func setImmediate(_ gradient: SpaceGradient) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            accentColor = gradient.primaryColor
            accentNSColor = NSColor(gradient.primaryColor)
            Self.currentAccentNSColor = accentNSColor
        }
    }

    /// Animate to a space's accent (active window space switch).
    func transition(to gradient: SpaceGradient) {
        withAnimation(NookDesign.Motion.standard) {
            accentColor = gradient.primaryColor
            accentNSColor = NSColor(gradient.primaryColor)
            Self.currentAccentNSColor = accentNSColor
        }
    }

    private static var didInstallSelectionHook = false

    /// Swizzles NSTextView's private selection background color method to ensure selected text
    /// uses the active space's accent color with high contrast instead of an invisible wash.
    static func installSelectionColorHook() {
        guard !didInstallSelectionHook else { return }
        didInstallSelectionHook = true

        guard let origMethod = class_getInstanceMethod(NSTextView.self, Selector(("_selectionBackgroundColor"))),
              let newMethod = class_getInstanceMethod(NSTextView.self, #selector(NSTextView.nook_selectionBackgroundColor)) else {
            return
        }
        method_exchangeImplementations(origMethod, newMethod)
    }
}

// MARK: - NSTextView Selection Styling

extension NSTextView {
    @objc func nook_selectionBackgroundColor() -> NSColor {
        let accent = GradientColorManager.currentAccentNSColor
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        guard let rgb = accent.usingColorSpace(.sRGB) else {
            return accent
        }

        // Relative luminance: 0.2126 * R + 0.7152 * G + 0.0722 * B
        let lum = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if isDark {
            // Ensure minimum luminance so selection stands out against dark glass (~#1D1D1D)
            if lum < 0.18 {
                return rgb.blended(withFraction: 0.35, of: .white) ?? rgb
            }
        } else {
            // Ensure contrast against light background
            if lum > 0.82 {
                return rgb.blended(withFraction: 0.35, of: .black) ?? rgb
            }
        }
        return rgb
    }
}
