import SwiftUI

// MARK: - AngleDial
// Dedicated dial for gradient angle with tick marks
struct AngleDial: View {
    @Binding var angle: Double // degrees 0...360

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)

                // tick marks
                ForEach(0..<24, id: \.self) { i in
                    let a = Double(i) / 24.0 * 2 * .pi
                    Capsule()
                        .fill(Color.primary.opacity(i % 6 == 0 ? 0.35 : 0.18))
                        .frame(width: i % 6 == 0 ? 3 : 2, height: i % 6 == 0 ? 10 : 6)
                        .offset(y: -size/2 + 10)
                        .rotationEffect(.radians(a))
                }

                // needle and handle
                let a = Angle(degrees: angle)
                let handle = CGPoint(x: cos(a.radians) * (size/2 - 12), y: sin(a.radians) * (size/2 - 12))
                Path { p in
                    p.move(to: CGPoint(x: size/2, y: size/2))
                    p.addLine(to: CGPoint(x: size/2 + handle.x, y: size/2 + handle.y))
                }
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)

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
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                angle = deg
            })
        }
    }
}

