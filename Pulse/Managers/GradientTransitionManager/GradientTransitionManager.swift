import Foundation
import SwiftUI
import QuartzCore

@MainActor
final class GradientTransitionManager: ObservableObject {
    @Published var displayGradient: SpaceGradient = .default
    @Published private(set) var isEditing: Bool = false

    private var timer: Timer?
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0.45
    private var fromGradient: SpaceGradient = .default
    private var toGradient: SpaceGradient = .default
    private var animation: Animation = .easeInOut

    func setImmediate(_ gradient: SpaceGradient) {
        cancelTimer()
        displayGradient = gradient
    }

    func beginInteractivePreview() {
        cancelTimer()
        isEditing = true
    }

    func endInteractivePreview() {
        cancelTimer()
        isEditing = false
    }

    func transition(from: SpaceGradient? = nil,
                    to: SpaceGradient,
                    duration: TimeInterval = 0.45,
                    animation: Animation = .easeInOut) {
        // Suppress transitions while an interactive edit is in progress
        if isEditing { return }
        cancelTimer()

        self.duration = max(0.0, duration)
        self.animation = animation
        self.fromGradient = from ?? displayGradient
        self.toGradient = to

        guard self.duration > 0 else {
            setImmediate(to)
            return
        }

        self.startTime = CACurrentMediaTime()

        // Drive updates ~60fps
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick()
        }
        self.timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        var progress = (now - startTime) / duration
        if progress >= 1.0 {
            progress = 1.0
        }

        // Ease progress using SwiftUI animation timing curve by mapping to timing function.
        // Since we cannot directly sample Animation, approximate with .easeInOut by using a cosine blend.
        let eased = easeInOut(progress)

        let interpolated = interpolateGradient(from: fromGradient, to: toGradient, progress: eased)
        // Assign directly; easing already applied above. Avoid implicit animations every frame.
        self.displayGradient = interpolated

        if progress >= 1.0 {
            cancelTimer()
            // Ensure final value lands exactly on target
            self.displayGradient = toGradient
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        // Timer will be released with this object; no actor hop here.
    }
}

// MARK: - Interpolation helpers
@MainActor
private func interpolateGradient(from: SpaceGradient, to: SpaceGradient, progress: Double) -> SpaceGradient {
    // Normalize nodes count
    let (aNodes, bNodes) = normalizeGradientNodes(from: from.nodes, to: to.nodes)
    let nodes = interpolateGradientNodes(from: aNodes, to: bNodes, progress: progress)
    let angle = interpolateAngle(from: from.angle, to: to.angle, progress: progress)
    let grain = from.grain + (to.grain - from.grain) * progress
    return SpaceGradient(angle: angle, nodes: nodes, grain: grain)
}

private func easeInOut(_ t: Double) -> Double {
    // Cosine-based easeInOut (similar to .easeInOut)
    return 0.5 - 0.5 * cos(Double.pi * min(1, max(0, t)))
}
