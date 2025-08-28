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
                // Sine wave track
                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(Color.black.opacity(0.08))

                SineWave()
                    .stroke(Color.black.opacity(0.35), lineWidth: 3)
                    .padding(.horizontal, 16)

                // Thumb
                let x = CGFloat(value) * w
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 18, height: h - 8)
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

private struct SineWave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let amp = rect.height * 0.18
        let length = rect.width
        p.move(to: CGPoint(x: rect.minX, y: midY))
        let step: CGFloat = 2
        for x in stride(from: CGFloat(0), through: length, by: step) {
            let y = sin(x / 18) * amp + midY
            p.addLine(to: CGPoint(x: rect.minX + x, y: y))
        }
        return p
    }
}

