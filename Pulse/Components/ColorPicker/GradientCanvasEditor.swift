import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - GradientCanvasEditor
// Large canvas with dot grid background and draggable color stops
struct GradientCanvasEditor: View {
    @Binding var gradient: SpaceGradient
    @Binding var selectedNodeID: UUID?

    // ephemeral Y-positions (0...1) for visual placement only
    @State private var yPositions: [UUID: CGFloat] = [:]
    @State private var selectedMode: Int = 0 // 0 sparkle, 1 sun, 2 moon (visual only)

    private let cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let rect = CGRect(origin: .zero, size: proxy.size)

            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(stops: stops()), startPoint: startPoint(), endPoint: endPoint()))

                // Noise overlay
                Image("noise_texture")
                    .resizable()
                    .scaledToFill()
                    .opacity(max(0, min(1, gradient.grain)))
                    .blendMode(.overlay)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)

                // Dot grid
                DotGrid()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)

                // Top mode toggles
                HStack(spacing: 12) {
                    modeButton(symbol: "sparkles", idx: 0)
                    modeButton(symbol: "sun.max", idx: 1)
                    modeButton(symbol: "moon.stars", idx: 2)
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Draggable handles
                ForEach(gradient.nodes) { node in
                    let posX = CGFloat(node.location)
                    let posY = yPositions[node.id] ?? defaultY(for: node)
                    let center = CGPoint(x: posX * width, y: posY * height)

                    Handle(colorHex: node.colorHex, selected: selectedNodeID == node.id)
                        .position(center)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let nx = max(0, min(1, value.location.x / width))
                                let ny = max(0, min(1, value.location.y / height))
                                updateNode(node, newX: nx, newY: ny)
                            }
                        )
                        .onTapGesture { selectedNodeID = node.id }
                }

                // Plus / minus at bottom center
                HStack(spacing: 24) {
                    Button(action: removeNode) {
                        Image(systemName: "minus")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                     .disabled(gradient.nodes.count <= 1)
                    Button(action: addNode) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                     .disabled(gradient.nodes.count >= 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)

                // Border stroke
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear { ensureYPositions(height: height) }
            .onChange(of: gradient.nodes) { _ in ensureYPositions(height: height) }
        }
        .frame(height: 300)
    }

    // MARK: - Helpers
    private func modeButton(symbol: String, idx: Int) -> some View {
        Image(systemName: symbol)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedMode == idx ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
            )
            .foregroundStyle(selectedMode == idx ? .primary : .secondary)
            .onTapGesture { selectedMode = idx }
    }

    private func defaultY(for node: GradientNode) -> CGFloat {
        // spread defaults by index for nicer initial layout
        if let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) {
            return [0.35, 0.55, 0.45][min(idx, 2)]
        }
        return 0.5
    }

    private func ensureYPositions(height: CGFloat) {
        for n in gradient.nodes {
            if yPositions[n.id] == nil { yPositions[n.id] = defaultY(for: n) }
        }
        // drop removed
        yPositions = yPositions.filter { pair in gradient.nodes.contains { $0.id == pair.key } }
    }

    private func updateNode(_ node: GradientNode, newX: CGFloat, newY: CGFloat) {
        if let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) {
            gradient.nodes[idx].location = Double(newX)
            yPositions[node.id] = newY
            gradient.nodes.sort { $0.location < $1.location }
            selectedNodeID = node.id
        }
    }

    private func addNode() {
        guard gradient.nodes.count < 3 else { return }
        let source = selectedNodeID.flatMap { id in gradient.nodes.first(where: { $0.id == id }) }
        let color = source?.colorHex ?? gradient.nodes.first?.colorHex ?? "#FFFFFFFF"
        let loc = min(1, max(0, (source?.location ?? 0.5) + 0.15))
        let new = GradientNode(id: UUID(), colorHex: color, location: loc)
        gradient.nodes.append(new)
        gradient.nodes.sort { $0.location < $1.location }
        selectedNodeID = new.id
        yPositions[new.id] = 0.5
    }

    private func removeNode() {
        guard gradient.nodes.count > 1 else { return }
        if let id = selectedNodeID {
            gradient.nodes.removeAll { $0.id == id }
            yPositions.removeValue(forKey: id)
            selectedNodeID = gradient.nodes.first?.id
        } else {
            let removed = gradient.nodes.removeLast()
            yPositions.removeValue(forKey: removed.id)
            selectedNodeID = gradient.nodes.last?.id
        }
    }

    private func stops() -> [Gradient.Stop] {
        gradient.nodes
            .sorted(by: { $0.location < $1.location })
            .map { Gradient.Stop(color: Color(hex: $0.colorHex), location: CGFloat($0.location)) }
    }

    private func startPoint() -> UnitPoint {
        let theta = Angle(degrees: gradient.angle).radians
        return UnitPoint(x: 0.5 - 0.5 * cos(theta), y: 0.5 - 0.5 * sin(theta))
    }

    private func endPoint() -> UnitPoint {
        let theta = Angle(degrees: gradient.angle).radians
        return UnitPoint(x: 0.5 + 0.5 * cos(theta), y: 0.5 + 0.5 * sin(theta))
    }
}

// MARK: - Handle
private struct Handle: View {
    let colorHex: String
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: 30, height: 30)
            .overlay(
                Circle().strokeBorder(Color.white, lineWidth: 4)
            )
            .overlay(
                Circle().strokeBorder(selected ? Color.accentColor : Color.white.opacity(0), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)
            .contentShape(Circle())
    }
}

// MARK: - DotGrid
private struct DotGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let spacing: CGFloat = 10
            Canvas { ctx, _ in
                let cols = Int(w / spacing)
                let rows = Int(h / spacing)
                let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.5, height: 1.5))
                for r in 0...rows {
                    for c in 0...cols {
                        let x = CGFloat(c) * spacing + 2
                        let y = CGFloat(r) * spacing + 2
                        ctx.translateBy(x: x, y: y)
                        ctx.fill(dot, with: .color(Color.black.opacity(0.08)))
                        ctx.translateBy(x: -x, y: -y)
                    }
                }
            }
        }
    }
}

