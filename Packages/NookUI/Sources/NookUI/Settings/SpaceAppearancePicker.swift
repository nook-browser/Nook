// Licensed under GPL-3.0. See LICENSE.

import NookDesign
import NookTabsCore
import SwiftUI

/// A native, live editor for a space's colors, material and appearance.
public struct SpaceAppearancePicker: View {
    @Binding private var appearance: SpaceAppearance
    @Environment(\.self) private var environment
    @State private var selection: UUID?
    @State private var paletteIndex = 0
    @State private var dragAnchor: DragAnchor?

    private struct DragAnchor {
        var node: SpaceAppearance.Node
        var location: CGPoint
    }

    private let palettes = [
        ["#F5F0DF", "#EFB4CE", "#E7C2E7", "#D87587", "#F08770", "#E1D17E", "#53E2AF", "#929DB9"],
        ["#CCD4FF", "#9FC5E8", "#A5D6CB", "#C5D6A4", "#F5D4A4", "#D8B7A6", "#BAA7CC", "#A7ABB4"]
    ]

    public init(appearance: Binding<SpaceAppearance>) {
        self._appearance = appearance
    }

    private var selectedID: UUID? {
        appearance.nodes.first(where: { $0.id == selection })?.id ?? appearance.nodes.first?.id
    }

    public var body: some View {
        VStack(spacing: 14) {
            stage
            palette
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    waveSlider
                    Text("Intensity").font(.caption).foregroundStyle(.secondary)
                }
                grainDial
            }
            HStack {
                ColorPicker("Custom color", selection: selectedColor, supportsOpacity: false)
                    .font(.caption)
                Spacer()
                Button("Reset") {
                    appearance = SpaceAppearance(nodes: [], mode: appearance.mode)
                    selection = nil
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 350)
        .preferredColorScheme(appearance.mode == .system ? nil : appearance.mode == .dark ? .dark : .light)
    }

