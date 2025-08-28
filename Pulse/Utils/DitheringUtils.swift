import SwiftUI
import CoreGraphics

// MARK: - DitheredGradientView (async + cached)
// Uses a renderer to generate a dithered image off the main thread; falls back to SwiftUI gradient.
struct DitheredGradientView: View {
    let gradient: SpaceGradient
    @StateObject private var renderer = DitheredGradientRenderer()

    var body: some View {
        GeometryReader { proxy in
            let logicalSize = proxy.size
            #if canImport(AppKit)
            let scale = NSScreen.main?.backingScaleFactor ?? 1.0
            #else
            let scale = 1.0
            #endif
            // Cap pixel count for performance (e.g., ~3MP)
            let maxPixels: Double = 3_000_000
            let targetPixels = Double(logicalSize.width * logicalSize.height) * Double(scale * scale)
            let downscale = targetPixels > maxPixels ? sqrt(maxPixels / max(targetPixels, 1)) : 1.0
            let renderScale = scale * downscale
            let renderSize = CGSize(width: logicalSize.width * renderScale, height: logicalSize.height * renderScale)

            ZStack {
                // Fallback gradient always available (also when we heuristically skip dithering)
                let pts = Self.linePoints(angle: gradient.angle)
                Rectangle()
                    .fill(LinearGradient(gradient: Gradient(stops: Self.stops(gradient)), startPoint: pts.start, endPoint: pts.end))

                if let image = renderer.image {
                    Image(decorative: image, scale: renderScale, orientation: .up)
                        .resizable()
                        .scaledToFill()
                }
            }
            .onAppear {
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale)
            }
            .onChange(of: gradient) { g in
                renderer.update(gradient: g, size: renderSize, scale: renderScale)
            }
            .onChange(of: logicalSize) { _ in
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale)
            }
        }
    }

    private static func stops(_ g: SpaceGradient) -> [Gradient.Stop] {
        var mapped: [Gradient.Stop] = g.sortedNodes.map { node in
            Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
        }
        if mapped.count == 0 {
            let def = SpaceGradient.default
            mapped = def.sortedNodes.map { Gradient.Stop(color: Color(hex: $0.colorHex), location: CGFloat($0.location)) }
        } else if mapped.count == 1 {
            let single = mapped[0]
            mapped = [Gradient.Stop(color: single.color, location: 0.0), Gradient.Stop(color: single.color, location: 1.0)]
        }
        return mapped
    }

    private static func linePoints(angle: Double) -> (start: UnitPoint, end: UnitPoint) {
        let theta = Angle(degrees: angle).radians
        let dx = cos(theta)
        let dy = sin(theta)
        let start = UnitPoint(x: 0.5 - 0.5 * dx, y: 0.5 - 0.5 * dy)
        let end = UnitPoint(x: 0.5 + 0.5 * dx, y: 0.5 + 0.5 * dy)
        return (start, end)
    }
}

