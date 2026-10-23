// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// The spatial colors and surface treatment of a space, independent of any UI framework.
public struct SpaceAppearance: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case system, light, dark
    }

    public struct Node: Identifiable, Codable, Hashable, Sendable {
        public var id: UUID
        public var colorHex: String
        public var x: Double
        public var y: Double

        public init(id: UUID = UUID(), colorHex: String, x: Double = 0.25, y: Double = 0.25) {
            self.id = id
            self.colorHex = colorHex
            self.x = x
            self.y = y
        }
    }

    public var nodes: [Node]
    public var mode: Mode
    public var grain: Double
    public var opacity: Double

    public init(nodes: [Node], mode: Mode = .system, grain: Double = 0, opacity: Double = 0.65) {
        self.nodes = nodes
        self.mode = mode
        self.grain = grain
        self.opacity = opacity
    }

    public init(accentHex: String) {
        // A stable identity makes repeated resolution of legacy spaces compare equal.
        self.init(nodes: [Node(id: Self.fallbackNodeID, colorHex: accentHex)])
    }

    /// Empty colors explicitly select the built-in light/dark chrome.
    public var usesDefaultTheme: Bool { nodes.isEmpty }
    public var primaryAccentHex: String { nodes.first?.colorHex ?? "#8E8E93" }

    private static let fallbackNodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let fallbackHex = "#3A8FA3"

    /// Keep persisted or externally supplied values safe for drawing and editing.
    public var normalized: Self {
        func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        var result = self
        var seen = Set<UUID>()
        result.nodes = nodes.prefix(3).map { node in
            var node = node
            if !seen.insert(node.id).inserted {
                node.id = UUID()
                seen.insert(node.id)
            }
            let hex = node.colorHex.hasPrefix("#") ? String(node.colorHex.dropFirst()) : node.colorHex
            let valid = (hex.count == 3 || hex.count == 6 || hex.count == 8) && hex.unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
            }
            let expanded = hex.count == 3 ? hex.map { String(repeating: String($0), count: 2) }.joined() : hex
            node.colorHex = valid ? "#" + expanded.uppercased() : Self.fallbackHex
            node.x = bounded(node.x, 0...1, fallback: 0.25)
            node.y = bounded(node.y, 0...1, fallback: 0.25)
            return node
        }
        result.grain = bounded(grain, 0...1, fallback: 0)
        result.opacity = bounded(opacity, 0.3...0.8, fallback: 0.65)
        return result
    }
}
