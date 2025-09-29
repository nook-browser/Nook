import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - BarycentricGradientView
// GPU shader-based gradient using barycentric interpolation across up to 3 colors.
// - Supports 1, 2, and 3 color schemes.
// - Smoothly animates activation between counts (1<->2<->3) in Metal.
struct BarycentricGradientView: View, Animatable {
    var gradient: SpaceGradient
    @EnvironmentObject private var gradientColorManager: GradientColorManager

    // Track transitions between color-count modes for smooth activation
    @State private var previousCount: Int = 0
    @State private var activationProgress: Double = 1.0

    // Bridge SpaceGradient's animatable data so SwiftUI drives shader args smoothly
    var animatableData: SpaceGradient.AnimVector {
        get { gradient.animatableData }
        set {
            gradient.animatableData = newValue
            // Update activation progress when gradient changes
            let currentCount = max(1, min(3, gradient.sortedNodes.count))
            if currentCount != previousCount {
                activationProgress = 0.0
                withAnimation(.easeInOut(duration: 0.3)) {
                    activationProgress = 1.0
                }
            }
        }
    }

    // Anchor inset controls how far in from the edges the color anchors sit.
    // Increasing this pulls anchors inward (shrinks individual lobes),
    // decreasing pushes them toward the edges (expands individual lobes).
    private let anchorInset: Double = 0.08

    // Fixed anchor positions in normalized space (top-left, top-right, bottom-center)
    private var pA: SIMD2<Double> { SIMD2<Double>(anchorInset, anchorInset) }
    private var pB: SIMD2<Double> { SIMD2<Double>(1.0 - anchorInset, anchorInset) }
    private var pC: SIMD2<Double> { SIMD2<Double>(0.5, 1.0 - anchorInset) }

    var body: some View {
        let nodes = gradient.sortedNodes
        let count = max(1, min(3, nodes.count))

        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let shader = Self.makeShader(
                gradient: gradient,
                size: size,
                pA: pA, pB: pB, pC: pC,
                previousCount: previousCount,
                currentCount: count,
                t: activationProgress,
                primaryID: gradientColorManager.activePrimaryNodeID ?? gradientColorManager.preferredPrimaryNodeID
            )
            context.fill(Path(rect), with: .shader(shader))
        }
        .onAppear {
            let c = max(1, min(3, gradient.sortedNodes.count))
            previousCount = c
            activationProgress = 1.0
        }
        .onChange(of: gradient) { _ in
            let currentCount = max(1, min(3, gradient.sortedNodes.count))
            if currentCount != previousCount {
                previousCount = currentCount
                activationProgress = 0.0
                withAnimation(.easeInOut(duration: 0.3)) {
                    activationProgress = 1.0
                }
            }
        }
    }

    private static func makeShader(gradient: SpaceGradient,
                                   size: CGSize,
                                   pA: SIMD2<Double>, pB: SIMD2<Double>, pC: SIMD2<Double>,
                                   previousCount: Int, currentCount: Int, t: Double,
                                   primaryID: UUID?) -> Shader {
        // Start from location-sorted nodes, then move the active primary to the front
        var nodes = gradient.sortedNodes
        if let pid = primaryID, let idx = nodes.firstIndex(where: { $0.id == pid }) {
            let primary = nodes.remove(at: idx)
            nodes.insert(primary, at: 0)
        }
        // Select up to first 3 nodes; duplicate last color if fewer
        let nA = nodes.count > 0 ? nodes[0] : SpaceGradient.default.sortedNodes[0]
        let nB = nodes.count > 1 ? nodes[1] : nA
        let nC = nodes.count > 2 ? nodes[2] : nB
        #if canImport(AppKit)
        let cA = Color(nsColor: NSColor(Color(hex: nA.colorHex)).usingColorSpace(.sRGB) ?? .black)
        let cB = Color(nsColor: NSColor(Color(hex: nB.colorHex)).usingColorSpace(.sRGB) ?? .black)
        let cC = Color(nsColor: NSColor(Color(hex: nC.colorHex)).usingColorSpace(.sRGB) ?? .black)
        #else
        let cA = Color(hex: nA.colorHex)
        let cB = Color(hex: nB.colorHex)
        let cC = Color(hex: nC.colorHex)
        #endif

        // Activation profiles for counts 1,2,3 respectively
        func weights(for count: Int) -> (Double, Double, Double) {
            switch max(1, min(3, count)) {
            case 1: return (1, 0, 0)
            case 2: return (1, 1, 0)
            default: return (1, 1, 1)
            }
        }
        let (a0, b0, c0) = weights(for: previousCount)
        let (a1, b1, c1) = weights(for: currentCount)
        // Interpolate activation smoothly
        let sA = a0 + (a1 - a0) * t
        let sB = b0 + (b1 - b0) * t
        let sC = c0 + (c1 - c0) * t

        let function = ShaderFunction(library: .default, name: "baryAdaptiveGradient")
        return Shader(function: function, arguments: [
            .color(cA), .color(cB), .color(cC),
            .float2(size),
            .float2(CGSize(width: pA.x, height: pA.y)),
            .float2(CGSize(width: pB.x, height: pB.y)),
            .float2(CGSize(width: pC.x, height: pC.y)),
            .float(sA), .float(sB), .float(sC)
        ])
    }

    private static func stops(_ g: SpaceGradient) -> [Gradient.Stop] {
        var mapped: [Gradient.Stop] = g.sortedNodes.map { node in
            #if canImport(AppKit)
            let c = Color(nsColor: NSColor(Color(hex: node.colorHex)).usingColorSpace(.sRGB) ?? .black)
            #else
            let c = Color(hex: node.colorHex)
            #endif
            return Gradient.Stop(color: c, location: CGFloat(node.location))
        }
        if mapped.count == 0 {
            let def = SpaceGradient.default
            mapped = def.sortedNodes.map {
                #if canImport(AppKit)
                Gradient.Stop(color: Color(nsColor: NSColor(Color(hex: $0.colorHex)).usingColorSpace(.sRGB) ?? .black), location: CGFloat($0.location))
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
