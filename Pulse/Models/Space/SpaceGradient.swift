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

    init(angle: Double, nodes: [GradientNode], grain: Double) {
        // Normalize angle to [0, 360)
        var normalized = angle.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 { normalized += 360.0 }
        self.angle = normalized
        // Clamp grain to [0,1]
        self.grain = max(0.0, min(1.0, grain))
        self.nodes = nodes
    }

    static var `default`: SpaceGradient {
        let hex = SpaceGradient.accentHex()
        let n1 = GradientNode(colorHex: hex, location: 0.0)
        let n2 = GradientNode(colorHex: hex, location: 1.0)
        return SpaceGradient(angle: 45.0, nodes: [n1, n2], grain: 0.05)
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let angle = try container.decode(Double.self, forKey: .angle)
        let nodes = try container.decode([GradientNode].self, forKey: .nodes)
        let grain = try container.decode(Double.self, forKey: .grain)
        self.init(angle: angle, nodes: nodes, grain: grain)
    }
}
