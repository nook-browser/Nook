// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceThemeEditor.swift
//  NookUI
//
//  Edit Theme Color: appearance, a color canvas with one or two pucks, presets, intensity and
//  grain. Every change writes through to the space, so the window recolors while you drag.
//

import SwiftUI
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
                SquiggleSlider(value: $theme.intensity)
                GrainDial(value: $theme.grain)
            }
        }
        .padding(NookDesign.Spacing.lg)
        .frame(width: width)
        // The panel takes the appearance it is choosing, as Arc's does.
        .preferredColorScheme(theme.mode == .auto ? nil : (isDark ? .dark : .light))
    }
}

extension SpaceTheme {
    /// A preset at random, for a new space, so no two read alike by default.
    public static func randomPreset() -> SpaceTheme {
        let colored = ThemeSwatches.pages.flatMap { $0 }.filter { $0 != [.center] }
        return SpaceTheme(points: colored.randomElement() ?? [.center])
    }
}

// MARK: - Canvas

/// Also the Boost panel's color pad, which passes `showsControls: false` (no appearance or second color).
struct ThemeCanvas: View {
    @Binding var theme: SpaceTheme
    let isDark: Bool
    var showsControls = true

    @State private var dragging: Int?
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
                ForEach(theme.points.indices, id: \.self) { index in
                    puck(theme.points[index], active: dragging == index)
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

    private func puck(_ point: SpaceTheme.Point, active: Bool) -> some View {
        Circle()
            .fill(Color(SpaceTheme.puckColor(point, dark: isDark)))
            .overlay(Circle().strokeBorder(.white, lineWidth: ringWidth))
            .frame(width: puckSize, height: puckSize)
            .shadow(color: .black.opacity(0.25), radius: active ? 10 : 4, y: active ? 4 : 1)
            .scaleEffect(active ? 1.1 : 1)
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
                if dragging == nil {
                    // Grab the nearest puck; a press on one keeps the offset from where it was
                    // grabbed, a press on empty canvas brings the nearest puck to the pointer.
                    let centers = theme.points.map { position(of: $0, in: area) }
                    let nearest = centers.indices.min {
                        hypot(centers[$0].x - value.startLocation.x, centers[$0].y - value.startLocation.y)
                            < hypot(centers[$1].x - value.startLocation.x, centers[$1].y - value.startLocation.y)
                    } ?? 0
                    let center = centers[nearest]
                    let onPuck = hypot(center.x - value.startLocation.x, center.y - value.startLocation.y) <= puckSize / 2
                    grabOffset = onPuck
                        ? CGSize(width: center.x - value.startLocation.x, height: center.y - value.startLocation.y)
                        : .zero
                    dragging = nearest
                    if !onPuck {
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                            theme.points[nearest] = point(at: value.location, in: area)
                        }
                        return
                    }
                }
                guard let index = dragging else { return }
                let location = CGPoint(x: value.location.x + grabOffset.width, y: value.location.y + grabOffset.height)
                theme.points[index] = point(at: location, in: area)
            }
            .onEnded { _ in dragging = nil }
    }

    // MARK: Add / remove a color

    private var pointButtons: some View {
        HStack(spacing: NookDesign.Spacing.xl) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { _ = theme.points.popLast() }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(theme.points.count <= 1)
            .help("Remove color")

            Button {
                let first = theme.points[0]
                let second = SpaceTheme.Point(hue: first.hue + 60, saturation: max(0.6, first.saturation))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { theme.points.append(second) }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(theme.points.count >= SpaceTheme.maxPoints)
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

private struct ThemeSwatches: View {
    @Binding var theme: SpaceTheme
    @State private var page = 0

    private let swatchSize: CGFloat = 22

    /// Page one is single colors, page two pairs. Hues are OKLCH degrees.
    static let pages: [[[SpaceTheme.Point]]] = {
        let neutral = SpaceTheme.Point.center
        let hues: [Double] = [355, 320, 25, 55, 95, 150, 230, 275]
        let singles = [[neutral]] + hues.map { [SpaceTheme.Point(hue: $0, saturation: $0 == 275 ? 0.45 : 0.85)] }
        let pairs: [[SpaceTheme.Point]] = [(355, 55), (320, 230), (25, 95), (55, 150), (150, 230), (230, 320), (275, 355), (95, 150), (200, 25)]
            .map { [SpaceTheme.Point(hue: $0.0, saturation: 0.85), SpaceTheme.Point(hue: $0.1, saturation: 0.85)] }
        return [singles, pairs]
    }()

    var body: some View {
        HStack(spacing: NookDesign.Spacing.xxs) {
            arrow("chevron.left", to: page - 1)
            HStack(spacing: NookDesign.Spacing.xs) {
                ForEach(Self.pages[page].indices, id: \.self) { index in
                    swatch(Self.pages[page][index])
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
        .disabled(!Self.pages.indices.contains(target))
        .accessibilityLabel(target < page ? "Previous presets" : "Next presets")
    }

    private func swatch(_ points: [SpaceTheme.Point]) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { theme.points = points }
        } label: {
            Circle()
                .fill(LinearGradient(
                    colors: points.map { Color(SpaceTheme.swatchColor($0)) },
                    startPoint: .topLeading, endPoint: .bottomTrailing))
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

// MARK: - Intensity

/// A slider whose filled part is a sine wave: the larger the value, the taller the wave.
private struct SquiggleSlider: View {
    @Binding var value: Double

    private let height: CGFloat = 48
    private let trackHeight: CGFloat = 22
    private let thumbWidth: CGFloat = 26
    private let wavelength: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width - thumbWidth
            let thumbX = travel * value
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NookDesign.Surface.fill)
                    .frame(height: trackHeight)
                SineWave(amplitude: 3 + 10 * value, wavelength: wavelength)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: max(0, thumbX + thumbWidth / 2), height: height)
                    .padding(.leading, NookDesign.Spacing.sm)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, thumbX))
                    }
                Capsule()
                    .fill(.white)
                    .frame(width: thumbWidth, height: height)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard travel > 0 else { return }
                    value = min(1, max(0, (drag.location.x - thumbWidth / 2) / travel))
                })
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Intensity")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}

