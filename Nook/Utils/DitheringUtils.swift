import SwiftUI
import CoreGraphics
import simd

// MARK: - Backing scale environment
private struct BackingScaleKey: EnvironmentKey {
    static var defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var backingScale: CGFloat {
        get { self[BackingScaleKey.self] }
        set { self[BackingScaleKey.self] = newValue }
    }
}

#if canImport(AppKit)
private final class BackingScaleNSView: NSView {
    var onScaleChange: ((CGFloat) -> Void)?
    private var obs: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        update()
        registerNotifications()
    }

    deinit { unregisterNotifications() }

    private func registerNotifications() {
        unregisterNotifications()
        if let window = window {
            let center = NotificationCenter.default
            obs.append(center.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main) { [weak self] _ in self?.update() })
            obs.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in self?.update() })
        }
    }

    private func unregisterNotifications() {
        let center = NotificationCenter.default
        for o in obs { center.removeObserver(o) }
        obs.removeAll()
    }

    private func update() {
        let s = window?.screen?.backingScaleFactor ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        onScaleChange?(s)
    }
}

private struct BackingScaleReader: NSViewRepresentable {
    @Binding var scale: CGFloat
    func makeNSView(context: Context) -> BackingScaleNSView {
        let v = BackingScaleNSView()
        v.onScaleChange = { [weak v] s in
            if v != nil { scale = s }
        }
        return v
    }
    func updateNSView(_ nsView: BackingScaleNSView, context: Context) {}
}
#endif

private struct BackingScaleEnvironment<Content: View>: View {
    @ViewBuilder var content: () -> Content
    #if canImport(AppKit)
    @State private var scale: CGFloat = 1.0
    #endif
    var body: some View {
        #if canImport(AppKit)
        content()
            .background(BackingScaleReader(scale: $scale).frame(width: 0, height: 0))
            .environment(\.backingScale, scale)
        #else
        content().environment(\.backingScale, 1.0)
        #endif
    }
}

#if canImport(AppKit)
// MARK: - Cached color lookup for hex
fileprivate let _DitherColorCache = NSCache<NSString, NSColor>()
fileprivate func cachedNSColor(hex: String) -> NSColor {
    if let c = _DitherColorCache.object(forKey: hex as NSString) { return c }
    let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .black
    _DitherColorCache.setObject(ns, forKey: hex as NSString)
    return ns
}
#endif

