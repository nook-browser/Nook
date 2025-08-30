//
//  SpaceGradient.swift
//  Pulse
//
//  Created by Codex on 28/08/2025.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct SpaceGradient: Codable, Hashable {
    var angle: Double
    var nodes: [GradientNode]
    var grain: Double
    // Global opacity for the entire gradient layer (0..1)
    var opacity: Double

    init(angle: Double, nodes: [GradientNode], grain: Double, opacity: Double = 1.0) {
        // Normalize angle to [0, 360)
        var normalized = angle.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 { normalized += 360.0 }
        self.angle = normalized
        // Clamp grain to [0,1]
        self.grain = max(0.0, min(1.0, grain))
        self.nodes = nodes
        self.opacity = max(0.0, min(1.0, opacity))
    }

    static var `default`: SpaceGradient {
        let hex = SpaceGradient.accentHex()
        let n1 = GradientNode(colorHex: hex, location: 0.0)
        let n2 = GradientNode(colorHex: hex, location: 1.0)
        return SpaceGradient(angle: 45.0, nodes: [n1, n2], grain: 0.05, opacity: 1.0)
    }

    var encoded: Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(self)
        } catch {
            print("[SpaceGradient] Encoding failed: \(error)")
            return nil
        }
    }

    static func decode(_ data: Data) -> SpaceGradient {
        guard !data.isEmpty else { return .default }
        let decoder = JSONDecoder()
        return (try? decoder.decode(SpaceGradient.self, from: data)) ?? .default
    }

    var sortedNodes: [GradientNode] {
        nodes.sorted { $0.location < $1.location }
    }

    // MARK: - Primary Color
    // Defines a "primary" color for a space derived from the gradient.
    // Rule: pick the node with the lowest location (leading stop). If no nodes
    // are defined, fall back to the system accent-derived default.
    var primaryColorHex: String {
        if let first = sortedNodes.first { return first.colorHex }
        return SpaceGradient.accentHex()
    }

    #if canImport(SwiftUI)
    var primaryColor: Color {
        Color(hex: primaryColorHex)
    }
    #endif

    #if canImport(AppKit)
    var primaryNSColor: NSColor {
        cachedNSColor(for: primaryColorHex)
    }
    #endif

    private static func accentHex() -> String {
        #if canImport(AppKit)
        let accent = NSColor.controlAccentColor
        guard let rgb = accent.usingColorSpace(.sRGB) else { return "#007AFF" }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return "#007AFF"
        #endif
    }
}

// MARK: - Codable (custom decode for normalization)
extension SpaceGradient {
    enum CodingKeys: String, CodingKey { case angle, nodes, grain, opacity }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let angle = try container.decode(Double.self, forKey: .angle)
        let nodes = try container.decode([GradientNode].self, forKey: .nodes)
        let grain = try container.decode(Double.self, forKey: .grain)
        let opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        self.init(angle: angle, nodes: nodes, grain: grain, opacity: opacity)
    }
}

// MARK: - Visual Equality
extension SpaceGradient {
    func visuallyEquals(_ other: SpaceGradient, epsilon: Double = 0.5, grainEpsilon: Double = 0.01, opacityEpsilon: Double = 0.01) -> Bool {
        // Compare angle and grain with tolerances
        let angleDiff = abs(self.angle - other.angle).truncatingRemainder(dividingBy: 360)
        let angleEqual: Bool = angleDiff < epsilon || abs(angleDiff - 360) < epsilon
        let grainEqual = abs(self.grain - other.grain) <= grainEpsilon
        let opacityEqual = abs(self.opacity - other.opacity) <= opacityEpsilon

        // Compare nodes ignoring IDs; order by location
        let aNodes = self.sortedNodes
        let bNodes = other.sortedNodes
        if aNodes.count != bNodes.count { return false }
        for i in 0..<aNodes.count {
            let a = aNodes[i]
            let b = bNodes[i]
            if a.colorHex.caseInsensitiveCompare(b.colorHex) != .orderedSame { return false }
            if abs(a.location - b.location) > 1e-4 { return false }
        }
        return angleEqual && grainEqual && opacityEqual
    }
}

// MARK: - Animatable Conformance
// Provide an animatable representation so SwiftUI can smoothly interpolate gradients.
// We flatten angle, grain and up to maxStops nodes (RGBA + location) into a VectorArithmetic.
extension SpaceGradient: Animatable {
    static let maxStopsForAnimation = 8

    struct AnimVector: VectorArithmetic {
        // Fixed-size vector: [(cosθ, sinθ), grain, (r,g,b,a,loc) * maxStops]
        static let width = 2 + 1 + maxStopsForAnimation * 5
        var scalars: [Double] = Array(repeating: 0, count: width)