// MARK: - Dithering
// Heuristic to skip dithering when banding is unlikely (3+ stops or very noisy/short ramps)
private func shouldSkipDithering(_ gradient: SpaceGradient) -> Bool {
    let nodes = gradient.nodes.isEmpty ? SpaceGradient.default.nodes : gradient.nodes
    if nodes.count >= 3 { return true }
    // Compute max per-channel delta as a simple banding risk metric
    #if canImport(AppKit)
    func rgba(_ hex: String) -> (Double, Double, Double, Double) {
        let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
    if nodes.count >= 2 {
        let a = rgba(nodes.first!.colorHex)
        let b = rgba(nodes.last!.colorHex)
        let maxDelta = max(abs(a.0-b.0), max(abs(a.1-b.1), abs(a.2-b.2)))
        // Small ramps are less likely to band noticeably
        if maxDelta < 0.05 { return true }
    }
    #endif
    return false
}

func generateDitheredGradient(gradient: SpaceGradient, size: CGSize) -> CGImage? {
    // Use default nodes when empty
    let nodes = gradient.nodes.isEmpty ? SpaceGradient.default.nodes : gradient.nodes
    // Heuristic fast-path: skip in low-risk cases
    if shouldSkipDithering(gradient) { return nil }
    let width = max(1, Int(size.width.rounded()))
    let height = max(1, Int(size.height.rounded()))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8

    guard let ctx = CGContext(data: nil,
                              width: width,
                              height: height,
                              bitsPerComponent: bitsPerComponent,
                              bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // First: draw the gradient into the bitmap using Core Graphics (no per-pixel hex conversions)
    drawLinearGradientCG(gradientNodes: nodes, angle: gradient.angle, width: width, height: height, context: ctx)

    guard let buffer = ctx.data else { return ctx.makeImage() }
    let ptr = buffer.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

    // Build 4x4 Bayer matrix scaled to [0,1]
    let bayer = bayerMatrix4x4()

    // Quantization strength driven by grain in [0,1]
    let strength = max(0.0, min(1.0, gradient.grain))
    // When strength == 0, disable dithering; otherwise map to 2..16 levels
    let levels = strength <= 0.0001 ? 0 : Int(ceil(2 + 14 * strength))
    if levels == 0 { return ctx.makeImage() }

    for y in 0..<height {
        for x in 0..<width {
            let idx = (y * width + x) * bytesPerPixel
            let b = Double(ptr[idx + 0]) / 255.0
            let g = Double(ptr[idx + 1]) / 255.0
            let r = Double(ptr[idx + 2]) / 255.0
            let a = Double(ptr[idx + 3]) / 255.0
            let th = bayer[y & 3][x & 3]
            let rq = ditherQuantize(r, levels: levels, threshold: th)
            let gq = ditherQuantize(g, levels: levels, threshold: th)
            let bq = ditherQuantize(b, levels: levels, threshold: th)
            ptr[idx + 2] = UInt8(min(255, max(0, Int(round(rq * 255)))))
            ptr[idx + 1] = UInt8(min(255, max(0, Int(round(gq * 255)))))
            ptr[idx + 0] = UInt8(min(255, max(0, Int(round(bq * 255)))))
            ptr[idx + 3] = UInt8(min(255, max(0, Int(round(a * 255)))))
        }
    }

    return ctx.makeImage()
}

private func ditherQuantize(_ v: Double, levels: Int, threshold: Float) -> Double {
    let lv = max(2, levels)
    let step = 1.0 / Double(lv - 1) // quantization step
    // Bias by threshold in [-0.5, 0.5] scaled by half-step
    let bias = Double(threshold - 0.5) * step
    let q = (v + bias) / step
    let iq = round(q)
    return min(1.0, max(0.0, iq * step))
}

func bayerMatrix4x4() -> [[Float]] {
    // Classic 4x4 Bayer matrix, normalized to [0,1]
    let m: [[Float]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5]
    ]
    let scale: Float = 1.0 / 16.0
    return m.map { row in row.map { ($0 + 0.5) * scale } }
}

// Provided for API completeness if future callers want to dither arbitrary images
func applyOrderedDithering(to image: CGImage, using matrix: [[Float]]) -> CGImage? {
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8

    guard let ctx = CGContext(data: nil,
                              width: width,
                              height: height,
                              bitsPerComponent: bitsPerComponent,
                              bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return nil }
    let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let idx = (y * width + x) * bytesPerPixel
            let r = Double(ptr[idx + 2]) / 255.0
            let g = Double(ptr[idx + 1]) / 255.0
            let b = Double(ptr[idx + 0]) / 255.0
            let a = Double(ptr[idx + 3]) / 255.0
            let th = matrix[y & 3][x & 3]
            let levels = 8
            let rq = ditherQuantize(r, levels: levels, threshold: th)
            let gq = ditherQuantize(g, levels: levels, threshold: th)
            let bq = ditherQuantize(b, levels: levels, threshold: th)
            ptr[idx + 2] = UInt8(min(255, max(0, Int(round(rq * 255)))))
            ptr[idx + 1] = UInt8(min(255, max(0, Int(round(gq * 255)))))
            ptr[idx + 0] = UInt8(min(255, max(0, Int(round(bq * 255)))))
            ptr[idx + 3] = UInt8(min(255, max(0, Int(round(a * 255)))))
        }
    }

    return ctx.makeImage()
}

// MARK: - CoreGraphics gradient rendering helper
private func drawLinearGradientCG(gradientNodes: [GradientNode], angle: Double, width: Int, height: Int, context ctx: CGContext) {
    #if canImport(AppKit)
    // Normalize nodes for CGGradient input
    var nodes = gradientNodes.sorted { $0.location < $1.location }
    if nodes.isEmpty {
        nodes = SpaceGradient.default.nodes
    } else if nodes.count == 1 {
        let n = nodes[0]
        nodes = [GradientNode(id: n.id, colorHex: n.colorHex, location: 0.0), GradientNode(colorHex: n.colorHex, location: 1.0)]
    }

    var colors: [CGColor] = []
    var locations: [CGFloat] = []
    colors.reserveCapacity(nodes.count)
    locations.reserveCapacity(nodes.count)
    for n in nodes {
        let ns = NSColor(Color(hex: n.colorHex)).usingColorSpace(.sRGB) ?? .black
        colors.append(ns.cgColor)
        locations.append(CGFloat(n.location))
    }
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }

    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let theta = CGFloat(Angle(degrees: angle).radians)
    let dx = cos(theta)
    let dy = sin(theta)
    // Convert UnitPoint logic to pixel coordinates
    let sx = 0.5 - 0.5 * dx
    let sy = 0.5 - 0.5 * dy
    let ex = 0.5 + 0.5 * dx
    let ey = 0.5 + 0.5 * dy
    let start = CGPoint(x: bounds.minX + bounds.width * sx, y: bounds.minY + bounds.height * sy)
    let end = CGPoint(x: bounds.minX + bounds.width * ex, y: bounds.minY + bounds.height * ey)
    ctx.saveGState()
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
    ctx.restoreGState()
    #endif
}

// MARK: - Renderer with caching and background generation
final class DitheredGradientRenderer: ObservableObject {
    @Published var image: CGImage?
    private var workItem: DispatchWorkItem?
    private static var cache = NSCache<NSString, CGImage>()

    func update(gradient: SpaceGradient, size: CGSize, scale: Double) {
        // Debounce rapid updates
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            let key = self?.cacheKey(gradient: gradient, size: size)
            if let key = key, let cached = Self.cache.object(forKey: key as NSString) {
                DispatchQueue.main.async { self?.image = cached }
                return
            }
            let img = generateDitheredGradient(gradient: gradient, size: size)
            if let img, let key = key {
                Self.cache.setObject(img, forKey: key as NSString)
            }
            DispatchQueue.main.async { self?.image = img }
        }
        workItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.02, execute: item)
    }

    private func cacheKey(gradient: SpaceGradient, size: CGSize) -> String {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        var hasher = Hasher()
        hasher.combine(gradient)
        hasher.combine(w)
        hasher.combine(h)
        return String(hasher.finalize())
    }
}
