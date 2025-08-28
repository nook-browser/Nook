import SwiftUI

// MARK: - GradientNodePicker
// Manage 1-3 gradient nodes and a rotatable angle dial
struct GradientNodePicker: View {
    @Binding var gradient: SpaceGradient
    @Binding var selectedNodeID: UUID?

    private let swatchSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                nodeSwatches
                Spacer()
                HStack(spacing: 8) {
                    Button(action: removeNode) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove node")
                    .disabled(gradient.nodes.count <= 1)

                    Button(action: addNode) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Add node")
                    .disabled(gradient.nodes.count >= 3)
                }
            }

            angleDial

            VStack(alignment: .leading, spacing: 12) {
                ForEach(gradient.nodes) { node in
                    HStack {
                        Circle()
                            .fill(Color(hex: node.colorHex))
                            .frame(width: 14, height: 14)
                        Slider(value: binding(for: node), in: 0...1)
                        Text(String(format: "%.0f%%", (node.location * 100)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear { if selectedNodeID == nil { selectedNodeID = gradient.nodes.first?.id } }
    }

    // MARK: - Swatches
    private var nodeSwatches: some View {
        HStack(spacing: 8) {
            ForEach(gradient.nodes) { node in
                let isSelected = node.id == selectedNodeID
                Circle()
                    .fill(Color(hex: node.colorHex))
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 3 : 1))
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    .onTapGesture { selectedNodeID = node.id }
                    .contextMenu {
                        Button("Delete", role: .destructive) { removeSpecific(node) }
                            .disabled(gradient.nodes.count <= 1)
                    }
            }
        }
    }

    // MARK: - Angle Dial
    private var angleDial: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height, 140)
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)

                // Handle
                let angle = Angle(degrees: gradient.angle)
                let handle = point(onCircleOf: size/2 - 8, angle: angle)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .position(x: size/2 + handle.x, y: size/2 + handle.y)

                // Direction line
                Path { p in
                    p.move(to: CGPoint(x: size/2, y: size/2))
                    p.addLine(to: CGPoint(x: size/2 + handle.x, y: size/2 + handle.y))
                }
                .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let center = CGPoint(x: size/2, y: size/2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let degrees = atan2(dy, dx) * 180 / .pi
                // Convert from atan2 (0 at +x) to SwiftUI gradient angle convention
                var adjusted = degrees
                if adjusted < 0 { adjusted += 360 }
                gradient.angle = Double(adjusted)
            })
        }
        .frame(height: 160)
    }

    private func point(onCircleOf radius: CGFloat, angle: Angle) -> CGPoint {
        let r = radius
        let a = CGFloat(angle.radians)
        return CGPoint(x: cos(a) * r, y: sin(a) * r)
    }

    // MARK: - Node CRUD
    private func addNode() {
        guard gradient.nodes.count < 3 else { return }
        let color = gradient.nodes.first?.colorHex ?? "#FFFFFFFF"
        let new = GradientNode(id: UUID(), colorHex: color, location: min(1, max(0, (gradient.nodes.last?.location ?? 0.5) + 0.2)))
        gradient.nodes.append(new)
        selectedNodeID = new.id
        gradient.nodes.sort { $0.location < $1.location }
    }

    private func removeNode() {
        guard gradient.nodes.count > 1 else { return }
        if let id = selectedNodeID, let idx = gradient.nodes.firstIndex(where: { $0.id == id }) {
            gradient.nodes.remove(at: idx)
            selectedNodeID = gradient.nodes.first?.id
        } else {
            _ = gradient.nodes.popLast()
            selectedNodeID = gradient.nodes.last?.id
        }
    }

    private func removeSpecific(_ node: GradientNode) {
        guard gradient.nodes.count > 1 else { return }
        gradient.nodes.removeAll { $0.id == node.id }
        selectedNodeID = gradient.nodes.first?.id
    }

    private func binding(for node: GradientNode) -> Binding<Double> {
        Binding<Double>(
            get: {
                gradient.nodes.first(where: { $0.id == node.id })?.location ?? node.location
            },
            set: { newValue in
                if let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) {
                    gradient.nodes[idx].location = newValue
                    gradient.nodes.sort { $0.location < $1.location }
                }
            }
        )
    }
}
