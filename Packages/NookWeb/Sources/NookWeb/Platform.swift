@_exported import MuteableWKWebView

import SwiftUI

#if canImport(AppKit)
import AppKit

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension PlatformImage {
    /// PNG encoding, for the favicon disk cache.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

extension Color {
    init(platformColor: PlatformColor) { self.init(nsColor: platformColor) }
}

extension PlatformColor {
    /// Fallback when a space's accent hex will not parse.
    static var defaultAccent: PlatformColor { .controlAccentColor }
}
#else
import UIKit

public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}

extension Color {
    init(platformColor: PlatformColor) { self.init(uiColor: platformColor) }
}

extension PlatformColor {
    /// Fallback when a space's accent hex will not parse.
    static var defaultAccent: PlatformColor { .tintColor }
}
#endif

extension PlatformColor {
    /// `#RRGGBB` or `RRGGBB`; nil for anything else.
    static func fromHex(_ hex: String) -> PlatformColor? {
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
