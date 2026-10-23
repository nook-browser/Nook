// Licensed under GPL-3.0. See LICENSE.
//
//  View+Surface.swift
//  Nook
//
//  The surface recipes every layer goes through. Nook draws no Liquid Glass: floating layers
//  are solid cards, sidebar chrome and rows are Surface fills.
//

import SwiftUI

public extension View {
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

    /// The selected sidebar row or pinned tile. Branch-free so view identity is stable and the
    /// change animates; the row applies its own `.raised` elevation.
    func nookRowSelection(_ isSelected: Bool, radius: CGFloat = NookDesign.Radius.md) -> some View {
        let shape = NookDesign.Radius.shape(radius)
        return background(shape.fill(isSelected ? NookDesign.Surface.sidebarSelection : .clear))
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

private struct NookTabSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let selected: Bool
    let hovered: Bool

    func body(content: Content) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Tab.radius)
        let fill: Color = selected
            ? .white.opacity(colorScheme == .dark ? 0.18 : 0.8)
            : hovered ? (colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)) : .clear
        content
            .clipShape(shape)
            .background {
                shape.fill(fill)
                    .shadow(color: .black.opacity(selected ? 0.10 : 0),
                            radius: NookDesign.Tab.selectedShadowRadius,
                            y: NookDesign.Tab.selectedShadowOffset)
            }
            .contentShape(shape)
    }
}

public extension View {
    /// Translucent tab card shared by sidebar rows and their native drag previews.
    func nookTabSurface(selected: Bool, hovered: Bool = false) -> some View {
        modifier(NookTabSurface(selected: selected, hovered: hovered))
    }
}

private struct NookFavoriteSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    let selected: Bool
    let hovered: Bool
    var primaryColor: Color = .accentColor
    var icon: AnyView? = nil

    private var selectedFill: Color {
        guard colorScheme == .dark else { return .white.opacity(hovered ? 0.8 : 0.85) }
        // CSS color-mix(in srgb, primary, rgba(132,132,132,.85) 40%/30%).
        // Mix premultiplied components, then unpremultiply for SwiftUI's Color.
        let primary = primaryColor.resolve(in: environment)
        let grayWeight = hovered ? 0.3 : 0.4
        let primaryAlpha = Double(primary.opacity) * (1 - grayWeight)
        let grayAlpha = 0.85 * grayWeight
        let alpha = primaryAlpha + grayAlpha
        func mix(_ component: Float) -> Double {
            (Double(component) * primaryAlpha + (132.0 / 255) * grayAlpha) / alpha
        }
        return Color(.sRGB, red: mix(primary.red), green: mix(primary.green),
                     blue: mix(primary.blue), opacity: alpha)
    }

    func body(content: Content) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Tab.radius)
        let dark = colorScheme == .dark
        let restingFill: Color = dark ? .white.opacity(hovered ? 0.20 : 0.15)
                                      : .black.opacity(hovered ? 0.10 : 0.08)
        content
            .clipShape(shape)
            .background {
                ZStack {
                    if selected, let icon {
                        // Zen's selected essential uses the enlarged, blurred favicon
                        // as its outer rim, not a uniform accent stroke.
                        GeometryReader { geometry in
                            icon
                                .frame(width: geometry.size.width * 2, height: geometry.size.height * 2)
                                .blur(radius: 20)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }
                        NookDesign.Radius.shape(NookDesign.Tab.radius - 2)
                            .fill(selectedFill)
                            .padding(2)
                    } else {
                        shape.fill(selected ? selectedFill : restingFill)
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(shape)
    }
}

public extension View {
    func nookFavoriteSurface(selected: Bool, hovered: Bool = false) -> some View {
        modifier(NookFavoriteSurface(selected: selected, hovered: hovered))
    }

    func nookFavoriteSurface<Icon: View>(selected: Bool, hovered: Bool = false,
                                         primaryColor: Color, icon: Icon) -> some View {
        modifier(NookFavoriteSurface(selected: selected, hovered: hovered,
                                     primaryColor: primaryColor, icon: AnyView(icon)))
    }
}
