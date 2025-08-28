import SwiftUI

// Dithered gradient rendering
import CoreGraphics

// Renders the current space's gradient as a bottom background layer
struct SpaceGradientBackgroundView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientTransitionManager: GradientTransitionManager

    private var gradient: SpaceGradient {
        gradientTransitionManager.displayGradient
    }

    var body: some View {
        ZStack {
            // Properly dithered gradient image respecting current displayGradient
            // While animating, DitheredGradientView will show a lightweight gradient.
            DitheredGradientView(gradient: gradient)
        }
        .allowsHitTesting(false) // Entire background should not intercept input
    }

    private func stops() -> [Gradient.Stop] {
        // Map nodes to stops
        var mapped: [Gradient.Stop] = gradient.sortedNodes.map { node in
            Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
        }
        // Ensure at least two stops to satisfy LinearGradient requirements
        if mapped.count == 0 {
            // Fallback to default gradient stops
            let def = SpaceGradient.default
            mapped = def.sortedNodes.map { node in
                Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
            }
        } else if mapped.count == 1 {
            // Duplicate the single color across the full range
            let single = mapped[0]
            mapped = [
                Gradient.Stop(color: single.color, location: 0.0),
                Gradient.Stop(color: single.color, location: 1.0)
            ]
        }
        return mapped
    }

    // Compute start and end UnitPoints using a single trig pass
    private func linePoints(angle: Double) -> (start: UnitPoint, end: UnitPoint) {
        let theta = Angle(degrees: angle).radians
        let dx = cos(theta)
        let dy = sin(theta)
        let start = UnitPoint(x: 0.5 - 0.5 * dx, y: 0.5 - 0.5 * dy)
        let end = UnitPoint(x: 0.5 + 0.5 * dx, y: 0.5 + 0.5 * dy)
        return (start, end)
    }
}
