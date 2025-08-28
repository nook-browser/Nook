import SwiftUI

// MARK: - GradientPreview
// Live preview for SpaceGradient with grain overlay
struct GradientPreview: View {
    @Binding var gradient: SpaceGradient

    private let cornerRadius: CGFloat = 12
    private let size = CGSize(width: 300, height: 160)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(gradient: Gradient(stops: stops()), startPoint: startPoint(), endPoint: endPoint()))

            Image("noise_texture")
                .resizable()
                .scaledToFill()
                .opacity(max(0, min(1, gradient.grain)))
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .drawingGroup()
    }

    private func stops() -> [Gradient.Stop] {
        gradient.nodes
            .sorted { $0.location < $1.location }
            .map { node in
                Gradient.Stop(color: Color(hex: node.colorHex), location: CGFloat(node.location))
            }
    }

    private func startPoint() -> UnitPoint {
        let theta = Angle(degrees: gradient.angle).radians
        let dx = cos(theta)
        let dy = sin(theta)
        return UnitPoint(x: 0.5 - 0.5 * dx, y: 0.5 - 0.5 * dy)
    }

    private func endPoint() -> UnitPoint {
        let theta = Angle(degrees: gradient.angle).radians
        let dx = cos(theta)
        let dy = sin(theta)
        return UnitPoint(x: 0.5 + 0.5 * dx, y: 0.5 + 0.5 * dy)
    }
}

