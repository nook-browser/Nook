// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconTint.swift
//  NookWeb
//
//  An icon's main colors, for lighting a selected favorite with its own color as Arc does:
//  one for a one-color icon (Claude's orange), a few around the wheel for a many-colored one
//  (Gemini). Gray icons have none. CoreGraphics only; `Checks/FaviconTintCheck.swift` runs it.
//

import CoreGraphics

public enum FaviconTint {
    public struct Swatch: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    private static let side = 32
    private static let bins = 12

    /// Up to three colors in hue order, or empty for an icon with too little color to light anything.
    public static func swatches(from image: CGImage) -> [Swatch] {
        let n = side
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let context = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Saturated pixels by hue bin, with their summed color so each bin's color is its own average.
        var weight = [Double](repeating: 0, count: bins)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: bins)
        var opaque = 0
        for i in 0 ..< n * n {
            let a = Double(pixels[i * 4 + 3]) / 255
            guard a > 0.5 else { continue }
            opaque += 1
            let r = Double(pixels[i * 4]) / 255 / a, g = Double(pixels[i * 4 + 1]) / 255 / a, b = Double(pixels[i * 4 + 2]) / 255 / a
            let high = max(r, g, b), low = min(r, g, b), chroma = high - low
            guard chroma > 0.2 else { continue }
            var hue: Double
            if high == r { hue = (g - b) / chroma } else if high == g { hue = (b - r) / chroma + 2 } else { hue = (r - g) / chroma + 4 }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bin = min(Int(hue * Double(bins)), bins - 1)
            weight[bin] += chroma
            sums[bin].0 += r * chroma; sums[bin].1 += g * chroma; sums[bin].2 += b * chroma
        }
        let total = weight.reduce(0, +)
        // Under a twentieth of the icon in color: a gray icon with a speck, nothing to light.
        guard opaque > 0, total / Double(opaque) > 0.05 else { return [] }

        return weight.indices
            .filter { weight[$0] / total > 0.12 }
            .sorted { weight[$0] > weight[$1] }
            .prefix(3)
            .sorted()
            .map { bin in
                let w = weight[bin]
                return Swatch(red: min(sums[bin].0 / w, 1), green: min(sums[bin].1 / w, 1), blue: min(sums[bin].2 / w, 1))
            }
    }
}
