// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceThemeEditor.swift
//  NookUI
//
//  Edit Theme Color: appearance, a color canvas with one to three pucks, presets, intensity and
//  a noise knob. Every change writes through to the space, so the window recolors while you drag.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
import NookDesign
import NookTabsCore
import NookWeb

public struct SpaceThemeEditor: View {
    @Environment(TabsController.self) private var tabs

    let spaceID: UUID
    @State private var theme: SpaceTheme

    public init(space: SpaceRecord) {
        self.spaceID = space.id
        self._theme = State(initialValue: space.theme ?? SpaceTheme(accentHex: space.accentHex))
    }

    public var body: some View {
        SpaceThemePanel(theme: $theme)
            .onChange(of: theme) { _, newValue in
                tabs.setTheme(newValue, forSpace: spaceID)
            }
    }
}

/// The editor itself, over a theme it does not save: Create a Space edits one before the
/// space exists.
public struct SpaceThemePanel: View {
    @Environment(\.colorScheme) private var systemScheme
    @Binding var theme: SpaceTheme

    private let width: CGFloat = 300
    private let canvasHeight: CGFloat = 300

    public init(theme: Binding<SpaceTheme>) {
        self._theme = theme
    }

    private var isDark: Bool { theme.isDark(systemDark: systemScheme == .dark) }

    public var body: some View {
        VStack(spacing: NookDesign.Spacing.lg) {
            ThemeCanvas(theme: $theme, isDark: isDark)
                .frame(height: canvasHeight)
            ThemeSwatches(theme: $theme)
            HStack(spacing: NookDesign.Spacing.lg) {
                Slider(value: $theme.intensity) { Text("Intensity") }
                    .labelsHidden()
                    .accessibilityLabel("Intensity")
                NoiseKnob(theme: $theme)
            }
        }
        .padding(NookDesign.Spacing.lg)
        .frame(width: width)
        // The panel takes the appearance it is choosing, as Arc's does.
        .preferredColorScheme(theme.mode == .auto ? nil : (isDark ? .dark : .light))
    }
}

extension SpaceTheme {
    /// One of Arc's Drab presets at random, for a new space, so no two read alike by default.
    public static func randomPreset() -> SpaceTheme {
        SpaceTheme(points: [(ThemePresets.pages[1].randomElement()?.point ?? .center)])
    }
}

// MARK: - Canvas

/// Also the Boost panel's color pad, which passes `showsControls: false` (no appearance or second color).
struct ThemeCanvas: View {
    @Binding var theme: SpaceTheme
    let isDark: Bool
    var showsControls = true

    @State private var dragging = false
    @State private var grabOffset: CGSize = .zero

