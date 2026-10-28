// Licensed under GPL-3.0. See LICENSE.
//
//  FilmGrain.swift
//  NookUI
//
//  Film grain: one tile of fine monochrome noise, made once with Core Image and drawn one
//  noise pixel to one screen pixel, so it reads as grain rather than a tiled dot pattern.
//

import CoreImage
import SwiftUI

public struct FilmGrain: View {
    let opacity: Double
    let scale: CGFloat

    /// `scale` is the display's backing scale, so a noise pixel lands on a screen pixel; an
    /// export rendered at 2x passes 2.
    public init(opacity: Double, scale: CGFloat = 2) {
        self.opacity = opacity
        self.scale = scale
    }

    public var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: scale)
                .resizable(resizingMode: .tile)
                // Soft light lifts and sinks the colors under it the way grain does; overlay
                // went harsh on dark backdrops.
                .blendMode(.softLight)
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 256 px of gray noise with a mild contrast boost; made on first use and kept.
    @MainActor private static let tile: CGImage? = {
        let size = 256
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let gray = random
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.35,
            ])
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(gray, from: CGRect(x: 0, y: 0, width: size, height: size))
    }()
}
