import SwiftUI

// MARK: - GrainSlider
// Custom horizontal slider with a sine-wave track and vertical white thumb
struct GrainSlider: View {
    @Binding var value: Double // 0...1

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(Color.black.opacity(0.08))

                // Interpolated wave: amplitude goes 0 -> max with value
                let amplitude = max(0.001, value) * (h * 0.22)
                InterpolatedWave(amplitude: amplitude)
                    .stroke(
                        LinearGradient(colors: [
                            Color.black.opacity(0.15),
                            Color.black.opacity(0.45)
                        ], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 3
                    )
                    .padding(.horizontal, 16)

                // Thumb
                let x = CGFloat(value) * w
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 14 + CGFloat(value) * 10, height: (h - 8) + CGFloat(value) * 6)
                    .position(x: min(max(9, x), w - 9), y: h/2)
                    .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let x = min(max(0, g.location.x), w)
                value = Double(x / w)
            })
        }
        .frame(height: 44)
    }
}

private struct InterpolatedWave: Shape {
    let amplitude: CGFloat // 0 = line, else sine amplitude
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let length = rect.width
        p.move(to: CGPoint(x: rect.minX, y: midY))
        let step: CGFloat = 2
        let period: CGFloat = 18
        for x in stride(from: CGFloat(0), through: length, by: step) {
            let y = sin(x / period) * amplitude + midY
            p.addLine(to: CGPoint(x: rect.minX + x, y: y))
        }
        return p
    }
}
