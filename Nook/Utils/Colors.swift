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
    static let controlBackgroundHover = Color.gray.opacity(0.8)
    static let controlBackgroundHoverLight = Color.gray.opacity(0.2)
    static let controlBackgroundActive = Color.white.opacity(0.3)
    static let activeTab = Color.white.opacity(1.0)
    static let inactiveTab = Color(nsColor: .controlBackgroundColor).opacity(0.1)
    
    
    
    static let iconActiveLight = Color.white.opacity(0.6)
    static let iconDisabledLight = Color.white.opacity(0.25)
    static let iconHoverLight = Color.white.opacity(0.1)
    
    static let iconActiveDark = Color.black.opacity(0.55)
    static let iconDisabledDark = Color.black.opacity(0.15)
    static let iconHoverDark = Color.black.opacity(0.1)
    
    static let spaceTabActiveLight = Color.white.opacity(0.2)
    static let spaceTabHoverLight = Color.white.opacity(0.1)
    static let spaceTabTextLight = Color(hex: "EAE6DC")
    
    static let spaceTabActiveDark = Color.white
    static let spaceTabHoverDark = Color.black.opacity(0.05)
    static let spaceTabTextDark = Color(hex: "001E21")
    
    
    static let pinnedTabActiveLight = Color.white.opacity(0.2)
    static let pinnedTabHoverLight = Color.white.opacity(0.15)
    static let pinnedTabIdleLight = Color.white.opacity(0.1)
    
    static let pinnedTabActiveDark = Color.white
    static let pinnedTabHoverDark = Color.black.opacity(0.1)
    static let pinnedTabIdleDark = Color.black.opacity(0.05)
    
    
    static let sidebarTextLight = Color.white.opacity(0.5)
    static let sidebarTextDark = Color.black.opacity(0.5)
    
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

extension NSImage {
    var singlePixelColor: NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Create a bitmap context to read pixel data
        let width = 1
        let height = 1
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        var pixelData: [UInt8] = [0, 0, 0, 0]
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Draw the image into the context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Extract RGB values (pixelData is RGBA format with premultipliedLast)
        let red = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let blue = CGFloat(pixelData[2]) / 255.0
        let alpha = CGFloat(pixelData[3]) / 255.0
        
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

