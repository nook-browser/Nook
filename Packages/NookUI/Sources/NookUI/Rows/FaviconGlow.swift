// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconGlow.swift
//  NookUI
//
//  The blurred favicon behind a favorite tile and in its selection ring, as Arc draws it.
//  Rendered once per host off the main actor and kept in a small cache.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import NookDesign
import NookWeb

actor FaviconGlow {
    static let shared = FaviconGlow()

    private let limit = 64
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []
    private let context = CIContext()

    /// A blurred copy of the host's cached favicon, enlarged to fill a tile; nil without an icon.
    func image(forHost host: String) async -> CGImage? {
        if let hit = cache[host] { return hit }
        guard let icon = await FaviconCache.shared.cachedImage(for: host),
              let source = Self.cgImage(icon), let glow = render(source) else { return nil }
        cache[host] = glow
        order.append(host)
        if order.count > limit { cache[order.removeFirst()] = nil }
        return glow
    }

    private func render(_ source: CGImage) -> CGImage? {
        let side = NookDesign.Size.favoriteTile * NookDesign.Size.favoriteGlowScale
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let input = CIImage(cgImage: source)
        let fill = max(side / input.extent.width, side / input.extent.height)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        let centered = scaled.transformed(by: CGAffineTransform(
            translationX: (side - scaled.extent.width) / 2 - scaled.extent.minX,
            y: (side - scaled.extent.height) / 2 - scaled.extent.minY))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = centered.clampedToExtent()
        blur.radius = Float(side * NookDesign.Size.favoriteGlowBlur)
        guard let out = blur.outputImage else { return nil }
        return context.createCGImage(out, from: rect)
    }

    private static func cgImage(_ image: PlatformImage) -> CGImage? {
        #if os(macOS)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        image.cgImage
        #endif
    }
}
