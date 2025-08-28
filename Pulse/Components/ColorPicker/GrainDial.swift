import SwiftUI

// MARK: - GrainDial
// Circular dial mapping rotation to 0...1 grain value
struct GrainDial: View {
    @Binding var grain: Double // 0...1

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                GeometryReader { proxy in
                    let size = min(proxy.size.width, proxy.size.height)
                    dial(size: size)
                }
            }
            .frame(height: 120)
            Text("Grain: " + String(format: "%.0f%%", grain * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dial(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.thinMaterial)
            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            let angle = Angle(degrees: grain * 360)
            let handle = point(onCircleOf: size/2 - 8, angle: angle)

            Path { p in
                p.move(to: CGPoint(x: size/2, y: size/2))
                p.addLine(to: CGPoint(x: size/2 + handle.x, y: size/2 + handle.y))
            }
            .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: size/2 + handle.x, y: size/2 + handle.y)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let center = CGPoint(x: size/2, y: size/2)
            let dx = value.location.x - center.x
            let dy = value.location.y - center.y
            var degrees = atan2(dy, dx) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            grain = max(0, min(1, Double(degrees) / 360.0))
        })
    }

    private func point(onCircleOf radius: CGFloat, angle: Angle) -> CGPoint {
        let r = radius
        let a = CGFloat(angle.radians)
        return CGPoint(x: cos(a) * r, y: sin(a) * r)
    }
}

