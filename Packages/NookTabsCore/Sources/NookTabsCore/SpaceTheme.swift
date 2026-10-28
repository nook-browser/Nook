// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// A space's chrome theme, edited in the Edit Theme Color panel: one or two points on a color
/// canvas, an appearance, how strongly the color tints the chrome, and film grain.
/// Saved on `SpaceRecord.theme`; a space without one keeps its plain accent gradient.
public struct SpaceTheme: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable { case auto, light, dark }

    /// A point on the canvas, 0...1 on each axis with the origin top left. The center is
    /// neutral; the angle around it is the hue and the distance from it the saturation.
    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = min(1, max(0, x))
            self.y = min(1, max(0, y))
        }
        public static let center = Point(x: 0.5, y: 0.5)

        /// The point at `hue` (OKLCH degrees) and `saturation` (0...1 of the canvas radius).
        public init(hue: Double, saturation: Double) {
            let radians = hue * .pi / 180
            let r = min(1, max(0, saturation)) * 0.5
            self.init(x: 0.5 + r * cos(radians), y: 0.5 - r * sin(radians))
        }

        public var hue: Double {
            let degrees = atan2(0.5 - y, x - 0.5) * 180 / .pi
            return degrees < 0 ? degrees + 360 : degrees
        }

        public var saturation: Double { min(1, hypot(x - 0.5, y - 0.5) / 0.5) }
    }

    public static let maxPoints = 2

    public var points: [Point]
    public var mode: Mode
    public var intensity: Double
    public var grain: Double

    public init(points: [Point], mode: Mode = .auto, intensity: Double = 0.6, grain: Double = 0) {
        self.points = Array((points.isEmpty ? [.center] : points).prefix(Self.maxPoints))
        self.mode = mode
        self.intensity = min(1, max(0, intensity))
        self.grain = min(1, max(0, grain))
    }

    /// A theme matching an existing accent, so opening the editor changes nothing until the
    /// person moves something.
    public init(accentHex: String) {
        guard let rgb = ThemeRGB(hex: accentHex) else { self.init(points: [.center]); return }
        let lch = rgb.oklch
        self.init(points: [Point(hue: lch.h, saturation: lch.c / Self.accentChroma)])
    }

    // Every field decodes on its own, so a value a newer build writes never fails the whole
    // tab file (which would leave the app read-only).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            points: (try? c.decode([Point].self, forKey: .points)) ?? [.center],
            mode: (try? c.decode(Mode.self, forKey: .mode)) ?? .auto,
            intensity: (try? c.decode(Double.self, forKey: .intensity)) ?? 0.6,
            grain: (try? c.decode(Double.self, forKey: .grain)) ?? 0)
    }

    // MARK: - Resolving

    /// Chroma of a point at the canvas rim for the accent color (dots, folder icons).
    static let accentChroma = 0.16

    /// What the chrome draws: gradient stops top to bottom, whether it is dark, and the accent.
    public struct Resolved: Hashable, Sendable {
        public var stops: [ThemeRGB]
        public var accent: ThemeRGB
        public var isDark: Bool
        public var grain: Double
    }

    public func isDark(systemDark: Bool) -> Bool {
        switch mode {
        case .auto: return systemDark
        case .light: return false
        case .dark: return true
        }
    }

    /// `dimmed` is an inactive window: the tint fades further toward neutral.
    public func resolve(systemDark: Bool, dimmed: Bool = false) -> Resolved {
        let dark = isDark(systemDark: systemDark)
        // Some tint survives at zero intensity, as in Arc, so the slider never reads as off.
        let strength = (0.25 + 0.75 * intensity) * (dimmed ? 0.55 : 1)
        var stops = points.map { Self.chromeColor($0, dark: dark, strength: strength) }
        if stops.count == 1 {
            // One color still reads as a gradient: a touch lighter at the top.
            let lch = stops[0]
            stops = [lch.adjusted(dl: 0.025), lch.adjusted(dl: -0.02)]
        }
        return Resolved(
            stops: stops.map(\.rgb),
            accent: Self.accentColor(points[0]),
            isDark: dark,
            grain: grain)
    }

    static func chromeColor(_ p: Point, dark: Bool, strength: Double) -> OKLCH {
        let s = p.saturation * strength
        return dark
            ? OKLCH(l: 0.21 + 0.17 * s, c: 0.13 * s, h: p.hue)
            : OKLCH(l: 0.955 - 0.11 * s, c: 0.11 * s, h: p.hue)
    }

    /// The fill of a puck on the canvas: the color at full strength, black or white at center.
    public static func puckColor(_ p: Point, dark: Bool) -> ThemeRGB {
        let s = p.saturation
        return (dark
            ? OKLCH(l: 0.12 + 0.56 * s, c: 0.17 * s, h: p.hue)
            : OKLCH(l: 0.99 - 0.27 * s, c: 0.17 * s, h: p.hue)).rgb
    }

    /// A preset swatch: light enough to read on the panel in either appearance.
    public static func swatchColor(_ p: Point) -> ThemeRGB {
        OKLCH(l: 0.95 - 0.2 * p.saturation, c: 0.14 * p.saturation, h: p.hue).rgb
    }

    public static func accentColor(_ p: Point) -> ThemeRGB {
        OKLCH(l: 0.64, c: accentChroma * p.saturation, h: p.hue).rgb
    }
}

// MARK: - Color math

/// An sRGB color, 0...1 per channel.
public struct ThemeRGB: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        let byte = { (v: Double) in Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        0.2126 * Self.linear(r) + 0.7152 * Self.linear(g) + 0.0722 * Self.linear(b)
    }

    var oklch: OKLCH {
        let lr = Self.linear(r), lg = Self.linear(g), lb = Self.linear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCH(l: L, c: hypot(a, bb), h: h)
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

/// OKLCH: perceptual lightness, chroma, hue in degrees. Blending here keeps every hue at the
/// same perceived brightness, which plain HSB does not (yellow glares, blue sinks).
struct OKLCH: Hashable, Sendable {
    var l: Double
    var c: Double
    var h: Double

    func adjusted(dl: Double) -> OKLCH { OKLCH(l: min(1, max(0, l + dl)), c: c, h: h) }

    /// The sRGB color, with chroma reduced until it fits the gamut so the hue never shifts.
    var rgb: ThemeRGB {
        let full = linearRGB(chroma: c)
        if full.inGamut { return full.encoded }
        var low = 0.0, high = c
        var best = linearRGB(chroma: 0)
        for _ in 0..<16 {
            let mid = (low + high) / 2
            let candidate = linearRGB(chroma: mid)
            if candidate.inGamut { best = candidate; low = mid } else { high = mid }
        }
        return best.encoded
    }

    private func linearRGB(chroma: Double) -> ThemeRGB {
        let radians = h * .pi / 180
        let a = chroma * cos(radians), b = chroma * sin(radians)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        return ThemeRGB(
            r: 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            g: -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            b: -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }
}

private extension ThemeRGB {
    var inGamut: Bool {
        let e = 1e-4
        return r >= -e && r <= 1 + e && g >= -e && g <= 1 + e && b >= -e && b <= 1 + e
    }
    var encoded: ThemeRGB { ThemeRGB(r: Self.encoded(min(1, max(0, r))), g: Self.encoded(min(1, max(0, g))), b: Self.encoded(min(1, max(0, b)))) }
}
