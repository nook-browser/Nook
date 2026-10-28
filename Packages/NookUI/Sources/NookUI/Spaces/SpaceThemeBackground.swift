// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceThemeBackground.swift
//  NookUI
//
//  The window and sidebar fill for a space: its theme when it has one, else the accent gradient.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
import NookDesign
import NookTabsCore

public struct SpaceChromeBackground: View {
    let theme: SpaceTheme?
    let accent: Color
    let isActive: Bool
    /// Off for small previews: each live behind-window blur is a WindowServer layer of its own.
    var blursBehind = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(theme: SpaceTheme?, accent: Color, isActive: Bool, blursBehind: Bool = true) {
        self.theme = theme
        self.accent = accent
        self.isActive = isActive
        self.blursBehind = blursBehind
    }

    public var body: some View {
        if let theme {
            let resolved = theme.resolve(systemDark: colorScheme == .dark, dimmed: !isActive)
            let twoTone = theme.points.count > 1
            LinearGradient(
                colors: resolved.stops.map(Color.init),
                startPoint: twoTone ? .topLeading : .top,
                endPoint: twoTone ? .bottomTrailing : .bottom)
                // Intensity is how much of the desktop shows through, as in Arc.
                .opacity(reduceTransparency || !blursBehind ? 1 : NookDesign.Surface.themeTintOpacity(intensity: theme.intensity))
                .background {
                    #if os(macOS)
                    if !reduceTransparency && blursBehind { BehindWindowBlur(isDark: resolved.isDark) }
                    #endif
                }
                .overlay {
                    // Only when there is grain: an overlay blend is its own compositing pass every
                    // frame the window redraws, invisible or not.
                    if resolved.grain > 0.001 {
                        FilmGrain(opacity: resolved.grain * NookDesign.Surface.themeGrainOpacity)
                    }
                }
        } else {
            NookDesign.Surface.containerGradient(accent: accent, isActive: isActive)
        }
    }
}

#if os(macOS)
/// The desktop, blurred, behind a themed space's chrome. WindowServer does the blur, and only
/// themed spaces pay for it; a space without a theme keeps the flat gradient.
private struct BehindWindowBlur: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        // Inactive windows go flat gray, which is the dimming the chrome wants anyway.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // A theme's forced light or dark mode has to reach the material too.
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
#endif

extension Color {
    init(_ rgb: ThemeRGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension View {
    /// Forces the theme's light or dark appearance on the chrome it wraps. Pages are not
    /// wrapped: a site keeps following the system, as in Arc.
    public func spaceThemeAppearance(_ theme: SpaceTheme?) -> some View {
        transformEnvironment(\.colorScheme) { scheme in
            switch theme?.mode {
            case .light?: scheme = .light
            case .dark?: scheme = .dark
            case .auto?, nil: break
            }
        }
    }
}
