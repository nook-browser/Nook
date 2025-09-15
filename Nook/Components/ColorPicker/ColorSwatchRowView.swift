import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - ColorSwatchRowView
// Horizontal palette row with arrows
struct ColorSwatchRowView: View {
    var selectedColor: Color?
    var onSelect: (Color) -> Void

    private let swatchSize: CGFloat = 28
    private let palettes: [[Color]] = {
        let base: [Color] = [
            Color.white,
            Color(red: 1.0, green: 0.55, blue: 0.75),
            Color.purple,
            Color.red,
            Color.orange,
            Color.yellow,
            Color.green,
            Color.cyan,
            Color.blue,
            Color.gray
        ]
        let alt: [Color] = [
            Color(white: 0.9),
            Color(hue: 0.95, saturation: 0.6, brightness: 0.9),
            Color(hue: 0.7, saturation: 0.5, brightness: 0.8),
            Color(hue: 0.03, saturation: 0.7, brightness: 0.95),
            Color(hue: 0.08, saturation: 0.7, brightness: 0.95),
            Color(hue: 0.13, saturation: 0.8, brightness: 0.95),
            Color(hue: 0.33, saturation: 0.75, brightness: 0.85),
            Color(hue: 0.55, saturation: 0.6, brightness: 0.9),
            Color(hue: 0.62, saturation: 0.7, brightness: 0.85),
            Color(hue: 0.75, saturation: 0.4, brightness: 0.7)
        ]
        return [base, alt]
    }()

    @State private var page: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Button { page = max(0, page - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(page == 0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(palettes[page].indices, id: \.self) { i in
                        let color = palettes[page][i]
                        Circle()
                            .fill(color)
                            .frame(width: swatchSize, height: swatchSize)
                            .overlay(
                                Circle().strokeBorder(Color.white, lineWidth: 2)
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    (selectedColor.map { approxEqual($0, color) } ?? false) ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                            )
                            .onTapGesture { onSelect(color) }
                    }
                }
                .padding(.horizontal, 4)
            }

            Button { page = min(palettes.count - 1, page + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(page >= palettes.count - 1)
        }
    }

    private func approxEqual(_ a: Color, _ b: Color) -> Bool {
        #if canImport(AppKit)
        let nsA = NSColor(a)
        let nsB = NSColor(b)
        var (ha, sa, ba): (CGFloat, CGFloat, CGFloat) = (0,0,0)
        var (hb, sb, bb): (CGFloat, CGFloat, CGFloat) = (0,0,0)
        nsA.usingColorSpace(.deviceRGB)?.getHue(&ha, saturation: &sa, brightness: &ba, alpha: nil)
        nsB.usingColorSpace(.deviceRGB)?.getHue(&hb, saturation: &sb, brightness: &bb, alpha: nil)
        return abs(ha - hb) < 0.03 && abs(sa - sb) < 0.08 && abs(ba - bb) < 0.08
        #else
        return false
        #endif
    }
}

