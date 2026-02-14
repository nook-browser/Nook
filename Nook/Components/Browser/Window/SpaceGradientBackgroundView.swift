import SwiftUI

// Dithered gradient rendering
import CoreGraphics

// Renders the current space's gradient as a bottom background layer
struct SpaceGradientBackgroundView: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var gradientColorManager: GradientColorManager

    private var gradient: SpaceGradient {
        if windowState.isIncognito {
            return windowState.gradient
        }
        return gradientColorManager.displayGradient
    }

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(max(0, (0.35 - gradient.opacity)))
            BarycentricGradientView(gradient: gradient)
                .opacity(max(0.0, min(1.0, gradient.opacity)))
                .allowsHitTesting(false)
        }
    }
}