    private let puckSize: CGFloat = 40
    private let ringWidth: CGFloat = 4
    private let dotPitch: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            ZStack {
                NookDesign.Radius.shape(NookDesign.Radius.lg)
                    .fill(NookDesign.Surface.fill)
                dotGrid
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
                // The key color is the one to drag; the others follow it around the wheel.
                ForEach(shownIndices, id: \.self) { index in
                    puck(theme.points[index], active: dragging && index == 0, isKey: index == 0)
                        .position(position(of: theme.points[index], in: area))
                }
            }
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
            .gesture(drag(in: area))
            .overlay(alignment: .top) {
                if showsControls {
                    ModePicker(mode: $theme.mode)
                        .padding(.top, NookDesign.Spacing.md)
                }
            }
            .overlay(alignment: .bottom) {
                if showsControls {
                    pointButtons
                        .padding(.bottom, NookDesign.Spacing.md)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme color")
    }

    private var dotGrid: some View {
        Canvas { context, size in
            let dot = CGSize(width: 1.5, height: 1.5)
            var path = Path()
            var y = dotPitch / 2
            while y < size.height {
                var x = dotPitch / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(origin: CGPoint(x: x, y: y), size: dot))
                    x += dotPitch
                }
                y += dotPitch
            }
            context.fill(path, with: .color(.primary.opacity(0.14)))
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    /// Boost's pad shows only its one dot.
    private var shownIndices: [Int] { showsControls ? Array(theme.points.indices) : [0] }

    private func puck(_ point: SpaceTheme.Point, active: Bool, isKey: Bool) -> some View {
        Circle()
            .fill(Color(SpaceTheme.puckColor(point, dark: isDark)))
            .overlay(Circle().strokeBorder(.white, lineWidth: ringWidth))
            .frame(width: puckSize, height: puckSize)
            .shadow(color: .black.opacity(0.25), radius: active ? 10 : 4, y: active ? 4 : 1)
            .scaleEffect((active ? 1.1 : 1) * (isKey ? 1 : 0.7))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
            .allowsHitTesting(false)
    }

    // MARK: Geometry

    /// Pucks travel inside an inset rect so a rim color never hangs off the canvas.
    private func inset(_ area: CGSize) -> CGRect {
        CGRect(origin: .zero, size: area).insetBy(dx: puckSize / 2, dy: puckSize / 2)
    }

    private func position(of point: SpaceTheme.Point, in area: CGSize) -> CGPoint {
        let rect = inset(area)
        return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func point(at location: CGPoint, in area: CGSize) -> SpaceTheme.Point {
        let rect = inset(area)
        return SpaceTheme.Point(x: (location.x - rect.minX) / rect.width, y: (location.y - rect.minY) / rect.height)
    }

    private func drag(in area: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragging {
                    // A press on the key puck keeps the offset from where it was grabbed; a press
                    // on empty canvas brings the key puck to the pointer.
                    let center = position(of: theme.points[0], in: area)
                    let onPuck = hypot(center.x - value.startLocation.x, center.y - value.startLocation.y) <= puckSize / 2
                    grabOffset = onPuck
                        ? CGSize(width: center.x - value.startLocation.x, height: center.y - value.startLocation.y)
                        : .zero
                    dragging = true
                    if !onPuck {
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                            theme.points[0] = point(at: value.location, in: area)
                        }
                        theme.tone = nil
                        return
                    }
                }
                let location = CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height)
                let moved = point(at: location, in: area)
                if moved != theme.points[0] { theme.tone = nil }
                theme.points[0] = moved
            }
            .onEnded { _ in dragging = false }
    }

    // MARK: Add / remove a color

    private var pointButtons: some View {
        HStack(spacing: NookDesign.Spacing.xl) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { theme.colorCount -= 1 }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(theme.colorCount <= 1)
            .help("Remove color")

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                    theme.wheel = theme.wheel == .analogous ? .complementary : .analogous
                }
            } label: {
                Image(systemName: theme.wheel == .analogous ? "circle.lefthalf.filled" : "circle.righthalf.filled")
            }
            .disabled(theme.colorCount <= 1)
            .help(theme.wheel == .analogous ? "Analogous colors" : "Complementary colors")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { theme.colorCount += 1 }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(theme.colorCount >= SpaceTheme.maxPoints)
            .help("Add color")
        }
        .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
        .foregroundStyle(.secondary)
        .buttonStyle(NookIconButtonStyle())
    }
}

// MARK: - Mode

private struct ModePicker: View {
    @Binding var mode: SpaceTheme.Mode

    var body: some View {
        HStack(spacing: NookDesign.Spacing.xs) {
            item(.auto, symbol: "sparkles", help: "Automatic")
            item(.light, symbol: "sun.max", help: "Light")
            item(.dark, symbol: "moon.stars", help: "Dark")
        }
    }

    private func item(_ value: SpaceTheme.Mode, symbol: String, help: String) -> some View {
        Button {
            withAnimation(NookDesign.Motion.standard) { mode = value }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                .foregroundStyle(mode == value ? .primary : .secondary)
                .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                .background(
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .fill(mode == value ? NookDesign.Surface.fillPressed : .clear))
                .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

// MARK: - Presets

/// Arc's three preset pages of nine, stored there in Display P3 (`ColorPicker*1..9` in
/// ARC_SpaceStyleEditor). A preset sets the key color.
enum ThemePresets {
    struct Preset {
        let point: SpaceTheme.Point
        let swatch: Color
        /// Greys carry no hue, only a tone.
        var tone: Double? = nil
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double) -> Preset {
        Preset(point: .init(rgb: ThemeRGB(displayP3: r, g, b)), swatch: Color(.displayP3, red: r, green: g, blue: b))
    }

    private static func grey(_ v: Double) -> Preset {
        Preset(point: .center, swatch: Color(.displayP3, white: v), tone: v)
    }

    static let pages: [[Preset]] = [
        [(0.994, 0.984, 0.981), (0.985, 0.917, 0.951), (0.924, 0.825, 0.918), (0.968, 0.804, 0.822), (0.98, 0.882, 0.834),
         (0.996, 0.977, 0.906), (0.894, 0.988, 0.926), (0.88, 0.95, 0.984), (0.774, 0.776, 0.888)].map { color($0.0, $0.1, $0.2) },
        [(0.294, 0.231, 0.345), (0.384, 0.22, 0.337), (0.522, 0.267, 0.267), (0.655, 0.439, 0.282), (0.82, 0.706, 0.416),
         (0.804, 0.8, 0.659), (0.518, 0.659, 0.522), (0.204, 0.376, 0.294), (0.176, 0.267, 0.408)].map { color($0.0, $0.1, $0.2) },
        [1.0, 0.9, 0.8, 0.7, 0.5, 0.4, 0.2, 0.1, 0.0].map(grey),
    ]
}

private struct ThemeSwatches: View {
    @Binding var theme: SpaceTheme
    @State private var page = 0

    private let swatchSize: CGFloat = 22

    var body: some View {
        HStack(spacing: NookDesign.Spacing.xxs) {
            arrow("chevron.left", to: page - 1)
            HStack(spacing: NookDesign.Spacing.xs) {
                ForEach(ThemePresets.pages[page].indices, id: \.self) { index in
                    swatch(ThemePresets.pages[page][index])
                }
            }
            .frame(maxWidth: .infinity)
            .id(page)
            .transition(.opacity)
            arrow("chevron.right", to: page + 1)
        }
    }

    private func arrow(_ symbol: String, to target: Int) -> some View {
        Button {
            withAnimation(NookDesign.Motion.quick) { page = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: NookDesign.Size.rowGlyph, weight: .semibold))
        }
        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton))
        .foregroundStyle(.secondary)
        .disabled(!ThemePresets.pages.indices.contains(target))
        .accessibilityLabel(target < page ? "Previous presets" : "Next presets")
    }