// MARK: - DitheredGradientView (async + cached)
// Uses a renderer to generate a dithered image off the main thread; falls back to SwiftUI gradient.
struct DitheredGradientView: View {
    let gradient: SpaceGradient
    @StateObject private var renderer = DitheredGradientRenderer()
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.backingScale) private var backingScale

    var body: some View {
        BackingScaleEnvironment {
        GeometryReader { proxy in
            let logicalSize = proxy.size
            let scale = Double(backingScale)
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

                // Overlay the generated image only when not animating/editing,
                // so SwiftUI's fallback gradient can animate space transitions.
                if !(gradientColorManager.isAnimating || gradientColorManager.isEditing), let image = renderer.image {
                    Image(decorative: image, scale: renderScale, orientation: .up)
                        .resizable()
                        .scaledToFill()
                }
            }
            .onAppear {
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale, allowDithering: !(gradientColorManager.isAnimating || gradientColorManager.isEditing))
            }
            .onChange(of: gradient) { _, g in
                renderer.update(gradient: g, size: renderSize, scale: renderScale, allowDithering: !(gradientColorManager.isAnimating || gradientColorManager.isEditing))
            }
            .onChange(of: logicalSize) {
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale, allowDithering: !(gradientColorManager.isAnimating || gradientColorManager.isEditing))
            }
            .onChange(of: gradientColorManager.isAnimating) { _, anim in
                // When animation toggles off, generate the high-quality image
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale, allowDithering: !(anim || gradientColorManager.isEditing))
            }
            .onChange(of: gradientColorManager.isEditing) { _, editing in
                renderer.update(gradient: gradient, size: renderSize, scale: renderScale, allowDithering: !(gradientColorManager.isAnimating || editing))
            }
        }
        }
    }

    private static func stops(_ g: SpaceGradient) -> [Gradient.Stop] {
        var mapped: [Gradient.Stop] = g.sortedNodes.map { node in
            #if canImport(AppKit)
            let c = Color(nsColor: cachedNSColor(hex: node.colorHex))
            #else
            let c = Color(hex: node.colorHex)
            #endif
            return Gradient.Stop(color: c, location: CGFloat(node.location))
        }
        if mapped.count == 0 {
            let def = SpaceGradient.default
            mapped = def.sortedNodes.map {
                #if canImport(AppKit)
                Gradient.Stop(color: Color(nsColor: cachedNSColor(hex: $0.colorHex)), location: CGFloat($0.location))
                #else
                Gradient.Stop(color: Color(hex: $0.colorHex), location: CGFloat($0.location))
                #endif
            }
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
        let ns = cachedNSColor(hex: hex)
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

func generateDitheredGradient(gradient: SpaceGradient, size: CGSize, allowDithering: Bool) -> CGImage? {
    // Use default nodes when empty
    let nodes = gradient.nodes.isEmpty ? SpaceGradient.default.nodes : gradient.nodes
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

    // Triadic barycentric blend for 3 nodes
    if nodes.count == 3 {
        guard let buffer = ctx.data else { return ctx.makeImage() }
        let ptr = buffer.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

        #if canImport(AppKit)
        func rgba(_ hex: String) -> (Double, Double, Double, Double) {
            let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .black
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            ns.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b), Double(a))
        }
        #else
        func rgba(_ hex: String) -> (Double, Double, Double, Double) { return (1,1,1,1) }
        #endif

        let sorted = nodes.sorted { $0.location < $1.location }
        let cA = rgba(sorted[0].colorHex)
        let cB = rgba(sorted[1].colorHex)
        let cC = rgba(sorted[2].colorHex)

        // Anchor points (normalized 0..1)
        let inset: Double = 0.08 // controls lobe size by moving anchors inward
        let pA = SIMD2<Double>(inset, inset)            // top-left
        let pB = SIMD2<Double>(1.0 - inset, inset)      // top-right
        let pC = SIMD2<Double>(0.5, 1.0 - inset)        // bottom-center

        // Precompute for barycentric
        let v0 = pB - pA
        let v1 = pC - pA
        let d00 = simd_dot(v0, v0)
        let d01 = simd_dot(v0, v1)
        let d11 = simd_dot(v1, v1)
        let denom = (d00 * d11 - d01 * d01)

        // Ordered dithering (optional during editing)
        let bayer = bayerMatrix4x4()
        let grain = max(0.0, min(1.0, gradient.grain))
        let amplitude = (allowDithering ? (0.6 + 1.4 * grain) : 0.0) / 255.0

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * bytesPerPixel
                let nx = Double(x) / Double(max(1, width - 1))
                let ny = Double(y) / Double(max(1, height - 1))
                let p = SIMD2<Double>(nx, ny)

                let v2 = p - pA
                let d20 = simd_dot(v2, v0)
                let d21 = simd_dot(v2, v1)
                var v = (d11 * d20 - d01 * d21) / (denom == 0 ? 1 : denom)
                var w = (d00 * d21 - d01 * d20) / (denom == 0 ? 1 : denom)
                var u = 1.0 - v - w

                u = max(0.0, u)
                v = max(0.0, v)
                w = max(0.0, w)
                var sum = u + v + w
                if sum < 1e-6 {
                    let dA = simd_length(p - pA)
                    let dB = simd_length(p - pB)
                    let dC = simd_length(p - pC)
                    if dA <= dB && dA <= dC { u = 1; v = 0; w = 0; sum = 1 }
                    else if dB <= dC { u = 0; v = 1; w = 0; sum = 1 }
                    else { u = 0; v = 0; w = 1; sum = 1 }
                }
                let inv = 1.0 / sum
                u *= inv; v *= inv; w *= inv

                // Blend premultiplied
                let a = u*cA.3 + v*cB.3 + w*cC.3
                let r = u*cA.0*cA.3 + v*cB.0*cB.3 + w*cC.0*cC.3
                let g = u*cA.1*cA.3 + v*cB.1*cB.3 + w*cC.1*cC.3
                let b = u*cA.2*cA.3 + v*cB.2*cB.3 + w*cC.2*cC.3

                // Ordered noise
                let th = bayer[y & 3][x & 3]
                let n = Double(th - 0.5) * amplitude
                let rn = min(1.0, max(0.0, r + n))
                let gn = min(1.0, max(0.0, g + n))
                let bn = min(1.0, max(0.0, b + n))
                let an = min(1.0, max(0.0, a))

                ptr[idx + 2] = UInt8(min(255, max(0, Int(round(rn * 255)))))
                ptr[idx + 1] = UInt8(min(255, max(0, Int(round(gn * 255)))))
                ptr[idx + 0] = UInt8(min(255, max(0, Int(round(bn * 255)))))
                ptr[idx + 3] = UInt8(min(255, max(0, Int(round(an * 255)))))
            }
        }

        return ctx.makeImage()
    }

    // First: draw the gradient into the bitmap using Core Graphics (no per-pixel hex conversions)
    drawLinearGradientCG(gradientNodes: nodes, angle: gradient.angle, width: width, height: height, context: ctx)

    guard let buffer = ctx.data else { return ctx.makeImage() }
    let ptr = buffer.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

    // Build 4x4 Bayer matrix scaled to [0,1]
    let bayer = bayerMatrix4x4()

    // Dither amplitude ~ LSBs, scaled by grain. Disable during editing for performance.
    let grain = max(0.0, min(1.0, gradient.grain))
    let amplitude = (allowDithering ? (0.6 + 1.4 * grain) : 0.0) / 255.0

    for y in 0..<height {
        for x in 0..<width {
            let idx = (y * width + x) * bytesPerPixel
            let b = Double(ptr[idx + 0]) / 255.0
            let g = Double(ptr[idx + 1]) / 255.0
            let r = Double(ptr[idx + 2]) / 255.0
            let a = Double(ptr[idx + 3]) / 255.0
            let th = bayer[y & 3][x & 3]
            // Add small ordered noise around 0 using Bayer threshold
            let n = Double(th - 0.5) * amplitude
            let rn = min(1.0, max(0.0, r + n))
            let gn = min(1.0, max(0.0, g + n))
            let bn = min(1.0, max(0.0, b + n))
            ptr[idx + 2] = UInt8(min(255, max(0, Int(round(rn * 255)))))
            ptr[idx + 1] = UInt8(min(255, max(0, Int(round(gn * 255)))))
            ptr[idx + 0] = UInt8(min(255, max(0, Int(round(bn * 255)))))
            ptr[idx + 3] = UInt8(min(255, max(0, Int(round(a * 255)))))
        }
    }

    return ctx.makeImage()
}

