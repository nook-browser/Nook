// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct AppColors {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    static let background = Color(nsColor: .windowBackgroundColor)
    static let backgroundSecondary = Color(nsColor: .underPageBackgroundColor)

}

extension Color {
    func toHexString(includeAlpha: Bool = false) -> String? {
        let ns = NSColor(self)
        return ns.toHexString(includeAlpha: includeAlpha)
    }
    
    var perceivedBrightness: CGFloat {
            guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return 0.5 }
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)

            if a <= 0.01 { return 1.0 }

            let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
            return brightness * a + (1 - a)
        }

        var isPerceivedDark: Bool {
            perceivedBrightness < 0.6
        }
}

extension NSColor {
    func toHexString(includeAlpha: Bool = false) -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        if includeAlpha {
            let ai = Int(round(a * 255))
            return String(format: "#%02X%02X%02X%02X", ai, ri, gi, bi)
        } else {
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
    }

    var perceivedBrightness: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0.5 }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)

        if a <= 0.01 { return 1.0 }

        let brightness = (0.299 * r + 0.587 * g + 0.114 * b)
        return brightness * a + (1 - a)
    }

    var isPerceivedDark: Bool {
        perceivedBrightness < 0.6
    }
}

extension NSColor {
    /// `#RRGGBB` or `RRGGBB`; nil for anything else.
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else { return nil }

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