    private func swatch(_ preset: ThemePresets.Preset) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                theme.points[0] = preset.point
                theme.tone = preset.tone
            }
        } label: {
            Circle()
                .fill(preset.swatch)
                .overlay(Circle().strokeBorder(NookDesign.Surface.hairline))
                .frame(width: swatchSize, height: swatchSize)
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Noise knob

/// Arc's dial: a disc showing the current noise texture. Click cycles the texture; dragging
/// around it or scrolling over it sets how much noise the chrome gets.
private struct NoiseKnob: View {
    @Binding var theme: SpaceTheme

    private let steps = 20
    private let sweep: Double = 135   // degrees each side of straight up

    var body: some View {
        let size = NookDesign.Size.themeKnob
        ZStack {
            Circle().fill(NookDesign.Surface.fillPressed)
            FilmGrain(opacity: 1, overlay: theme.overlay, blend: .normal)
            Capsule()
                .fill(.primary)
                .frame(width: NookDesign.Spacing.xxs + 1, height: NookDesign.Spacing.md)
                .offset(y: -(size / 2 - NookDesign.Spacing.md))
                .rotationEffect(.degrees(-sweep + theme.grain * 2 * sweep))
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(NookDesign.Surface.hairline))
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            let all = SpaceTheme.Overlay.allCases
            let next = all.firstIndex(of: theme.overlay).map { all[($0 + 1) % all.count] } ?? .grain
            withAnimation(NookDesign.Motion.quick) { theme.overlay = next }
            Haptics.alignment()
        }
        .gesture(
            DragGesture(minimumDistance: 4).onChanged { drag in
                let dx = drag.location.x - size / 2, dy = drag.location.y - size / 2
                let angle = atan2(dx, -dy) * 180 / .pi
                // Past the ends, stay at whichever end the knob is nearer.
                set(abs(angle) > sweep ? (theme.grain > 0.5 ? 1 : 0) : (angle + sweep) / (2 * sweep))
            })
        #if os(macOS)
        .overlay { ScrollCatcher { set(theme.grain + $0) }.allowsHitTesting(true) }
        #endif
        .help("Cycle noise texture")
        .accessibilityElement()
        .accessibilityLabel("Cycle noise texture")
        .accessibilityValue("\(Int((theme.grain * 100).rounded())) percent")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { theme.overlay = SpaceTheme.Overlay.allCases[(SpaceTheme.Overlay.allCases.firstIndex(of: theme.overlay)! + 1) % SpaceTheme.Overlay.allCases.count] }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(theme.grain + 0.1)
            case .decrement: set(theme.grain - 0.1)
            @unknown default: break
            }
        }
    }

    private func set(_ raw: Double) {
        let next = min(1, max(0, raw))
        if Int(next * Double(steps)) != Int(theme.grain * Double(steps)) { Haptics.alignment() }
        theme.grain = next
    }
}

#if os(macOS)
/// Reports scroll-wheel deltas over its area. It takes hits only for scroll events, so clicks
/// and drags pass through to the knob under it.
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: (Double) -> Void = { _ in }
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }
        private var engaged = false
        override func scrollWheel(with event: NSEvent) {
            // Momentum, and gestures that began elsewhere, belong to whatever scrolls underneath.
            if !event.momentumPhase.isEmpty { nextResponder?.scrollWheel(with: event); return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { engaged = true }
            let mouseWheel = event.phase.isEmpty
            guard mouseWheel || engaged else { nextResponder?.scrollWheel(with: event); return }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { engaged = false }
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            if event.hasPreciseScrollingDeltas {
                onScroll(Double(delta) * 0.01)
            } else if delta != 0 {
                onScroll(delta > 0 ? 0.05 : -0.05)
            }
        }
    }
}
#endif
