import Foundation
import SwiftUI

@MainActor
final class GradientColorManager: ObservableObject {
    @Published var displayGradient: SpaceGradient = .default
    @Published private(set) var isEditing: Bool = false
    @Published var isAnimating: Bool = false
    private var animationToken: UUID?

    // Animation state management
    @Published var preferBarycentricDuringAnimation: Bool = false
    @Published var activePrimaryNodeID: UUID? = nil
    @Published var preferredPrimaryNodeID: UUID? = nil

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
        activePrimaryNodeID = nil
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

        // Use the provided animation/timing for smooth direct transition
        let anim = animation

        // Tokenize this transition to avoid races on overlapping transitions
        let token = UUID()
        self.animationToken = token

        // Direct smooth transition to target gradient
        withAnimation(anim) {
            self.displayGradient = to
        }

        // After animation completes, make sure we land exactly on the final value
        let expectedEnd = to
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
            // Ensure final value is exact
            if self.animationToken == token {
                self.setImmediate(expectedEnd)
                self.isAnimating = false
            }
        }
    }
}

extension GradientColorManager {
    // Space-specific accent color derived from the currently displayed gradient.
    // Views can access this via `@EnvironmentObject var gradientColorManager`.
    // This is now a simple static color based on the current display gradient.
    var primaryColor: Color {
        return displayGradient.primaryColor
    }
}
