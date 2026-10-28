// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/FaviconTint.swift Packages/NookWeb/Checks/FaviconTintCheck.swift -o /tmp/ft && /tmp/ft

import CoreGraphics

/// A 32 px icon of vertical stripes in `colors`, on nothing.
func stripes(_ colors: [CGColor]) -> CGImage {
    let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let width = 32 / colors.count
    for (index, color) in colors.enumerated() {
        context.setFillColor(color)
        context.fill(CGRect(x: index * width, y: 0, width: width, height: 32))
    }
    return context.makeImage()!
}

@main
struct FaviconTintCheck {
    static func main() {
        let orange = CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        let blue = CGColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1)
        let pink = CGColor(red: 0.9, green: 0.3, blue: 0.6, alpha: 1)
        let gray = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)

        // Claude: one color, and it is that color (within the drawing color space's conversion).
        let claude = FaviconTint.swatches(from: stripes([orange]))
        precondition(claude.count == 1 && abs(claude[0].red - 0.85) < 0.06 && abs(claude[0].blue - 0.34) < 0.1, "\(claude)")

        // Gemini-like: several colors, in hue order (orange, blue, pink).
        let many = FaviconTint.swatches(from: stripes([blue, orange, pink]))
        precondition(many.count == 3 && many[0].red > 0.8 && many[1].blue > 0.9, "\(many)")

        // Gray icons light nothing.
        precondition(FaviconTint.swatches(from: stripes([gray])).isEmpty)
        print("FaviconTintCheck passed")
    }
}
