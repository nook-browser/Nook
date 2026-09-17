@_exported import MuteableWKWebView

import SwiftUI

#if canImport(AppKit)
import AppKit

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension PlatformImage {
    /// PNG encoding, for the favicon disk cache.
    public func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension Image {
    public init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

extension Color {
    public init(platformColor: PlatformColor) { self.init(nsColor: platformColor) }
}

extension PlatformColor {
    /// Fallback when a space's accent hex will not parse.
    public static var defaultAccent: PlatformColor { .controlAccentColor }
}

extension PlatformImage {
    var singlePixelCGImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#else
import UIKit

public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor

extension Image {
    public init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}

extension Color {
    public init(platformColor: PlatformColor) { self.init(uiColor: platformColor) }
}

extension PlatformColor {
    /// Fallback when a space's accent hex will not parse.
    public static var defaultAccent: PlatformColor { .tintColor }
}

extension PlatformImage {
    var singlePixelCGImage: CGImage? { cgImage }
}
#endif

extension PlatformImage {
    /// The colour of a 1x1 snapshot, used to sample a page's background.
    public var singlePixelColor: PlatformColor? {
        guard let cgImage = singlePixelCGImage else { return nil }
        
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
        
        return PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}



extension PlatformColor {
    /// `#RRGGBB` or `RRGGBB`; nil for anything else.
    public static func fromHex(_ hex: String) -> PlatformColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: text).scanHexInt64(&rgb) else { return nil }
        return PlatformColor(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
