// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconInk.swift
//  NookWeb
//
//  Black-and-white favicons drawn as Arc draws them: as a glyph in the text color, so a black
//  logo on a white disc (ChatGPT) or on nothing (GitHub, X) reads in dark mode too. Colored
//  icons, and gray ones that fill their square like an app icon (Kimi), are left alone.
//  CoreGraphics only; `Checks/FaviconInkCheck.swift` runs it on drawn images.
//

import CoreGraphics

public enum FaviconInk {
    private static let side = 64

    /// The glyph as white with its own alpha, for template drawing; nil to keep the icon as is.
    public static func glyph(from image: CGImage) -> CGImage? {
        let n = side
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let context = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Unpremultiplied luminance and alpha per pixel; any real color rules the icon out.
        var luminance = [Double](repeating: 0, count: n * n)
        var alpha = [Double](repeating: 0, count: n * n)
        var opaque = 0, colored = 0, light = 0, dark = 0
        for i in 0 ..< n * n {
            let a = Double(pixels[i * 4 + 3]) / 255
            alpha[i] = a
            guard a > 0.1 else { continue }
            let r = Double(pixels[i * 4]) / 255 / a, g = Double(pixels[i * 4 + 1]) / 255 / a, b = Double(pixels[i * 4 + 2]) / 255 / a
            if max(r, g, b) - min(r, g, b) > 0.12 { colored += 1 }
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luminance[i] = l
            opaque += 1
            if l > 0.6 { light += 1 } else if l < 0.4 { dark += 1 }
        }
        guard opaque > n * n / 20, Double(colored) / Double(opaque) < 0.03 else { return nil }

        // An icon whose corners are filled is a tile (an app icon); it already reads on any background.
        let inset = n / 16
        let corners = [(inset, inset), (n - 1 - inset, inset), (inset, n - 1 - inset), (n - 1 - inset, n - 1 - inset)]
        guard corners.filter({ alpha[$0.1 * n + $0.0] > 0.5 }).count < 2 else { return nil }

        // Two tones (a logo on a disc): the commoner tone is the backdrop and drops out, the other
        // is the ink. One tone (a logo on nothing): the shape itself is the ink.
        let twoTone = Double(light) / Double(opaque) > 0.08 && Double(dark) / Double(opaque) > 0.08
        let backdrop = light >= dark ? 1.0 : 0.0
        var ink = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0 ..< n * n {
            let strength = twoTone ? min(abs(luminance[i] - backdrop) / 0.6, 1) : 1
            let value = UInt8((alpha[i] * strength * 255).rounded())
            // Premultiplied white: color equals alpha.
            ink[i * 4] = value; ink[i * 4 + 1] = value; ink[i * 4 + 2] = value; ink[i * 4 + 3] = value
        }
        return ink.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
    }
}
