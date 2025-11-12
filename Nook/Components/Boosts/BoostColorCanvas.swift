//
//  BoostColorCanvas.swift
//  Nook
//
//  Created by Jude on 11/11/2025.
//

import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

// MARK: - BoostColorCanvas
// Circular canvas for picking tint color (similar to GradientCanvasEditor but single color)
struct BoostColorCanvas: View {
    @Binding var selectedColor: Color
    var onColorChange: ((Color) -> Void)?

    @State private var handlePosition: CGPoint?
    @State private var lightness: Double = 0.6

    private let cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let padding: CGFloat = 24
            let center = CGPoint(x: width / 2, y: height / 2)
            let radius = min(width, height) / 2 - padding

            ZStack {
                // Dot grid background
                DotGrid()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)

                // Draggable color handle
                if let position = handlePosition {
                    let clamped = clampToCircle(point: position, center: center, radius: radius)

                    ColorHandle(color: selectedColor, size: 40)
                        .position(clamped)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let clamped = clampToCircle(
                                        point: value.location, center: center, radius: radius)
                                    handlePosition = clamped
                                    updateColorFromPosition(clamped, center: center, radius: radius)
                                }
                        )
                }

                // Border stroke
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onAppear {
                if handlePosition == nil {
                    // Initialize handle position from current color
                    handlePosition = positionFromColor(
                        selectedColor, center: center, radius: radius)
                }
            }
        }
        .frame(height: 280)
    }

    // MARK: - Helper Methods

    private func clampToCircle(point: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance <= radius {
            return point
        } else {
            let angle = atan2(dy, dx)
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func updateColorFromPosition(_ position: CGPoint, center: CGPoint, radius: CGFloat) {
        let color = colorFromCircle(
            point: position, center: center, radius: radius, lightness: lightness)
        selectedColor = color
        onColorChange?(color)
    }

    private func colorFromCircle(
        point: CGPoint, center: CGPoint, radius: CGFloat, lightness: Double
    ) -> Color {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // Angle determines hue (0-360 degrees)
        var angle = atan2(dy, dx) * 180.0 / .pi
        if angle < 0 { angle += 360 }
        let hue = angle / 360.0

        // Distance from center determines saturation (0-1)
        let saturation = min(1.0, distance / radius)

        // Use fixed lightness
        return Color(hue: hue, saturation: saturation, brightness: lightness)
    }

    private func positionFromColor(_ color: Color, center: CGPoint, radius: CGFloat) -> CGPoint {
        #if canImport(AppKit)
            let nsColor = NSColor(color)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            nsColor.usingColorSpace(.deviceRGB)?.getHue(
                &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            // Update lightness from color
            lightness = brightness

            // Convert hue to angle (0-360 degrees)
            let angle = hue * 360.0 * .pi / 180.0

            // Convert saturation to distance
            let distance = saturation * radius

            return CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            )
        #else
            return center
        #endif
    }
}

// MARK: - ColorHandle
private struct ColorHandle: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                .frame(width: size, height: size)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - DotGrid (reuse from GradientCanvasEditor)
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let dotSize: CGFloat = 2
            let spacing: CGFloat = 12
            let dotColor = Color.primary.opacity(0.08)

            let cols = Int(size.width / spacing)
            let rows = Int(size.height / spacing)

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var color = Color.red

    return BoostColorCanvas(selectedColor: $color) { newColor in
        print("Color changed: \(newColor)")
    }
    .padding(40)
}
