import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct AppColors {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let textQuaternary = Color(nsColor: .quaternaryLabelColor)

    static let background = Color(nsColor: .windowBackgroundColor)
    static let backgroundSecondary = Color(nsColor: .underPageBackgroundColor)

    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let controlBackgroundHover = Color(nsColor: .controlColor)
    static let controlBackgroundActive = Color.white.opacity(0.3)
    static let activeTab = Color.white.opacity(1.0)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (
                int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF
            )
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    #if canImport(AppKit)
    func toHexString(includeAlpha: Bool = false) -> String? {
        let ns = NSColor(self)
        return ns.toHexString(includeAlpha: includeAlpha)
    }
    #endif
}

#if canImport(AppKit)
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
}
#endif