// Retained for potential future use if posterization is desired.
private func ditherQuantize(_ v: Double, levels: Int, threshold: Float) -> Double {
    let lv = max(2, levels)
    let step = 1.0 / Double(lv - 1)
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
        let ns = cachedNSColor(hex: n.colorHex)
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
    // Extend beyond start/end to guarantee full-rect coverage (prevents corner slivers)
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    #endif
}

// MARK: - Renderer with caching and background generation
final class DitheredGradientRenderer: ObservableObject {
    @Published var image: CGImage?
    private var workItem: DispatchWorkItem?
    private static var cache = NSCache<NSString, CGImage>()

    func update(gradient: SpaceGradient, size: CGSize, scale: Double, allowDithering: Bool) {
        // Debounce rapid updates
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            let key = self?.cacheKey(gradient: gradient, size: size)
            if let key = key, let cached = Self.cache.object(forKey: key as NSString) {
                DispatchQueue.main.async { self?.image = cached }
                return
            }
            // Compute image; renderer decides whether to apply dithering based on flag and gradient
            let img = generateDitheredGradient(gradient: gradient, size: size, allowDithering: allowDithering && !shouldSkipDithering(gradient))
            if let img, let key = key {
                Self.cache.setObject(img, forKey: key as NSString)
            }
            DispatchQueue.main.async { self?.image = img }
        }
        workItem = item
        DispatchQueue.global(qos: .userInitiated).async(execute: item)
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