private struct SineWave: Shape {
    var amplitude: CGFloat
    let wavelength: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: mid))
        var x = rect.minX
        while x <= rect.maxX {
            path.addLine(to: CGPoint(x: x, y: mid - amplitude * sin((x - rect.minX) / wavelength * 2 * .pi)))
            x += 1
        }
        return path
    }
}

// MARK: - Grain

/// A rotary knob over a ring of dots. The dots up to the value light up and the face shows
/// as much grain as the chrome will.
private struct GrainDial: View {
    @Binding var value: Double

    private let size: CGFloat = 72
    private let knob: CGFloat = 44
    private let dotCount = 24
    private let startAngle: Double = -25   // degrees clockwise from 12 o'clock
    private let travel: Double = 310

    var body: some View {
        let ring = size / 2 - NookDesign.Spacing.xs
        ZStack {
            ForEach(0..<dotCount, id: \.self) { index in
                let fraction = Double(index) / Double(dotCount - 1)
                Circle()
                    .fill(fraction <= value ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 3, height: 3)
                    .offset(y: -ring)
                    .rotationEffect(.degrees(startAngle + fraction * travel))
            }
            Circle()
                .fill(Color.gray)
                .overlay { FilmGrain(opacity: 0.5 + 0.5 * value) }
                .clipShape(Circle())
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Capsule()
                .fill(.white)
                .frame(width: 4, height: 11)
                .offset(y: -ring)
                .rotationEffect(.degrees(startAngle + value * travel))
                .shadow(color: .black.opacity(0.2), radius: 1)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                let dx = drag.location.x - size / 2, dy = drag.location.y - size / 2
                var angle = atan2(dx, -dy) * 180 / .pi - startAngle
                if angle < 0 { angle += 360 }
                // In the gap between the ends, stay at whichever end the knob is nearer.
                let next = angle > travel ? (value > 0.5 ? 1 : 0) : angle / travel
                if Int(next * Double(dotCount - 1)) != Int(value * Double(dotCount - 1)) { Haptics.alignment() }
                value = next
            })
        .accessibilityElement()
        .accessibilityLabel("Grain")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}
