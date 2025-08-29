import Foundation
import SwiftUI

// MARK: - Color Interpolation
// Returns hex string in ARGB format when alpha is present (supported by Color(hex:)).
func interpolateColor(from: String, to: String, progress: Double) -> String {
    let c1 = Color(hex: from)
    let c2 = Color(hex: to)

    #if canImport(AppKit)
    let n1 = NSColor(c1).usingColorSpace(.sRGB) ?? .black
    let n2 = NSColor(c2).usingColorSpace(.sRGB) ?? .black
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    n1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    n2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

    let t = CGFloat(min(1, max(0, progress)))
    let r = r1 + (r2 - r1) * t
    let g = g1 + (g2 - g1) * t
    let b = b1 + (b2 - b1) * t
    let a = a1 + (a2 - a1) * t
    let out = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    // Preserve alpha for semi-transparent gradient stops (#AARRGGBB)
    return out.toHexString(includeAlpha: true) ?? from
    #else
    // Fallback: without AppKit, just return target when progress > .5
    return progress < 0.5 ? from : to
    #endif
}

// MARK: - Angle Interpolation (shortest path)
func interpolateAngle(from: Double, to: Double, progress: Double) -> Double {
    let a = fmod(from, 360.0)
    let b = fmod(to, 360.0)
    var delta = b - a
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }
    let t = min(1, max(0, progress))
    var res = a + delta * t
    // Normalize to [0, 360)
    res = res.truncatingRemainder(dividingBy: 360)
    if res < 0 { res += 360 }
    return res
}

// Sample a color hex at a given position [0,1] within a gradient node array
func colorAt(position: Double, nodes: [GradientNode]) -> String {
    let clamped = min(1, max(0, position))
    let sorted = nodes.sorted { $0.location < $1.location }
    if sorted.isEmpty { return "#00000000" }
    if clamped <= sorted.first!.location { return sorted.first!.colorHex }
    if clamped >= sorted.last!.location { return sorted.last!.colorHex }
    for i in 0..<(sorted.count - 1) {
        let a = sorted[i]
        let b = sorted[i + 1]
        if clamped >= a.location && clamped <= b.location {
            let denom = max(1e-6, b.location - a.location)
            let localT = (clamped - a.location) / denom
            return interpolateColor(from: a.colorHex, to: b.colorHex, progress: localT)
        }
    }
    return sorted.last!.colorHex
}
