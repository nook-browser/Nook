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
    @EnvironmentObject var gradientColorManager: GradientColorManager

    // ephemeral Y-positions (0...1) for visual placement only
    @State private var yPositions: [UUID: CGFloat] = [:]
    @State private var xPositions: [UUID: CGFloat] = [:]
    @State private var selectedMode: Int = 0 // 0 sparkle, 1 sun, 2 moon
    @State private var lightness: Double = 0.6 // HSL L component
    // Lock a primary node identity when in 3-node mode
    @State private var lockedPrimaryID: UUID?
    
    // Haptic feedback state
    @State private var lastHapticSpoke: String? = nil
    @State private var lastHapticRadial: String? = nil

    private let cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let padding: CGFloat = 24
            let center = CGPoint(x: width/2, y: height/2)
            let radius = min(width, height)/2 - padding

            ZStack {
                // No gradient preview in the editor canvas; focus on dot grid + handles

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

                    let primaryID = primaryNodeID()
                    let isPrimary = (gradient.nodes.count == 3) && (node.id == primaryID)
                    let handleSize: CGFloat = isPrimary ? 40 : 26

                    Handle(colorHex: node.colorHex, selected: selectedNodeID == node.id, size: handleSize)
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
            .onChange(of: gradient.nodes.count) { _ in ensurePositions(width: width, height: height, center: center, radius: radius) }
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
        // Special layout when exactly 3 nodes: place both companions on the same circular radius as the primary
        // Also lock the primary node identity once when entering 3-node mode
        if gradient.nodes.count == 3 {
            // Only reassign lockedPrimaryID if it's nil or if the locked node no longer exists
            if lockedPrimaryID == nil {
                lockedPrimaryID = gradient.nodes.min(by: { $0.location < $1.location })?.id
            } else if !gradient.nodes.contains(where: { $0.id == lockedPrimaryID }) {
                lockedPrimaryID = gradient.nodes.min(by: { $0.location < $1.location })?.id
            }
            // Only update preferredPrimaryNodeID if it's different from lockedPrimaryID
            if gradientColorManager.preferredPrimaryNodeID != lockedPrimaryID {
                gradientColorManager.preferredPrimaryNodeID = lockedPrimaryID
            }
        } else if gradient.nodes.count == 2 {
            // No locked primary in 2-node mode; keep or choose a stable preferred primary
            lockedPrimaryID = nil
            if let pid = gradientColorManager.preferredPrimaryNodeID,
               gradient.nodes.contains(where: { $0.id == pid }) {
                // keep existing preferred - don't change it!
            } else {
                // Only reassign if the current preferred doesn't exist
                gradientColorManager.preferredPrimaryNodeID = gradient.nodes.min(by: { $0.location < $1.location })?.id
            }
        } else {
            // Single node: trivially the only node is primary
            lockedPrimaryID = nil
            if gradientColorManager.preferredPrimaryNodeID != gradient.nodes.first?.id {
                gradientColorManager.preferredPrimaryNodeID = gradient.nodes.first?.id
            }
        }
        if gradient.nodes.count == 3, let primaryID = primaryNodeID() {
            let allUnset = gradient.nodes.allSatisfy { xPositions[$0.id] == nil && yPositions[$0.id] == nil }
            if allUnset {
                // Seed primary at top-left; companions at top-right and bottom-center (same radius)
                // Primary (top-left)
                if let p = gradient.nodes.first(where: { $0.id == primaryID }) {
                    let primaryAngle: CGFloat = (.pi * 3.0) / 4.0 // 135° (top-left)
                    let pr = radius * 0.9
                    let px = center.x + cos(primaryAngle) * pr
                    let py = center.y + sin(primaryAngle) * pr
                    xPositions[p.id] = max(0, min(1, px / width))
                    yPositions[p.id] = max(0, min(1, py / height))
                    // DON'T update gradient.nodes[i].location - keep the 1st, 2nd, 3rd roles fixed!
                }
                // Companions: [top-right, bottom-center]
                let rComp = radius * 0.9
                let companionAngles: [CGFloat] = [(.pi / 4.0), (-.pi / 2.0)] // 45°, -90°
                let companions = gradient.nodes.filter { $0.id != primaryID }
                for (i, node) in companions.enumerated() where i < 2 {
                    let ang = companionAngles[i]
                    let x = center.x + cos(ang) * rComp
                    let y = center.y + sin(ang) * rComp
                    xPositions[node.id] = max(0, min(1, x / width))
                    yPositions[node.id] = max(0, min(1, y / height))
                    // DON'T update gradient.nodes[idx].location - keep the 1st, 2nd, 3rd roles fixed!
                }
            }
        }

        for n in gradient.nodes {
            // Load saved positions from the model if available
            if let savedX = n.xPosition, let savedY = n.yPosition {
                xPositions[n.id] = CGFloat(savedX)
                yPositions[n.id] = CGFloat(savedY)
            } else {
                // Use defaults if no saved positions
                if yPositions[n.id] == nil { yPositions[n.id] = defaultY(for: n) }
                if xPositions[n.id] == nil { xPositions[n.id] = CGFloat(n.location) }
                
                // Save the default positions to the model
                if let idx = gradient.nodes.firstIndex(where: { $0.id == n.id }) {
                    gradient.nodes[idx].xPosition = Double(xPositions[n.id] ?? CGFloat(n.location))
                    gradient.nodes[idx].yPosition = Double(yPositions[n.id] ?? defaultY(for: n))
                }
            }
            
            // keep points within circle
            let pt = CGPoint(x: (xPositions[n.id] ?? CGFloat(n.location)) * width,
                             y: (yPositions[n.id] ?? defaultY(for: n)) * height)
            let clamped = clampToCircle(point: pt, center: center, radius: radius)
            xPositions[n.id] = clamped.x / width
            yPositions[n.id] = clamped.y / height
            
            // Update the model with the clamped positions
            if let idx = gradient.nodes.firstIndex(where: { $0.id == n.id }) {
                gradient.nodes[idx].xPosition = Double(xPositions[n.id] ?? CGFloat(n.location))
                gradient.nodes[idx].yPosition = Double(yPositions[n.id] ?? defaultY(for: n))
            }
            
            // Update color based on position to ensure consistency
            updateNodeColorFromPosition(n, width: width, height: height, center: center, radius: radius)
        }
        // purge removed
        xPositions = xPositions.filter { pair in gradient.nodes.contains { $0.id == pair.key } }
        yPositions = yPositions.filter { pair in gradient.nodes.contains { $0.id == pair.key } }
    }

    private func updateNodeFromCanvasDrag(_ node: GradientNode, newX: CGFloat, newY: CGFloat, absolute: CGPoint, center: CGPoint, radius: CGFloat) {
        guard let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        
        // Check for haptic feedback triggers on invisible gridlines
        checkHapticFeedback(newX: newX, newY: newY)
        
        // Save visual positions in both the dictionaries (for immediate UI updates) and the model (for persistence)
        xPositions[node.id] = newX
        yPositions[node.id] = newY
        gradient.nodes[idx].xPosition = Double(newX)
        gradient.nodes[idx].yPosition = Double(newY)
        
        // DON'T update the persistent location - keep the node's role in the gradient fixed!
        // The location property determines the node's position in the gradient (primary, secondary, etc.)
        // and should NOT change when dragging on the canvas
        
        selectedNodeID = node.id
        
        // Mark the currently dragged node as the active primary for background rendering
        let designatedPrimary = primaryNodeID()
        if node.id == designatedPrimary {
            gradientColorManager.activePrimaryNodeID = node.id
        }

        // Map position on circle to HSL color - this is the key fix
        let hsla = colorFromCircle(point: absolute, center: center, radius: radius, lightness: lightness)
        let updated = colorWithPreservedAlpha(oldHex: gradient.nodes[idx].colorHex, newColor: hsla)
        gradient.nodes[idx].colorHex = updated

        // Auto-place companions only when dragging the designated primary
        // But don't change their gradient positions - they should maintain their 1st, 2nd, 3rd roles
        if gradient.nodes.count == 3, node.id == primaryNodeID() {
            autoPlaceCompanions(primary: node, center: center, radius: radius)
        } else if gradient.nodes.count == 2, node.id == primaryNodeID() {
            autoPlaceCompanions(primary: node, center: center, radius: radius)
        }

        // Push live update to background
        gradientColorManager.setImmediate(gradient)
    }

    private func checkHapticFeedback(newX: CGFloat, newY: CGFloat) {
        #if canImport(AppKit)
        // Simple gridlines that trigger haptic feedback
        let gridLines: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0] // Major gridlines
        let tolerance: CGFloat = 0.02 // How close you need to be to trigger
        
        // Check X-axis gridlines
        for line in gridLines {
            if abs(newX - line) < tolerance {
                if lastHapticSpoke != "x_\(line)" {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    lastHapticSpoke = "x_\(line)"
                }
                break
            }
        }
        
        // Check Y-axis gridlines
        for line in gridLines {
            if abs(newY - line) < tolerance {
                if lastHapticRadial != "y_\(line)" {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    lastHapticRadial = "y_\(line)"
                }
                break
            }
        }
        
        // Reset haptic state when moving away from gridlines
        if lastHapticSpoke != nil && !gridLines.contains(where: { abs(newX - $0) < tolerance }) {
            lastHapticSpoke = nil
        }
        if lastHapticRadial != nil && !gridLines.contains(where: { abs(newY - $0) < tolerance }) {
            lastHapticRadial = nil
        }
        #endif
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
        let others = gradient.nodes.filter { $0.id != primary.id }
        if gradient.nodes.count == 3 {
            // Place both companions on the same circular radius as primary, across with small angular spread
            let centerNorm = CGPoint(x: 0.5, y: 0.5)
            let dx = pX - centerNorm.x
            let dy = pY - centerNorm.y
            let baseAngle = atan2(dy, dx)
            let r = min(0.49, sqrt(dx*dx + dy*dy)) // same normalized radius
            let opposite = baseAngle + .pi
            let spread: CGFloat = 0.6 // ~34°
            let angles = [opposite - spread, opposite + spread]
            for (i, other) in others.enumerated() where i < 2 {
                let ang = angles[i]
                let pos = CGPoint(x: centerNorm.x + cos(ang) * r, y: centerNorm.y + sin(ang) * r)
                // Only update visual positions, NOT the gradient location
                xPositions[other.id] = pos.x
                yPositions[other.id] = pos.y
                // DON'T update gradient.nodes[idx].location - keep their 1st, 2nd, 3rd roles fixed!
                
                // Update the companion's color to match its new position
                if let idx = gradient.nodes.firstIndex(where: { $0.id == other.id }) {
                    // Save positions to the model
                    gradient.nodes[idx].xPosition = Double(pos.x)
                    gradient.nodes[idx].yPosition = Double(pos.y)
                    
                    let absolute = CGPoint(x: pos.x * (center.x * 2), y: pos.y * (center.y * 2))
                    let hsla = colorFromCircle(point: absolute, center: center, radius: radius, lightness: lightness)
                    let updated = colorWithPreservedAlpha(oldHex: gradient.nodes[idx].colorHex, newColor: hsla)
                    gradient.nodes[idx].colorHex = updated
                }
            }
        } else {
            // Two nodes: place the companion opposite side
            let p = CGPoint(x: pX, y: pY)
            let baseAngle = atan2(p.y - 0.5, p.x - 0.5)
            let dist = min(0.5, sqrt(pow(p.x - 0.5, 2) + pow(p.y - 0.5, 2)))
            let ang = baseAngle + .pi
            let pos = CGPoint(x: 0.5 + cos(ang) * dist, y: 0.5 + sin(ang) * dist)
            if let other = others.first {
                // Only update visual positions, NOT the gradient location
                xPositions[other.id] = pos.x
                yPositions[other.id] = pos.y
                // DON'T update gradient.nodes[idx].location - keep their 1st, 2nd roles fixed!
                
                // Update the companion's color to match its new position
                if let idx = gradient.nodes.firstIndex(where: { $0.id == other.id }) {
                    // Save positions to the model
                    gradient.nodes[idx].xPosition = Double(pos.x)
                    gradient.nodes[idx].yPosition = Double(pos.y)
                    
                    let absolute = CGPoint(x: pos.x * (center.x * 2), y: pos.y * (center.y * 2))
                    let hsla = colorFromCircle(point: absolute, center: center, radius: radius, lightness: lightness)
                    let updated = colorWithPreservedAlpha(oldHex: gradient.nodes[idx].colorHex, newColor: hsla)
                    gradient.nodes[idx].colorHex = updated
                }
            }
        }
    }

    private func primaryNodeID() -> UUID? {
        if let locked = lockedPrimaryID { return locked }
        if gradient.nodes.count <= 2 {
            return gradientColorManager.preferredPrimaryNodeID ?? gradient.nodes.min(by: { $0.location < $1.location })?.id
        }
        return gradient.nodes.min(by: { $0.location < $1.location })?.id
    }

    private func colorFromCircle(point: CGPoint, center: CGPoint, radius: CGFloat, lightness: Double) -> String {
        #if canImport(AppKit)
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        
        // Map angle to hue (0-360 degrees)
        let hue = Double(angle / (2 * .pi))
        
        // Calculate distance from center (0 = center, 1 = edge)
        let dist = min(1.0, Double(sqrt(dx*dx + dy*dy) / radius))
        
        // More intuitive color mapping:
        // - Saturation: High at center (vivid colors), very low at edges (pastels)
        // - Brightness: Much higher at edges for light pastel effect
        let saturation = max(0.1, min(1.0, 1.0 - 0.8 * dist))  // 0.1-1.0 range (very low saturation at edges)
        let brightness = max(0.3, min(1.0, lightness + 0.4 * dist))  // Much brighter at edges for pastels
        
        let ns = NSColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)
        return ns.toHexString(includeAlpha: true) ?? "#FFFFFFFF"
        #else
        return "#FFFFFFFF"
        #endif
    }

    private func updateNodeColorFromPosition(_ node: GradientNode, width: CGFloat, height: CGFloat, center: CGPoint, radius: CGFloat) {
        guard let idx = gradient.nodes.firstIndex(where: { $0.id == node.id }),
              let xPos = xPositions[node.id],
              let yPos = yPositions[node.id] else { return }
        
        let absolute = CGPoint(x: xPos * width, y: yPos * height)
        let hsla = colorFromCircle(point: absolute, center: center, radius: radius, lightness: lightness)
        let updated = colorWithPreservedAlpha(oldHex: gradient.nodes[idx].colorHex, newColor: hsla)
        gradient.nodes[idx].colorHex = updated
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
        
        // Assign gradient positions based on current count to maintain order
        let gradientPosition: Double
        if gradient.nodes.count == 0 {
            gradientPosition = 0.0  // First node is primary (0.0)
        } else if gradient.nodes.count == 1 {
            gradientPosition = 1.0  // Second node is secondary (1.0)
        } else {
            gradientPosition = 0.5  // Third node goes in the middle (0.5)
        }
        
        let new = GradientNode(id: UUID(), colorHex: color, location: gradientPosition, xPosition: 0.5, yPosition: 0.5)
        gradient.nodes.append(new)
        gradient.nodes.sort { $0.location < $1.location }
        selectedNodeID = new.id
        xPositions[new.id] = 0.5
        yPositions[new.id] = 0.5
        
        // Update color based on position after a brief delay to ensure layout is complete
        DispatchQueue.main.async {
            // We'll update the color in the next layout cycle when positions are properly set
            self.gradientColorManager.setImmediate(self.gradient)
        }
        
        gradientColorManager.setImmediate(gradient)
        // Update preferred primary mapping based on new count
        if gradient.nodes.count == 3 {
            if lockedPrimaryID == nil { lockedPrimaryID = gradient.nodes.min(by: { $0.location < $1.location })?.id }
            gradientColorManager.preferredPrimaryNodeID = lockedPrimaryID
        } else {
            gradientColorManager.preferredPrimaryNodeID = nil
        }
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
        gradientColorManager.setImmediate(gradient)
        // Update preferred primary mapping based on new count
        if gradient.nodes.count == 3 {
            if lockedPrimaryID == nil || (lockedPrimaryID != nil && !gradient.nodes.contains(where: { $0.id == lockedPrimaryID })) {
                lockedPrimaryID = gradient.nodes.min(by: { $0.location < $1.location })?.id
            }
            gradientColorManager.preferredPrimaryNodeID = lockedPrimaryID
        } else {
            lockedPrimaryID = nil
            gradientColorManager.preferredPrimaryNodeID = nil
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
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
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
