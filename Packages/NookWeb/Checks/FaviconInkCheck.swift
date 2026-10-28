// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/FaviconInk.swift Packages/NookWeb/Checks/FaviconInkCheck.swift -o /tmp/fi && /tmp/fi

import CoreGraphics

/// Draws a 64 px icon: an optional backdrop shape, then a glyph square in the middle.
func icon(backdrop: CGColor?, round: Bool, glyph: CGColor) -> CGImage {
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let backdrop {
        context.setFillColor(backdrop)
        if round { context.fillEllipse(in: CGRect(x: 0, y: 0, width: 64, height: 64)) } else { context.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
    }
    context.setFillColor(glyph)
    context.fill(CGRect(x: 20, y: 20, width: 24, height: 24))
    return context.makeImage()!
}

func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    return context.data!.assumingMemoryBound(to: UInt8.self)[(y * 64 + x) * 4 + 3]
}

@main
struct FaviconInkCheck {
    static func main() {
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let orange = CGColor(red: 0.85, green: 0.45, blue: 0.3, alpha: 1)

        // ChatGPT: black glyph on a white disc. The disc drops out, the glyph stays.
        let chatGPT = FaviconInk.glyph(from: icon(backdrop: white, round: true, glyph: black))!
        precondition(alpha(chatGPT, x: 32, y: 32) > 240, "glyph kept")
        precondition(alpha(chatGPT, x: 32, y: 8) < 15, "disc dropped")

        // GitHub: a black shape on nothing becomes the shape.
        let github = FaviconInk.glyph(from: icon(backdrop: nil, round: false, glyph: black))!
        precondition(alpha(github, x: 32, y: 32) > 240 && alpha(github, x: 4, y: 4) == 0)

        // Kimi: a full-bleed tile is an app icon and stays as drawn.
        precondition(FaviconInk.glyph(from: icon(backdrop: white, round: false, glyph: black)) == nil)

        // Claude: color is never touched.
        precondition(FaviconInk.glyph(from: icon(backdrop: nil, round: false, glyph: orange)) == nil)

        print("FaviconInkCheck passed")
    }
}
