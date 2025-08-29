import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - BarycentricTriGradientView
// GPU shader-based tri-color gradient using barycentric interpolation.
// Expects exactly 3 nodes; falls back to a linear gradient otherwise.
struct BarycentricTriGradientView: View {
    let gradient: SpaceGradient

    // Fixed anchor positions in normalized space (left, top-right, bottom-right)
    private let pA = SIMD2<Double>(0.08, 0.50)
    private let pB = SIMD2<Double>(0.92, 0.25)
    private let pC = SIMD2<Double>(0.92, 0.75)

    var body: some View {
        if gradient.nodes.count == 3 {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let shader = Self.makeShader(gradient: gradient, size: size, pA: pA, pB: pB, pC: pC)
                context.fill(Path(rect), with: .shader(shader))
            }
        } else {
            // Fallback to existing SwiftUI linear gradient behavior (angle respected)
            let pts = Self.linePoints(angle: gradient.angle)
            Rectangle()
                .fill(LinearGradient(gradient: Gradient(stops: Self.stops(gradient)), startPoint: pts.start, endPoint: pts.end))
        }
    }

    private static func makeShader(gradient: SpaceGradient, size: CGSize, pA: SIMD2<Double>, pB: SIMD2<Double>, pC: SIMD2<Double>) -> Shader {
        let nodes = gradient.sortedNodes
        // Map nodes by location: left = primary (min location), then the others
        guard nodes.count >= 3 else {
            // Defensive fallback
            let function = ShaderFunction(library: .default, name: "baryTriGradient")
            return Shader(function: function, arguments: [
                .color(.clear), .color(.clear), .color(.clear),
                .float2(size),
                .float2(CGSize.zero), .float2(CGSize.zero), .float2(CGSize.zero)
            ])
        }

        let nA = nodes[0]
        let nB = nodes[1]
        let nC = nodes[2]
        #if canImport(AppKit)
        let cA = Color(nsColor: NSColor(Color(hex: nA.colorHex)).usingColorSpace(.sRGB) ?? .black)
        let cB = Color(nsColor: NSColor(Color(hex: nB.colorHex)).usingColorSpace(.sRGB) ?? .black)
        let cC = Color(nsColor: NSColor(Color(hex: nC.colorHex)).usingColorSpace(.sRGB) ?? .black)
        #else
        let cA = Color(hex: nA.colorHex)
        let cB = Color(hex: nB.colorHex)
        let cC = Color(hex: nC.colorHex)
        #endif

        let function = ShaderFunction(library: .default, name: "baryTriGradient")
        return Shader(function: function, arguments: [
            .color(cA), .color(cB), .color(cC),
            .float2(size),
            .float2(CGSize(width: pA.x, height: pA.y)),
            .float2(CGSize(width: pB.x, height: pB.y)),
            .float2(CGSize(width: pC.x, height: pC.y)),
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
