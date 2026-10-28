// Licensed under GPL-3.0. See LICENSE.
//
//  View+Surface.swift
//  Nook
//
//  The surface recipes every layer goes through. Nook draws no Liquid Glass: floating layers
//  are solid cards, sidebar chrome and rows are Surface fills.
//

import SwiftUI

private struct DefaultSpaceThemeKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while the chrome shows a space with no custom theme.
    var nookUsesDefaultSpaceTheme: Bool {
        get { self[DefaultSpaceThemeKey.self] }
        set { self[DefaultSpaceThemeKey.self] = newValue }
    }
}

public extension View {
    /// A soft page-frame shadow, drawn separately from live WebKit content.
    /// Removing the silhouette's fill keeps split gutters transparent to the window theme.
    func nookWebPageShadow<S: Shape>(in shape: S, enabled: Bool = true) -> some View {
        background {
            if enabled {
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 0)
                    .overlay {
                        shape.fill(Color.black).blendMode(.destinationOut)
                    }
                    // Only the shadow is composited; the page and its video layers
                    // remain outside this group.
                    .compositingGroup()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A layer that floats over content: solid raised card, hairline edge, floating shadow.
    func nookFloatingSurface<S: InsettableShape>(in shape: S) -> some View {
        self.clipShape(shape)
            .background(shape.fill(NookDesign.Surface.raised))
            .overlay(shape.strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth))
            .nookElevation(.floating)
    }

    /// Controls over video: a dark scrim, whatever the page or appearance.
    func nookMediaControl<S: Shape>(in shape: S) -> some View {
        background(shape.fill(NookDesign.Surface.mediaScrim))
    }

    /// Anything chosen from a set outside the tab list (Settings sidebar, library tabs, history):
    /// a solid raised fill and hairline, readable on plain backgrounds. Tab rows use
    /// `nookTabSurface`. Branch-free; the row applies its own `.raised` elevation.
    func nookRowSelection(_ isSelected: Bool, radius: CGFloat = NookDesign.Radius.md) -> some View {
        let shape = NookDesign.Radius.shape(radius)
        return background(shape.fill(isSelected ? NookDesign.Surface.raised : .clear))
            .overlay(shape.strokeBorder(NookDesign.Surface.hairline.opacity(isSelected ? 1 : 0), lineWidth: NookDesign.Size.hairlineWidth))
    }

    /// A sidebar chrome control or group: history, sidebar and AI toggles, bottom bar buttons,
    /// search fields, filter chips. `tint` marks the chosen one of a set.
    func nookControlSurface<S: InsettableShape>(_ isOn: Bool = true, tint: Color? = nil, in shape: S) -> some View {
        background(shape.fill(isOn ? (tint?.opacity(NookDesign.Surface.tintOpacity) ?? NookDesign.Surface.fill) : .clear))
    }
}

/// Native tab interaction; Reduce Motion keeps the pressed card at its original scale.
public struct NookTabButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? NookDesign.Tab.pressScale : 1)
            .animation(reduceMotion ? nil : NookDesign.Motion.quick, value: configuration.isPressed)
    }
}

public extension View {
    /// Tab card shared by sidebar rows, split rows and native drag previews: the theme-tinted
    /// selection fill, a hover fill, and a continuous `Tab.radius` shape.
    func nookTabSurface(selected: Bool, hovered: Bool = false) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Tab.radius)
        return clipShape(shape)
            .background(shape.fill(selected ? NookDesign.Surface.selection : hovered ? NookDesign.Surface.fill : .clear))
            .contentShape(shape)
    }
}
