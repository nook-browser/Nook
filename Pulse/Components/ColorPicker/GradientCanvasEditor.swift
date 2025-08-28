import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - GradientCanvasEditor
// Large canvas with dot grid background and draggable color stops
struct GradientCanvasEditor: View {
    @Binding var gradient: SpaceGradient
    @Binding var selectedNodeID: UUID?
    var showDitherOverlay: Bool = true

    // ephemeral Y-positions (0...1) for visual placement only
    @State private var yPositions: [UUID: CGFloat] = [:]
    @State private var xPositions: [UUID: CGFloat] = [:]
    @State private var selectedMode: Int = 0 // 0 sparkle, 1 sun, 2 moon
    @State private var lightness: Double = 0.6 // HSL L component

    private let cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let padding: CGFloat = 24
            let center = CGPoint(x: width/2, y: height/2)
            let radius = min(width, height)/2 - padding

            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(stops: stops()), startPoint: startPoint(), endPoint: endPoint()))

                // Noise overlay (optional)
                if showDitherOverlay {
                    Image("noise_texture")
                        .resizable()
                        .scaledToFill()
                        .opacity(max(0, min(1, gradient.grain)))
                        .blendMode(.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                }

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
                    let posX = xPositions[node.id] ?? CGFloat(node.location)
                    let posY = yPositions[node.id] ?? defaultY(for: node)
                    let initial = CGPoint(x: posX * width, y: posY * height)
                    let clamped = clampToCircle(point: initial, center: center, radius: radius)

                    Handle(colorHex: node.colorHex, selected: selectedNodeID == node.id)
                        .position(clamped)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Clamp to circle and map to HSL for color
                                let clamped = clampToCircle(point: value.location, center: center, radius: radius)
                                let nx = max(0, min(1, clamped.x / width))
                                let ny = max(0, min(1, clamped.y / height))
                                updateNodeFromCanvasDrag(node, newX: nx, newY: ny, absolute: clamped, center: center, radius: radius)
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
            .onAppear { ensurePositions(width: width, height: height, center: center, radius: radius) }
            .onChange(of: gradient.nodes) { _ in ensurePositions(width: width, height: height, center: center, radius: radius) }
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
            .onTapGesture {
                selectedMode = idx
                switch idx {
                case 0: lightness = 0.6 // sparkle
                case 1: lightness = 0.7 // sun
                case 2: lightness = 0.45 // moon
                default: lightness = 0.6
                }
            }
    }

    private func defaultY(for node: GradientNode) -> CGFloat {
        // spread defaults by index for nicer initial layout
        if let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) {
            return [0.35, 0.55, 0.45][min(idx, 2)]
        }
        return 0.5
    }

    private func ensurePositions(width: CGFloat, height: CGFloat, center: CGPoint, radius: CGFloat) {
        for n in gradient.nodes {
            if yPositions[n.id] == nil { yPositions[n.id] = defaultY(for: n) }
            if xPositions[n.id] == nil { xPositions[n.id] = CGFloat(n.location) }
            // keep points within circle
            let pt = CGPoint(x: (xPositions[n.id] ?? CGFloat(n.location)) * width,
                             y: (yPositions[n.id] ?? defaultY(for: n)) * height)
            let clamped = clampToCircle(point: pt, center: center, radius: radius)
            xPositions[n.id] = clamped.x / width
            yPositions[n.id] = clamped.y / height
        }
        // purge removed
        xPositions = xPositions.filter { pair in gradient.nodes.contains { $0.id == pair.key } }
        yPositions = yPositions.filter { pair in gradient.nodes.contains { $0.id == pair.key } }
    }

    private func updateNodeFromCanvasDrag(_ node: GradientNode, newX: CGFloat, newY: CGFloat, absolute: CGPoint, center: CGPoint, radius: CGFloat) {
        guard let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        // Update persistent location from X only
        gradient.nodes[idx].location = Double(newX)
        // Save visual positions
        xPositions[node.id] = newX
        yPositions[node.id] = newY
        gradient.nodes.sort { $0.location < $1.location }
        selectedNodeID = node.id

        // Map position on circle to HSL color
        let hsla = colorFromCircle(point: absolute, center: center, radius: radius, lightness: lightness)
        let updated = colorWithPreservedAlpha(oldHex: gradient.nodes[idx].colorHex, newColor: hsla)
        gradient.nodes[idx].colorHex = updated

        // If there are 2 or 3 nodes, auto-place complementary/triadic companions
        autoPlaceCompanions(primary: node, center: center, radius: radius)
    }

    private func clampToCircle(point: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx*dx + dy*dy)
        if dist <= radius { return point }
        let angle = atan2(dy, dx)
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func autoPlaceCompanions(primary: GradientNode, center: CGPoint, radius: CGFloat) {
        guard gradient.nodes.count > 1, let pX = xPositions[primary.id], let pY = yPositions[primary.id] else { return }
        let width: CGFloat = 1 // we will use normalized x/y in [0,1]
        let p = CGPoint(x: pX, y: pY)
        let baseAngle = atan2(p.y - 0.5, p.x - 0.5)
        let dist = min(0.5, sqrt(pow(p.x - 0.5, 2) + pow(p.y - 0.5, 2)))
        let offsets: [Double] = gradient.nodes.count == 2 ? [180] : [120, 240]
        var others = gradient.nodes.filter { $0.id != primary.id }
        for (i, off) in offsets.enumerated() {
            if i >= others.count { break }
            let ang = baseAngle + CGFloat(off * .pi / 180)
            let pos = CGPoint(x: 0.5 + cos(ang) * dist, y: 0.5 + sin(ang) * dist)
            let absPt = CGPoint(x: pos.x * (radius*2 + 48), y: pos.y * (radius*2 + 48)) // scale roughly to canvas, not critical
            let colorHex = colorFromCircle(point: absPt, center: CGPoint(x: radius+24, y: radius+24), radius: radius, lightness: lightness)
            if let idx = gradient.nodes.firstIndex(where: { $0.id == others[i].id }) {
                gradient.nodes[idx].colorHex = colorHex
                xPositions[others[i].id] = pos.x
                yPositions[others[i].id] = pos.y
                gradient.nodes[idx].location = Double(pos.x)
            }
        }
    }

    private func colorFromCircle(point: CGPoint, center: CGPoint, radius: CGFloat, lightness: Double) -> String {
        #if canImport(AppKit)
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let hue = Double(angle / (2 * .pi))
        let dist = min(1.0, Double(sqrt(dx*dx + dy*dy) / radius))
        // Saturation grows with distance from center, keep high near edge
        let saturation = 0.2 + 0.8 * dist
        let ns = NSColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(lightness), alpha: 1)
        return ns.toHexString(includeAlpha: true) ?? "#FFFFFFFF"
        #else
        return "#FFFFFFFF"
        #endif
    }

    private func colorWithPreservedAlpha(oldHex: String, newColor: String) -> String {
        let aOld = Color(hex: oldHex)
        #if canImport(AppKit)
        var oa: CGFloat = 1
        var orv: CGFloat = 0, ogv: CGFloat = 0, obv: CGFloat = 0
        NSColor(aOld).usingColorSpace(.sRGB)?.getRed(&orv, green: &ogv, blue: &obv, alpha: &oa)
        var nr: CGFloat = 1, ng: CGFloat = 1, nb: CGFloat = 1, na: CGFloat = 1
        NSColor(Color(hex: newColor)).usingColorSpace(.sRGB)?.getRed(&nr, green: &ng, blue: &nb, alpha: &na)
        let combined = NSColor(srgbRed: nr, green: ng, blue: nb, alpha: oa)
        return combined.toHexString(includeAlpha: true) ?? newColor
        #else
        return newColor
        #endif
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
