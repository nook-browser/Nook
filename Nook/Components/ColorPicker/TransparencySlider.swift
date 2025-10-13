import SwiftUI

// MARK: - TransparencySlider
// Controls global opacity of the gradient layer
struct TransparencySlider: View {
    @Binding var gradient: SpaceGradient
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var localOpacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", localOpacity * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                opacityPreview
                    .frame(width: 48, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Slider(value: $localOpacity, in: 0...1)
            }
        }
        .onAppear { localOpacity = clamp(gradient.opacity) }
        .onChange(of: gradient.opacity) { _, newValue in localOpacity = clamp(newValue) }
        .onChange(of: localOpacity) { _, newValue in
            gradient.opacity = clamp(newValue)
            // Push live background update immediately
            gradientColorManager.setImmediate(gradient)
        }
    }

    private var opacityPreview: some View {
        ZStack {
            CheckerboardBackground()
            // Lightweight gradient preview inline
            let pts = linePoints(angle: gradient.angle)
            Rectangle()
                .fill(LinearGradient(gradient: Gradient(stops: stops()), startPoint: pts.start, endPoint: pts.end))
                .opacity(clamp(localOpacity))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
    }

    private func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

    private func stops() -> [Gradient.Stop] {
        var mapped: [Gradient.Stop] = gradient.sortedNodes.map { node in
            Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
        }
        if mapped.count == 0 {
            let def = SpaceGradient.default
            mapped = def.sortedNodes.map { node in
                Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
            }
        } else if mapped.count == 1 {
            let single = mapped[0]
            mapped = [
                Gradient.Stop(color: single.color, location: 0.0),
                Gradient.Stop(color: single.color, location: 1.0)
            ]
        }
        return mapped
    }

    private func linePoints(angle: Double) -> (start: UnitPoint, end: UnitPoint) {
        let theta = Angle(degrees: angle).radians
        let dx = cos(theta)
        let dy = sin(theta)
        let start = UnitPoint(x: 0.5 - 0.5 * dx, y: 0.5 - 0.5 * dy)
        let end = UnitPoint(x: 0.5 + 0.5 * dx, y: 0.5 + 0.5 * dy)
        return (start, end)
    }
}

// MARK: - Checkerboard Background
private struct CheckerboardBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tile: CGFloat = 6
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            Canvas { context, _ in
                for r in 0..<rows {
                    for c in 0..<cols {
                        let isDark = (r + c) % 2 == 0
                        let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile, width: tile, height: tile)
                        context.fill(Path(rect), with: .color(isDark ? Color.black.opacity(0.08) : Color.white.opacity(0.9)))
                    }
                }
            }
        }
    }
}
