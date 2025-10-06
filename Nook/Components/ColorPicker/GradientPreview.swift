import SwiftUI

// MARK: - GradientPreview
// Live preview for SpaceGradient with grain overlay
struct GradientPreview: View {
    @Binding var gradient: SpaceGradient
    var showDitherOverlay: Bool = true

    private let cornerRadius: CGFloat = 12
    private let size = CGSize(width: 300, height: 160)

    var body: some View {
        ZStack {
            BarycentricGradientView(gradient: gradient)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if showDitherOverlay {
                Image("noise_texture")
                    .resizable()
                    .scaledToFill()
                    .opacity(max(0, min(1, gradient.grain)))
                    .blendMode(.overlay)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .drawingGroup()
        .opacity(max(0.0, min(1.0, gradient.opacity)))
    }
}