        static var zero: AnimVector { AnimVector() }
        static func + (lhs: AnimVector, rhs: AnimVector) -> AnimVector {
            var out = AnimVector()
            for i in 0..<width { out.scalars[i] = lhs.scalars[i] + rhs.scalars[i] }
            return out
        }
        static func - (lhs: AnimVector, rhs: AnimVector) -> AnimVector {
            var out = AnimVector()
            for i in 0..<width { out.scalars[i] = lhs.scalars[i] - rhs.scalars[i] }
            return out
        }
        mutating func scale(by rhs: Double) {
            for i in 0..<Self.width { scalars[i] *= rhs }
        }
        var magnitudeSquared: Double {
            scalars.reduce(0) { $0 + $1*$1 }
        }
        static func == (lhs: AnimVector, rhs: AnimVector) -> Bool {
            // Not strictly required for VectorArithmetic but handy for stability
            guard lhs.scalars.count == rhs.scalars.count else { return false }
            for i in 0..<lhs.scalars.count {
                if lhs.scalars[i] != rhs.scalars[i] { return false }
            }
            return true
        }
    }

    var animatableData: AnimVector {
        get { SpaceGradient.encodeToAnimVector(self) }
        set { self = SpaceGradient.decodeFromAnimVector(newValue, fallback: self) }
    }

    private static func encodeToAnimVector(_ g: SpaceGradient) -> AnimVector {
        var out = AnimVector()
        // Normalize
        let theta = Angle(degrees: g.angle).radians
        let cosT = cos(theta)
        let sinT = sin(theta)
        let grain = min(1, max(0, g.grain))
        let sorted = g.sortedNodes

        // Prepare nodes padded to count and then to maxStops
        var nodes: [GradientNode] = sorted
        if nodes.isEmpty {
            nodes = SpaceGradient.default.sortedNodes
        }
        if nodes.count == 1 {
            let n = nodes[0]
            nodes = [GradientNode(id: n.id, colorHex: n.colorHex, location: 0.0), GradientNode(colorHex: n.colorHex, location: 1.0)]
        }
        if nodes.count < maxStopsForAnimation, let last = nodes.last {
            nodes.append(contentsOf: Array(repeating: GradientNode(colorHex: last.colorHex, location: last.location), count: maxStopsForAnimation - nodes.count))
        }
        if nodes.count > maxStopsForAnimation { nodes = Array(nodes.prefix(maxStopsForAnimation)) }

        out.scalars[0] = cosT
        out.scalars[1] = sinT
        out.scalars[2] = grain

        var idx = 3
        for n in nodes {
            #if canImport(AppKit)
            let ns = cachedNSColor(for: n.colorHex)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ns.getRed(&r, green: &g, blue: &b, alpha: &a)
            out.scalars[idx + 0] = Double(r)
            out.scalars[idx + 1] = Double(g)
            out.scalars[idx + 2] = Double(b)
            out.scalars[idx + 3] = Double(a)
            #else
            out.scalars[idx + 0] = 1
            out.scalars[idx + 1] = 1
            out.scalars[idx + 2] = 1
            out.scalars[idx + 3] = 1
            #endif
            out.scalars[idx + 4] = min(1, max(0, n.location))
            idx += 5
        }

        return out
    }

    private static func decodeFromAnimVector(_ v: AnimVector, fallback: SpaceGradient) -> SpaceGradient {
        let cosT = v.scalars[0]
        let sinT = v.scalars[1]
        // Recover angle from cos/sin
        var angleDeg = Angle(radians: atan2(sinT, cosT)).degrees
        if angleDeg < 0 { angleDeg += 360 }
        let grain = min(1, max(0, v.scalars[2]))

        var nodes: [GradientNode] = []
        nodes.reserveCapacity(maxStopsForAnimation)
        var idx = 3
        for _ in 0..<maxStopsForAnimation {
            let r = min(1, max(0, v.scalars[idx + 0]))
            let g = min(1, max(0, v.scalars[idx + 1]))
            let b = min(1, max(0, v.scalars[idx + 2]))
            let a = min(1, max(0, v.scalars[idx + 3]))
            let loc = min(1, max(0, v.scalars[idx + 4]))
            #if canImport(AppKit)
            let ns = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
            let hex = ns.toHexString(includeAlpha: true) ?? "#FFFFFFFF"
            #else
            let hex = "#FFFFFFFF"
            #endif
            nodes.append(GradientNode(colorHex: hex, location: loc))
            idx += 5
        }

        // Ensure monotonic locations to avoid visual artifacts
        var last: Double = 0.0
        for i in 0..<nodes.count {
            if nodes[i].location < last { nodes[i].location = last }
            last = nodes[i].location
        }
        if nodes.last?.location ?? 1.0 < 1.0 { nodes[nodes.count - 1].location = 1.0 }

        return SpaceGradient(angle: angleDeg, nodes: nodes, grain: grain)
    }
}

#if canImport(AppKit)
// MARK: - Cached NSColor for hex strings (to reduce per-frame parsing)
private let _SpaceGradientColorCache = NSCache<NSString, NSColor>()
private func cachedNSColor(for hex: String) -> NSColor {
    if let c = _SpaceGradientColorCache.object(forKey: hex as NSString) { return c }
    let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .black
    _SpaceGradientColorCache.setObject(ns, forKey: hex as NSString)
    return ns
}
#endif
