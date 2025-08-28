import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - TransparencySlider
// Controls alpha channel of selected gradient node
struct TransparencySlider: View {
    @Binding var selectedNode: GradientNode?
    var onCommit: (GradientNode) -> Void

    @State private var opacityValue: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", opacityValue * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                opacityPreview
                    .frame(width: 48, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Slider(value: $opacityValue, in: 0...1)
                    .disabled(selectedNode == nil)
            }
        }
        .onChange(of: selectedNode?.colorHex) { _ in syncOpacityFromSelection() }
        .onChange(of: opacityValue) { _ in applyOpacityChange() }
        .onAppear { syncOpacityFromSelection() }
    }

    private var opacityPreview: some View {
        ZStack {
            CheckerboardBackground()
            if let hex = selectedNode?.colorHex {
                Color(hex: hex).opacity(opacityValue)
            } else {
                Color.clear
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
    }

    private func syncOpacityFromSelection() {
        guard let hex = selectedNode?.colorHex else { opacityValue = 1.0; return }
        #if canImport(AppKit)
        let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)
        var a: CGFloat = 1.0
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ns?.getRed(&r, green: &g, blue: &b, alpha: &a)
        opacityValue = Double(a)
        #else
        opacityValue = 1.0
        #endif
    }

    private func applyOpacityChange() {
        guard var node = selectedNode else { return }
        #if canImport(AppKit)
        let base = NSColor(Color(hex: node.colorHex)).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, _a: CGFloat = 1
        base.getRed(&r, green: &g, blue: &b, alpha: &_a)
        let updated = NSColor(srgbRed: r, green: g, blue: b, alpha: CGFloat(opacityValue))
        node.colorHex = updated.toHexString(includeAlpha: true) ?? node.colorHex
        #endif
        onCommit(node)
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
