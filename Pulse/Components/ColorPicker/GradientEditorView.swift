import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - GradientEditorView
// Composes preview, node/angle controls, color grid, and transparency/grain
struct GradientEditorView: View {
    @Binding var gradient: SpaceGradient
    @State private var selectedNodeID: UUID?
    @EnvironmentObject var gradientTransitionManager: GradientTransitionManager

    // No throttling: update in real time

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GradientCanvasEditor(gradient: $gradient, selectedNodeID: $selectedNodeID, showDitherOverlay: false)

            ColorSwatchRowView(selectedColor: selectedColor()) { color in
                applyColorSelection(color)
            }

            // Opacity control for selected node
            TransparencySlider(selectedNode: bindingSelectedNode()) { updated in
                updateNode(updated)
            }
        }
        .padding(16)
        .onAppear { if selectedNodeID == nil { selectedNodeID = gradient.nodes.first?.id } }
        .onChange(of: gradient) { newValue in
            // Scrubbing should be immediate to avoid animation token races
            gradientTransitionManager.setImmediate(newValue)
        }
        .onAppear {
            // Ensure background starts from the current draft gradient
            gradientTransitionManager.setImmediate(gradient)
            gradientTransitionManager.beginInteractivePreview()
        }
        .onDisappear {
            gradientTransitionManager.endInteractivePreview()
        }
    }

    // MARK: - Selection Helpers
    private func selectedNodeIndex() -> Int? {
        if let id = selectedNodeID { return gradient.nodes.firstIndex(where: { $0.id == id }) }
        return gradient.nodes.indices.first
    }

    private func bindingSelectedNode() -> Binding<GradientNode?> {
        Binding<GradientNode?>(
            get: {
                if let idx = selectedNodeIndex() { return gradient.nodes[idx] }
                return nil
            },
            set: { newValue in
                guard let node = newValue, let idx = selectedNodeIndex() else { return }
                gradient.nodes[idx] = node
            }
        )
    }

    private func selectedColor() -> Color? {
        guard let idx = selectedNodeIndex() else { return nil }
        return Color(hex: gradient.nodes[idx].colorHex)
    }

    private func applyColorSelection(_ color: Color) {
        guard let idx = selectedNodeIndex() else { return }
        #if canImport(AppKit)
        // Preserve existing alpha from current node
        let currentNS = NSColor(Color(hex: gradient.nodes[idx].colorHex)).usingColorSpace(.sRGB)
        var oldA: CGFloat = 1.0
        var cr: CGFloat = 1, cg: CGFloat = 1, cb: CGFloat = 1
        currentNS?.getRed(&cr, green: &cg, blue: &cb, alpha: &oldA)

        // Extract new RGB from selected Color
        let newNS = NSColor(color).usingColorSpace(.sRGB)
        var nr: CGFloat = 1, ng: CGFloat = 1, nb: CGFloat = 1, na: CGFloat = 1
        newNS?.getRed(&nr, green: &ng, blue: &nb, alpha: &na)

        let combined = NSColor(srgbRed: nr, green: ng, blue: nb, alpha: oldA)
        gradient.nodes[idx].colorHex = combined.toHexString(includeAlpha: true) ?? gradient.nodes[idx].colorHex
        #endif
    }

    private func updateNode(_ updated: GradientNode) {
        guard let idx = gradient.nodes.firstIndex(where: { $0.id == updated.id }) else { return }
        gradient.nodes[idx] = updated
        // Live update when transparency slider changes
        gradientTransitionManager.setImmediate(gradient)
    }

    // No bespoke hex helpers: rely on Color(hex:) and NSColor.toHexString
}
