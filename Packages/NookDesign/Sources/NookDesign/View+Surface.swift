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
    @Environment(\.nookUsesDefaultSpaceTheme) private var defaultTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let selected: Bool
    let hovered: Bool

    func body(content: Content) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Tab.radius)
        let dark = colorScheme == .dark
        let strongContrast = contrast == .increased
        // A mostly opaque neutral surface stabilizes contrast across multicolor themes.
        // The remaining transparency picks up the actual background beneath this row,
        // including its position in a gradient, rather than using one global accent.
        let defaultDark = defaultTheme && dark
        let opaque = reduceTransparency || strongContrast
        let darkBase = opaque ? Color(white: 0.25) : Color(red: 0.98, green: 0.984, blue: 1)
        let base = defaultTheme
            ? (dark ? darkBase : .white)
            : Color(white: 0.99)
        let opacity = opaque ? 1.0
            : defaultTheme ? (dark ? 0.20 : 0.85) : 0.92
        let hoverFill = defaultTheme
            ? (dark ? Color(red: 0.98, green: 0.984, blue: 1).opacity(0.15)
                    : Color(red: 0.055, green: 0.059, blue: 0.063).opacity(0.10))
            : (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        let fill = selected
            ? base.opacity(opacity)
            : hovered ? hoverFill : .clear
        content
            .environment(\.colorScheme, selected && !defaultDark ? .light : colorScheme)
            .clipShape(shape)
            .background {
                shape.fill(fill)
                    .overlay {
                        if selected && !defaultDark {
                            // A subtle top light gives the card a rounded, raised surface.
                            shape.fill(LinearGradient(
                                colors: [.white.opacity(0.12), .clear],
                                startPoint: .top, endPoint: .bottom
                            ))
                            shape.strokeBorder(LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(strongContrast ? 0.65 : 0.75), location: 0),
                                    .init(color: .white.opacity(0.16), location: 0.45),
                                    .init(color: .black.opacity(strongContrast ? 0.35 : 0.09), location: 1)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ), lineWidth: strongContrast ? 1 : 0.5)
                        }
                    }
                    // Contact shadow, then a soft lift: avoid a dark halo around the card.
                    .shadow(color: .black.opacity(selected && !defaultDark ? 0.16 : 0),
                            radius: 0.65, y: 0.8)
                    .shadow(color: .black.opacity(selected && !defaultDark ? 0.10 : 0),
                            radius: 2, y: 1.5)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

public extension View {
    /// Raised tab card shared by sidebar rows, split rows and native drag previews.
    func nookTabSurface(selected: Bool, hovered: Bool = false) -> some View {
        modifier(NookTabSurface(selected: selected, hovered: hovered))
    }
}

private struct NookFavoriteSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nookUsesDefaultSpaceTheme) private var defaultTheme
    let selected: Bool
    let hovered: Bool
    var primaryColor: Color = .accentColor
    var icon: AnyView? = nil

    // A white wash lifts the actual sidebar underneath, preserving gradients and grain.
    private var selectedFill: Color {
        .white.opacity(colorScheme == .dark ? (hovered ? 0.30 : 0.24) : (hovered ? 0.46 : 0.38))
    }

    func body(content: Content) -> some View {
        let shape = NookDesign.Radius.shape(NookDesign.Tab.radius)
        let dark = colorScheme == .dark
        let restingFill: Color = defaultTheme
            ? (dark ? Color(red: 0.98, green: 0.984, blue: 1).opacity(hovered ? 0.15 : 0.10)
                    : Color(red: 0.055, green: 0.059, blue: 0.063).opacity(hovered ? 0.10 : 0.05))
            : .white.opacity(dark ? (hovered ? 0.18 : 0.10) : (hovered ? 0.26 : 0.16))
        content
            .clipShape(shape)
            .background {
                ZStack {
                    if selected, let icon {
                        // Use a square color source sized to the longest edge. Fitting a
                        // square favicon into a wide rectangle leaves the side rims empty.
                        GeometryReader { geometry in
                            let diameter = max(geometry.size.width, geometry.size.height) * 2
                            icon
                                .frame(width: diameter, height: diameter)
                                .blur(radius: 20)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }
                        // Retain the existing two-point favicon rim while preventing its
                        // enlarged colors from showing through the translucent center.
                        .mask(shape.strokeBorder(lineWidth: 2))
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
