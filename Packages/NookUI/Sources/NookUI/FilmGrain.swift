// Licensed under GPL-3.0. See LICENSE.
//
//  FilmGrain.swift
//  NookUI
//
//  The four noise textures of a space theme (grain, sand, denim, tweed): each made once with
//  Core Image as black and white specks of varying alpha, so tiling it over a color adds texture
//  without graying the color, and drawn one texture pixel to one screen pixel.
//

import CoreImage
import Foundation
import SwiftUI
import NookTabsCore

public struct FilmGrain: View {
    let opacity: Double
    let overlay: SpaceTheme.Overlay
    let blend: BlendMode
    let scale: CGFloat?
    @Environment(\.displayScale) private var displayScale
    @State private var tile: CGImage?

    /// `scale` overrides the display's backing scale, so a noise pixel lands on a screen pixel;
    /// an export rendered at 2x passes 2. A theme's chrome passes `.normal`.
    public init(opacity: Double, overlay: SpaceTheme.Overlay = .grain, blend: BlendMode = .softLight, scale: CGFloat? = nil) {
        self.opacity = opacity
        self.overlay = overlay
        self.blend = blend
        self.scale = scale
    }

    public var body: some View {
        Group {
            if let tile = tile ?? Self.cache.tile(overlay) {
                Image(decorative: tile, scale: scale ?? displayScale)
                    .resizable(resizingMode: .tile)
                    .blendMode(blend)
                    .opacity(opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: overlay) { tile = await Self.cache.load(overlay) }
    }

    /// Textures are made off the main thread, once each; nothing draws until one is ready.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var tiles: [SpaceTheme.Overlay: CGImage] = [:]

        func tile(_ overlay: SpaceTheme.Overlay) -> CGImage? {
            lock.lock(); defer { lock.unlock() }
            return tiles[overlay]
        }

        func load(_ overlay: SpaceTheme.Overlay) async -> CGImage? {
            if let cached = tile(overlay) { return cached }
            let made = await Task.detached(priority: .utility) { FilmGrain.make(overlay) }.value
            if let made { lock.lock(); tiles[overlay] = made; lock.unlock() }
            return made
        }
    }

    private static let cache = Cache()

    // Texture sizes follow Arc's assets (grain 155, sand 96, denim 300, tweed 128) at 2x.
    nonisolated private static func make(_ overlay: SpaceTheme.Overlay) -> CGImage? {
        let size: Int
        let gray: CIImage
        guard let infinite = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        // One tile of noise repeated forever: a blur of it is periodic, so the cropped center tiles seamlessly.
        func wrapped(_ size: Int) -> CIImage {
            infinite.cropped(to: CGRect(x: 0, y: 0, width: size, height: size)).applyingFilter("CIAffineTile")
        }
        let random = infinite
        switch overlay {
        case .grain:
            size = 256
            gray = random.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.35])
        case .sand:
            // Clumped speckle: noise blurred a little, then pushed back to full contrast.
            size = 192
            gray = wrapped(size)
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 3])
        case .denim:
            // A diagonal twill: noise smeared along 45 degrees.
            size = 300
            gray = wrapped(size)
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 5, kCIInputAngleKey: Double.pi / 4])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 3.5])
        case .tweed:
            // A woven check: two stripe sets crossed, roughened by noise. 4 px stripes divide the tile.
            size = 128
            let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
                "inputWidth": 4, "inputSharpness": 0.8,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
            ])?.outputImage ?? random
            let across = stripes.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
            let weave = stripes.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: across])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.4])
            let rough = random.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.2])
            gray = weave.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: rough])
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.35, kCIInputContrastKey: 1.5])
        }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let rowBytes = size * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * size)
        CIContext(options: [.useSoftwareRenderer: false]).render(
            gray.cropped(to: rect).settingAlphaOne(in: rect), toBitmap: &pixels, rowBytes: rowBytes, bounds: rect,
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // Above middle gray becomes white, below black, with alpha growing away from the middle.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let g = Double(pixels[i]) / 255
            let alpha = min(1, abs(g - 0.5) * 2)
            let value = g > 0.5 ? alpha : 0
            pixels[i] = UInt8(value * 255); pixels[i + 1] = pixels[i]; pixels[i + 2] = pixels[i]
            pixels[i + 3] = UInt8(alpha * 255)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
