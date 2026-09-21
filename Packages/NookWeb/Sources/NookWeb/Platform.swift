// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI
import WebKit

#if canImport(AppKit)
@_exported import MuteableWKWebView
import AppKit
import CoreAudio

public enum PlatformUserAgent {
    /// Desktop Safari, so sites serve what they serve Safari on a Mac.
    public static let custom: String? =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"

    /// The installed Safari's version, which is the system WebKit's: sites gate features on it
    /// (Google Docs at 26.4). Safari can run ahead of the OS, so the OS version is only the fallback.
    public static let safariVersion: String = {
        let installed = Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String
        return installed.flatMap(versionToken) ?? osVersion
    }()
}

extension WKWebView {
    /// AppKit's web view takes this through KVC only.
    public func setDrawsPageBackground(_ draws: Bool) { setValue(draws, forKey: "drawsBackground") }
}

/// The default-output-device listener PageSession keeps; see PageSession+AudioDevice+macOS.swift.
public typealias AudioDeviceListenerProc = AudioObjectPropertyListenerProc

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

public enum PlatformUserAgent {
    /// nil keeps WebKit's own iPhone or iPad string, completed by applicationNameForUserAgent
    /// in BrowserConfig+iOS.swift.
    public static let custom: String? = nil

    /// Safari ships with iOS, so its version is the system's.
    public static let safariVersion: String = osVersion
}

/// Never installed on iOS; the type exists so PageSession's stored property compiles.
public typealias AudioDeviceListenerProc = @convention(c) () -> Void

extension WKWebView {
    /// Page muting is the macOS-only MuteableWKWebView target; a phone has one audible page.
    public var isMuted: Bool { get { false } set {} }
    /// Pinch zoom is built into UIKit's web view; the AppKit switch has no counterpart.
    public var allowsMagnification: Bool { get { true } set {} }
    /// UIKit's origin is top-left, which is what AppKit calls flipped.
    public var isFlipped: Bool { true }
    /// UIKit has no drawsBackground key; opacity is the nearest control.
    public func setDrawsPageBackground(_ draws: Bool) { isOpaque = draws }
}

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

extension PlatformUserAgent {
    /// "26.0" or "26.0.1", the way Safari writes it.
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    /// A version fit for a header: digits and dots only, or nil.
    static func versionToken(_ raw: String) -> String? {
        let ok = raw.first?.isNumber == true && raw.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
        return ok ? raw : nil
    }
}
