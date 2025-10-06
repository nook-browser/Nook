import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - ColorPickerView
// Quadrant-based color grid with 3x3 tones per quadrant
struct ColorPickerView: View {
    // Current selection used to render selection border
    var selectedColor: Color?
    var onColorSelected: (Color) -> Void

    private let cellSize: CGFloat = 32
    private let cornerRadius: CGFloat = 8

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: 3) }

    // Generate tones for a base hue (0...1)
    private func tones(hue: Double) -> [Color] {
        // 3 brightness x 3 saturation
        let saturations: [Double] = [0.45, 0.70, 0.95]
        let brightness: [Double] = [0.45, 0.70, 0.95]
        return brightness.flatMap { b in
            saturations.map { s in
                Color(hue: hue, saturation: s, brightness: b)
            }
        }
    }

    private var quadrants: [(title: String, hue: Double)] {
        [
            ("Blue", 0.60),
            ("Red", 0.00),
            ("Green", 0.33),
            ("Yellow", 0.15)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(quadrants.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(tones(hue: item.hue).enumerated()), id: \.offset) { _, color in
                            ColorCell(color: color,
                                      isSelected: selectedColor.map { approxEqual($0, color) } ?? false,
                                      size: cellSize,
                                      cornerRadius: cornerRadius) {
                                onColorSelected(color)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // Loosely compare two colors in HSB space
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

// MARK: - Cell
private struct ColorCell: View {
    let color: Color
    let isSelected: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(hovering ? 0.06 : 0))
                )
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { action() }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}
