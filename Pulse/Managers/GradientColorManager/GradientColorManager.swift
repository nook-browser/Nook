import Foundation
import SwiftUI

@MainActor
final class GradientColorManager: ObservableObject {
    @Published var displayGradient: SpaceGradient = .default
    @Published private(set) var isEditing: Bool = false
    @Published var isAnimating: Bool = false
    @Published var preferBarycentricDuringAnimation: Bool = false
    private var animationToken: UUID?

    // MARK: - Immediate update (no animation)
    func setImmediate(_ gradient: SpaceGradient) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            self.displayGradient = gradient
        }
    }

    // MARK: - Editing lifecycle (no longer blocks transitions)
    func beginInteractivePreview() {
        isEditing = true
    }

    func endInteractivePreview() {
        isEditing = false
    }

    // MARK: - SwiftUI-driven transition
    func transition(from: SpaceGradient? = nil,
                    to: SpaceGradient,
                    duration: TimeInterval = 0.45,
                    animation: Animation = .easeInOut) {
        // If duration is zero (or negative), jump immediately
        guard duration > 0 else { setImmediate(to); return }

        // Flip on lightweight mode for renderers
        isAnimating = true

        // Prefer barycentric shader during animation if both ends are tri-color
        if let from { self.preferBarycentricDuringAnimation = (from.nodes.count == 3 && to.nodes.count == 3) }
        else { self.preferBarycentricDuringAnimation = (to.nodes.count == 3) }

        // If a specific starting gradient is provided, snap to it without animation first
        if let from {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { self.displayGradient = from }
        }

        // Use the provided animation/timing, scaled to approximate the requested duration
        // Base against previous default of ~0.45s
        let speedFactor = max(0.001, 0.45 / max(0.001, duration))
        let anim = animation.speed(speedFactor)

        // Tokenize this transition to avoid races on overlapping transitions
        let token = UUID()
        self.animationToken = token

        withAnimation(anim) {
            self.displayGradient = to
        }

        // After animation completes, make sure we land exactly on the final value
        // and toggle dithering back on.
        let expectedEnd = to
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.02) * 1_000_000_000))
            // Ensure final value is exact and disable animations for this set
            if self.animationToken == token {
                self.setImmediate(expectedEnd)
                self.isAnimating = false
                self.preferBarycentricDuringAnimation = false
            }
        }
    }
}

extension GradientColorManager {
    // Space-specific accent color derived from the currently displayed gradient.
    // Views can access this via `@EnvironmentObject var gradientColorManager`.
    var primaryColor: Color {
        displayGradient.primaryColor
    }
}