    private var stage: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.035))
                Canvas { context, canvasSize in
                    for x in stride(from: 6.0, to: canvasSize.width, by: 6) {
                        for y in stride(from: 6.0, to: canvasSize.height, by: 6) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(.primary.opacity(0.09)))
                        }
                    }
                }
                .allowsHitTesting(false)
                ForEach(appearance.nodes) { node in
                    Circle()
                        .fill(Color(hex: node.colorHex))
                        .frame(width: 38, height: 38)
                        .overlay(Circle().strokeBorder(.white.opacity(selectedID == node.id ? 1 : 0.45), lineWidth: selectedID == node.id ? 5 : 2))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                        .position(x: 24 + node.x * (size.width - 48), y: 60 + node.y * (size.height - 120))
                        .onTapGesture { selection = node.id }
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("colorStage"))
                            .onChanged { value in
                                selection = node.id
                                if dragAnchor?.node.id != node.id,
                                   let current = appearance.nodes.first(where: { $0.id == node.id }) {
                                    dragAnchor = DragAnchor(node: current, location: value.startLocation)
                                }
                                moveNode(node.id, location: value.location, size: size)
                            }
                            .onEnded { _ in dragAnchor = nil })
                        .accessibilityElement()
                        .accessibilityLabel("Color \((appearance.nodes.firstIndex(where: { $0.id == node.id }) ?? 0) + 1)")
                        .accessibilityValue(node.colorHex)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { selection = node.id }
                        .help("Drag to change color, or select and use Custom color")
                }
                VStack {
                    HStack(spacing: 22) {
                        modeButton("Use app appearance", symbol: "sparkles", mode: .system)
                        modeButton("Light appearance", symbol: "sun.max.fill", mode: .light)
                        modeButton("Dark appearance", symbol: "moon.fill", mode: .dark)
                    }
                    .padding(.top, 10)
                    Spacer()
                    HStack(spacing: 26) {
                        Button(action: addColor) { Image(systemName: "plus") }
                            .disabled(appearance.nodes.count >= 3)
                            .help("Add color").accessibilityLabel("Add color")
                        Button(action: removeColor) { Image(systemName: "minus") }
                            .disabled(appearance.nodes.isEmpty)
                            .help("Remove selected color").accessibilityLabel("Remove selected color")
                        Button(action: harmonize) { Image(systemName: "circle.grid.2x2") }
                            .disabled(appearance.nodes.count <= 1)
                            .help("Arrange harmonious colors").accessibilityLabel("Arrange harmonious colors")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                }
            }
            .coordinateSpace(name: "colorStage")
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 280)
    }

    private func modeButton(_ label: String, symbol: String, mode: SpaceAppearance.Mode) -> some View {
        Button { appearance.mode = mode } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .background(appearance.mode == mode ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(appearance.mode == mode ? .isSelected : [])
    }

    private var palette: some View {
        HStack(spacing: 7) {
            Button { paletteIndex = (paletteIndex + palettes.count - 1) % palettes.count } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous palette")
            ForEach(palettes[paletteIndex], id: \.self) { hex in
                Button { setSelectedHex(hex) } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 27, height: 27)
                }
                .accessibilityLabel("Use color \(hex)")
                .help(hex)
            }
            Button { paletteIndex = (paletteIndex + 1) % palettes.count } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next palette")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
    }

    private var waveSlider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10)).frame(height: 13)
                Wave().stroke(.primary.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(height: 22)
                Capsule().fill(.primary).frame(width: 13, height: 38)
                    .offset(x: CGFloat((appearance.opacity - 0.3) / 0.5) * (width - 13))
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                setIntensity(0.3 + 0.5 * min(1, max(0, (value.location.x - 6.5) / max(1, width - 13))))
            })
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Color intensity")
        .accessibilityValue("\(Int(appearance.opacity * 100)) percent")
        .accessibilityAdjustableAction { direction in
            setIntensity(appearance.opacity + (direction == .increment ? 0.025 : -0.025))
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { setIntensity(appearance.opacity - 0.025); return .handled }
        .onKeyPress(.rightArrow) { setIntensity(appearance.opacity + 0.025); return .handled }
    }

    private var grainDial: some View {
        VStack(spacing: 3) {
            grainDialControl
            Text("Grain").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Grain")
        .accessibilityValue("\(Int(appearance.grain * 100)) percent")
        .accessibilityAdjustableAction { direction in
            setGrain(appearance.grain + (direction == .increment ? 1.0 / 15 : -1.0 / 15))
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { setGrain(appearance.grain - 1.0 / 15); return .handled }
        .onKeyPress(.rightArrow) { setGrain(appearance.grain + 1.0 / 15); return .handled }
    }

    private var grainDialControl: some View {
        ZStack {
            ForEach(0..<16) { tick in
                Circle().fill(.primary.opacity(Double(tick) / 15 <= appearance.grain ? 0.55 : 0.13))
                    .frame(width: 3, height: 3)
                    .offset(y: -25).rotationEffect(.degrees(-135 + Double(tick) * 18))
            }
            Circle().fill(.primary.opacity(0.05)).frame(width: 36, height: 36)
                .overlay(Circle().stroke(.primary.opacity(0.1)))
            Capsule().fill(.primary.opacity(0.8)).frame(width: 3, height: 8)
                .offset(y: -21).rotationEffect(.degrees(-135 + appearance.grain * 270))
        }
        .frame(width: 54, height: 54)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let angle: Double = atan2(Double(value.location.x - 27), Double(27 - value.location.y)) * 180 / Double.pi
            setGrain((angle + 135) / 270)
        })
    }

    // Twenty intensity intervals give a perceptible detent about every 10 points
    // along the slider; grain follows its fifteen visible intervals.
    private func setIntensity(_ value: Double) {
        let step = (min(0.8, max(0.3, value)) - 0.3) / 0.025
        let next = 0.3 + step.rounded() * 0.025
        let previousStep = ((appearance.opacity - 0.3) / 0.025).rounded()
        appearance.opacity = next
        if previousStep != step.rounded() {
            Haptics.alignment()
        }
    }

    private func setGrain(_ value: Double) {
        let step = (min(1, max(0, value)) * 15).rounded()
        let previousStep = (appearance.grain * 15).rounded()
        appearance.grain = step / 15
        if previousStep != step {
            Haptics.alignment()
        }
    }

    private var selectedColor: Binding<Color> {
        Binding(get: { Color(hex: appearance.nodes.first(where: { $0.id == selectedID })?.colorHex ?? "#CCD4FF") },
                set: { setSelectedHex($0.hexString(in: environment)) })
    }

    private func setSelectedHex(_ hex: String) {
        if let index = appearance.nodes.firstIndex(where: { $0.id == selectedID }) {
            appearance.nodes[index].colorHex = hex
        } else {
            let node = SpaceAppearance.Node(colorHex: hex)
            appearance.nodes.append(node)
            selection = node.id
        }
    }

    private func addColor() {
        guard appearance.nodes.count < 3 else { return }
        let index = appearance.nodes.count
        let node = SpaceAppearance.Node(colorHex: palettes[paletteIndex][index * 2], x: index == 1 ? 0.8 : 0.5, y: index == 1 ? 0.35 : 0.8)
        appearance.nodes.append(node)
        selection = node.id
    }

    private func removeColor() {
        guard let id = selectedID else { return }
        appearance.nodes.removeAll { $0.id == id }
        selection = appearance.nodes.first?.id
    }

    private func harmonize() {
        var theme = appearance
        guard theme.nodes.count > 1, let primary = theme.nodes.first else { return }
        let base = hsl(primary.colorHex)
        // Keep the primary color exactly; derive complementary or triadic companions.
        for index in 1..<theme.nodes.count {
            let offset = Double(index) / Double(theme.nodes.count)
            theme.nodes[index].colorHex = hex(hue: base.hue + offset, saturation: base.saturation, lightness: base.lightness)
        }
        appearance = theme
    }

    private func moveNode(_ id: UUID, location: CGPoint, size: CGSize) {
        guard let anchor = dragAnchor, anchor.node.id == id else { return }
        var theme = appearance
        guard let index = theme.nodes.firstIndex(where: { $0.id == id }) else { return }
        let dx = Double((location.x - anchor.location.x) / (size.width - 48))
        let dy = Double((location.y - anchor.location.y) / (size.height - 120))
        theme.nodes[index].x = min(1, max(0, anchor.node.x + dx))
        theme.nodes[index].y = min(1, max(0, anchor.node.y + dy))
        let base = hsl(anchor.node.colorHex)
        // Relative changes prevent palette and custom colors jumping on the first drag.
        theme.nodes[index].colorHex = hex(
            hue: base.hue + dx,
            saturation: base.saturation,
            lightness: min(1, max(0, base.lightness - dy))
        )
        appearance = theme
    }

    private func hsl(_ hex: String) -> (hue: Double, saturation: Double, lightness: Double) {
        let rgb = Color(hex: hex).resolve(in: environment)
        let r = Double(rgb.red), g = Double(rgb.green), b = Double(rgb.blue)
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if maximum == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6 }
        else if maximum == g { hue = ((b - r) / delta + 2) / 6 }
        else { hue = ((r - g) / delta + 4) / 6 }
        return (hue < 0 ? hue + 1 : hue, saturation, lightness)
    }

    private func hex(hue: Double, saturation: Double, lightness: Double) -> String {
        let wrappedHue = hue - floor(hue)
        let brightness = lightness + saturation * min(lightness, 1 - lightness)
        let hsvSaturation = brightness == 0 ? 0 : 2 * (1 - lightness / brightness)
        return Color(hue: wrappedHue, saturation: hsvSaturation, brightness: brightness).hexString(in: environment)
    }

}

private struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for step in 0...120 {
                let x = CGFloat(step) / 120 * rect.width
                let y = rect.midY + sin(CGFloat(step) / 120 * .pi * 10) * rect.height * 0.42
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
