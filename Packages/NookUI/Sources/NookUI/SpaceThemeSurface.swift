// Licensed under GPL-3.0. See LICENSE.
// Native window backdrop with optional color washes and generated grain.
import SwiftUI
import Foundation
import NookDesign
import NookTabsCore
#if os(macOS)
import AppKit
#endif

/// Shared window-coordinate background for the sidebar and the frame surrounding web pages.
public struct SpaceThemeSurface: View {
    public var appearance: SpaceAppearance
    public var isActive: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(appearance: SpaceAppearance, isActive: Bool = true) {
        self.appearance = appearance
        self.isActive = isActive
    }

    private var dark: Bool {
        appearance.mode == .dark || (appearance.mode == .system && colorScheme == .dark)
    }

    public var body: some View {
        let theme = appearance.normalized
        let colors = theme.nodes.map { wash($0.colorHex) }
        ZStack {
            if reduceTransparency {
                NookDesign.Surface.windowBackground
            } else {
                #if os(macOS)
                SpaceThemeMaterial(defaultTheme: theme.usesDefaultTheme, dark: dark)
                #else
                Rectangle().fill(.regularMaterial)
                #endif
            }
            ZStack {
                if colors.isEmpty {
                    DefaultSpaceThemeGradient(dark: dark)
                } else if colors.count == 1 {
                    colors[0]
                } else if colors.count == 2 {
                    LinearGradient(colors: [colors[0], colors[1]], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                } else {
                    colors[2]
                    GeometryReader { proxy in
                        let radius = max(proxy.size.width, proxy.size.height) * 0.95
                        RadialGradient(colors: [colors[1], colors[1].opacity(0)], center: .topTrailing, startRadius: 0, endRadius: radius)
                        RadialGradient(colors: [colors[0], colors[0].opacity(0)], center: .topLeading, startRadius: 0, endRadius: radius * 0.85)
                    }
                }
            }
            .opacity((theme.usesDefaultTheme ? 1 : theme.opacity) * (isActive ? 1 : 0.65))
            if theme.grain > 0, let texture = SpaceThemeGrain.image {
                Image(decorative: texture, scale: 1)
                    .resizable(resizingMode: .tile)
                    .blendMode(.softLight)
                    .opacity(theme.grain * 0.35)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func wash(_ hex: String) -> Color {
        // Explicit colors avoid resolving a dynamic NSColor in the wrong window appearance.
        let cleaned = String(hex.suffix(6))
        let value = UInt32(cleaned, radix: 16) ?? 0x7C7C7C
        let components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        let mix = dark ? 0.48 : 0.18
        let base = dark ? 0.035 : 1.0
        let c = components.map { $0 * (1 - mix) + base * mix }
        return Color(red: c[0], green: c[1], blue: c[2])
    }
}

/// Built-in light/dark palette with perceptual color interpolation.
/// Cached samples approximate OKLab interpolation without shipping a Metal renderer.
private struct DefaultSpaceThemeGradient: View {
    var dark: Bool

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: dark ? Self.darkStops : Self.lightStops,
                startPoint: .topLeading,
                endPoint: Self.endPoint(for: proxy.size)
            )
        }
    }

    private static let lightStops = stops(first: 0xC8CAFE, last: 0xFFE6E6, intensity: 0.5, dark: false)
    private static let darkStops = stops(first: 0x01021E, last: 0x17011E, intensity: 0.8, dark: true)

    private static func endPoint(for size: CGSize) -> UnitPoint {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let ratio = width / height
        let q = min(ratio, 1 / ratio)
        let minor = (q + q * q) / (2 * (1 + q * q))
        let x = ratio > 1 ? 1 - minor : minor
        let y = 1 - x
        // Keep the gradient direction consistent in physical window space,
        // rather than stretching a fixed diagonal as the window changes aspect.
        let denominator = x * x / (width * width) + y * y / (height * height)
        return UnitPoint(x: x / (width * width * denominator),
                         y: y / (height * height * denominator))
    }

    private static func stops(first: UInt32, last: UInt32, intensity: Double, dark: Bool) -> [Gradient.Stop] {
        let start = oklab(first)
        let end = oklab(last)
        let weight = 0.55 * intensity + 0.2
        let backgroundAlpha = min(weight, 0.5) * (dark ? 0.35 : 1)
        let alpha = weight + backgroundAlpha * (1 - weight)
        let background = dark ? 0.0 : 1.0
        // 96 intervals include the final color stop at t = 0.75.
        return (0...96).map { index in
            let location = Double(index) / 96
            let amount = min(location * 1.333333373, 1)
            let lab = start + (end - start) * amount
            let rgb = encodedRGB(lab)
            func composite(_ channel: Double) -> Double {
                (channel * weight + background * backgroundAlpha * (1 - weight)) / alpha
            }
            return Gradient.Stop(
                color: Color(.sRGB, red: composite(rgb.x), green: composite(rgb.y),
                             blue: composite(rgb.z), opacity: alpha),
                location: location
            )
        }
    }

    private static func dot(_ value: SIMD3<Double>, _ x: Double, _ y: Double, _ z: Double) -> Double {
        value.x * x + value.y * y + value.z * z
    }

    private static func oklab(_ hex: UInt32) -> SIMD3<Double> {
        func linear(_ byte: UInt32) -> Double {
            let value = Double(byte & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let rgb = SIMD3(linear(hex >> 16), linear(hex >> 8), linear(hex))
        let lms = SIMD3(
            cbrt(dot(rgb, 0.4122214615, 0.5363325477, 0.0514459945)),
            cbrt(dot(rgb, 0.2119034976, 0.6806995273, 0.1073969603)),
            cbrt(dot(rgb, 0.0883024633, 0.2817188501, 0.6299787164))
        )
        return SIMD3(
            dot(lms, 0.2104542553, 0.7936177850, -0.0040720468),
            dot(lms, 1.9779984951, -2.4285922050, 0.4505937099),
            dot(lms, 0.0259040371, 0.7827717662, -0.8086757660)
        )
    }

    private static func encodedRGB(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let roots = SIMD3(
            dot(lab, 1, 0.3963377774, 0.2158037573),
            dot(lab, 1, -0.1055613458, -0.0638541728),
            dot(lab, 1, -0.0894841775, -1.291485548)
        )
        let lms = roots * roots * roots
        func encode(_ value: Double) -> Double {
            let magnitude = abs(value)
            if magnitude <= 0.0031308 { return 12.92 * value }
            let encoded = 1.055 * pow(magnitude, 1 / 2.4) - 0.055
            return value < 0 ? -encoded : encoded
        }
        return SIMD3(
            encode(dot(lms, 4.0767416954, -3.3077116013, 0.2309699357)),
            encode(dot(lms, -1.2684379816, 2.6097574234, -0.3413193822)),
            encode(dot(lms, -0.0041960864, -0.7034186125, 1.7076146603))
        )
    }
}

#if os(macOS)
private struct SpaceThemeMaterial: NSViewRepresentable {
    var defaultTheme: Bool
    var dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        if defaultTheme {
            // Resolve automatic appearance before choosing the AppKit
            // light/dark materials (raw values 1/2).
            view.material = NSVisualEffectView.Material(rawValue: dark ? 2 : 1) ?? .windowBackground
        } else {
            view.material = .sidebar
        }
        view.isEmphasized = defaultTheme
        view.appearance = defaultTheme ? NSAppearance(named: dark ? .darkAqua : .aqua) : nil
    }
}
#endif

private enum SpaceThemeGrain {
    // Generated once, tiled at native scale. No animation, timers or per-frame random work.
    static let image: CGImage? = {
        let side = 128
        var state: UInt32 = 0x4E4F4F4B
        let bytes: [UInt8] = (0..<(side * side)).map { _ in
            state = state &* 1664525 &+ 1013904223
            return UInt8(state >> 24)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}
