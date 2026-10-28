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

        /// The point whose accent is closest to `rgb`: its hue, and its chroma as saturation.
        public init(rgb: ThemeRGB) {
            let lch = rgb.oklch
            self.init(hue: lch.h, saturation: lch.c / SpaceTheme.accentChroma)
        }
    }

    /// How the other colors sit around the key color on the wheel, as in Arc.
    public enum Wheel: String, Codable, Sendable, CaseIterable { case analogous, complementary }

    /// The noise texture laid over the chrome.
    public enum Overlay: String, Codable, Sendable, CaseIterable { case grain, sand, denim, tweed }

    public static let maxPoints = 3

    /// The key color first, then the colors derived from it by `wheel` (kept in step by
    /// `didSet`, so moving the key moves the rest, as Arc's knobs do).
    public var points: [Point] { didSet { if points != oldValue { sync() } } }
    public var mode: Mode
    public var intensity: Double
    public var grain: Double
    public var wheel: Wheel { didSet { if wheel != oldValue { sync() } } }
    public var overlay: Overlay
    /// The key color's lightness, 0 black to 1 white, set by a grey preset (Arc's key color
    /// carries lightness); nil follows the key's saturation.
    public var tone: Double?
    public var colorCount: Int {
        didSet {
            colorCount = min(Self.maxPoints, max(1, colorCount))
            if colorCount != oldValue { sync() }
        }
    }

    public init(
        points: [Point], mode: Mode = .auto, intensity: Double = 0.6, grain: Double = 0,
        wheel: Wheel = .analogous, overlay: Overlay = .grain, colorCount: Int? = nil, tone: Double? = nil
    ) {
        let key = points.first ?? .center
        self.points = [key]
        self.mode = mode
        self.intensity = min(1, max(0, intensity))
        self.grain = min(1, max(0, grain))
        self.wheel = wheel
        self.overlay = overlay
        self.tone = tone.map { min(1, max(0, $0)) }
        self.colorCount = min(Self.maxPoints, max(1, colorCount ?? points.count))
        sync()
    }

    // MARK: - Arc's color rules

    /// Hues of `count` colors around `key`: N=2 +40 (analogous) or +180; N=3 +-40 or +150/+210;
    /// beyond that evenly spaced.
    public static func hues(key: Double, count: Int, wheel: Wheel) -> [Double] {
        let offsets: [Double]
        switch (count, wheel) {
        case (...1, _): offsets = [0]
        case (2, .analogous): offsets = [0, 40]
        case (2, .complementary): offsets = [0, 180]
        case (3, .analogous): offsets = [0, 40, -40]
        case (3, .complementary): offsets = [0, 150, 210]
        default: offsets = (0..<count).map { Double($0) * 360 / Double(count) }
        }
        return offsets.map { offset in
            let h = (key + offset).truncatingRemainder(dividingBy: 360)
            return h < 0 ? h + 360 : h
        }
    }

    /// The lightness a forced appearance allows; unconstrained is 0.01...0.97.
    public static func lightnessRange(forced mode: Mode) -> ClosedRange<Double> {
        switch mode {
        case .auto: return 0.01...0.97
        case .light: return 0.575...0.97
        case .dark: return 0.01...0.425
        }
    }

    public static func clampLightness(_ l: Double, forced mode: Mode) -> Double {
        let range = lightnessRange(forced: mode)
        return min(range.upperBound, max(range.lowerBound, l))
    }

    /// Keeps `points` at the key plus `colorCount - 1` companions. A theme saved with free
    /// second points (the first editor) keeps its key and takes derived companions.
    private mutating func sync() {
        let key = points.first ?? .center
        let hues = Self.hues(key: key.hue, count: colorCount, wheel: wheel)
        let derived = hues.dropFirst().map { Point(hue: $0, saturation: key.saturation) }
        let next = [key] + derived
        if next != points { points = next }
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
            grain: (try? c.decode(Double.self, forKey: .grain)) ?? 0,
            wheel: (try? c.decode(Wheel.self, forKey: .wheel)) ?? .analogous,
            overlay: (try? c.decode(Overlay.self, forKey: .overlay)) ?? .grain,
            colorCount: try? c.decode(Int.self, forKey: .colorCount),
            tone: try? c.decode(Double.self, forKey: .tone))
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
        public var overlay: Overlay
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
        var stops = points.map { Self.chromeColor($0, dark: dark, strength: strength, tone: tone) }
        if stops.count == 1 {
            // One color still reads as a gradient: a touch lighter at the top.
            let lch = stops[0]
            stops = [lch.adjusted(dl: 0.025), lch.adjusted(dl: -0.02)]
        }
        return Resolved(
            stops: stops.map(\.rgb),
            accent: Self.accentColor(points[0]),
            isDark: dark,
            grain: grain,
            overlay: overlay)
    }

    /// A favorite tile's colors over the chrome `chrome`. Light follows Arc, measured on a
    /// #B1DAEA sidebar: tile #A7CEDD, selected #D0E6F1 with a #A6BFC8 edge. Dark is not measured:
    /// the same steps toward white instead of black.
    public struct TileColors: Hashable, Sendable {
        public var fill: ThemeRGB
        public var hoverFill: ThemeRGB
        public var selectedFill: ThemeRGB
        public var selectedBorder: ThemeRGB
    }

    public static func tileColors(chrome: ThemeRGB, dark: Bool) -> TileColors {
        func mix(_ a: ThemeRGB, _ b: ThemeRGB, _ t: Double) -> ThemeRGB {
            ThemeRGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
        }
        let white = ThemeRGB(r: 1, g: 1, b: 1), black = ThemeRGB(r: 0, g: 0, b: 0)
        if dark {
            let selected = mix(chrome, white, 0.18)
            return TileColors(
                fill: mix(chrome, white, 0.07), hoverFill: mix(chrome, white, 0.12),
                selectedFill: selected, selectedBorder: mix(selected, white, 0.14))
        }
        let selected = mix(chrome, white, 0.36)
        return TileColors(
            fill: mix(chrome, black, 0.054), hoverFill: mix(chrome, selected, 0.5),
            selectedFill: selected, selectedBorder: mix(selected, black, 0.2))
    }

    static func chromeColor(_ p: Point, dark: Bool, strength: Double, tone: Double? = nil) -> OKLCH {
        let s = p.saturation * strength
        var l = dark ? 0.21 + 0.17 * s : 0.955 - 0.11 * s
        if let tone {
            // The tone's departure from the neutral chrome, scaled like a color's saturation.
            let neutral = dark ? 0.21 : 0.955
            let target = dark ? 0.12 + 0.30 * tone : 0.80 + 0.17 * tone
            l = neutral + (target - neutral) * strength
        }
        return OKLCH(l: clampLightness(l, forced: dark ? .dark : .light), c: dark ? 0.13 * s : 0.11 * s, h: p.hue)
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

    /// A Display P3 color (Arc's presets are stored in it), converted to sRGB. Out-of-gamut
    /// channels stay outside 0...1; `Point(rgb:)` only needs the hue and chroma.
    public init(displayP3 r: Double, _ g: Double, _ b: Double) {
        let lr = Self.linear(r), lg = Self.linear(g), lb = Self.linear(b)
        self.init(
            r: Self.encodedUnclamped(1.2249401 * lr - 0.2249404 * lg),
            g: Self.encodedUnclamped(-0.0420569 * lr + 1.0420571 * lg),
            b: Self.encodedUnclamped(-0.0196376 * lr - 0.0786361 * lg + 1.0982735 * lb))
    }

    private static func encodedUnclamped(_ c: Double) -> Double {
        c < 0 ? -encoded(-c) : encoded(c)
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
