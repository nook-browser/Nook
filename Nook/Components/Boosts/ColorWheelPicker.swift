//
//  ColorWheelPicker.swift
//  Nook
//
//  Created by Claude on 11/11/2025.
//

import SwiftUI

struct ColorWheelPicker: View {
    @Binding var selectedColor: Color
    @State private var selectedHue: Double = 0.0
    @State private var selectedSaturation: Double = 0.5
    @State private var dragPosition: CGPoint = .zero

    private let wheelSize: CGFloat = 280
    private let innerPadding: CGFloat = 40

    var body: some View {
        ZStack {
            // Background pattern
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.95))
                .overlay(
                    GeometryReader { geometry in
                        Path { path in
                            let spacing: CGFloat = 8
                            let rows = Int(geometry.size.height / spacing)
                            let cols = Int(geometry.size.width / spacing)

                            for row in 0..<rows {
                                for col in 0..<cols {
                                    let x = CGFloat(col) * spacing
                                    let y = CGFloat(row) * spacing
                                    path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                                }
                            }
                        }
                        .fill(Color(white: 0.85))
                    }
                )
                .frame(width: wheelSize + innerPadding * 2, height: wheelSize + innerPadding * 2)

            // Color wheel
            ZStack {
                // Outer ring with gradient colors
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(hue: 0.0, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.1, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.2, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.3, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.4, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.5, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.6, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.7, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.8, saturation: 1.0, brightness: 1.0),
                                Color(hue: 0.9, saturation: 1.0, brightness: 1.0),
                                Color(hue: 1.0, saturation: 1.0, brightness: 1.0),
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: wheelSize, height: wheelSize)
                    .overlay(
                        // Radial gradient for saturation
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(1.0),
                                        Color.white.opacity(0.0),
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: wheelSize / 2
                                )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)

                // Selection indicator (larger circle)
                Circle()
                    .fill(selectedColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .position(calculateIndicatorPosition())

                // Inner selection indicator (smaller circle)
                Circle()
                    .fill(Color(white: 0.3))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    .position(calculateInnerIndicatorPosition())
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location)
                    }
            )
        }
        .onAppear {
            updateFromColor()
        }
        .onChange(of: selectedColor) { _, _ in
            updateFromColor()
        }
    }

    private func handleDrag(at location: CGPoint) {
        let center = CGPoint(x: wheelSize / 2 + innerPadding, y: wheelSize / 2 + innerPadding)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let maxDistance = wheelSize / 2

        // Calculate angle for hue
        var angle = atan2(dy, dx)
        if angle < 0 {
            angle += 2 * .pi
        }
        selectedHue = angle / (2 * .pi)

        // Calculate saturation based on distance from center
        selectedSaturation = min(distance / maxDistance, 1.0)

        // Update the selected color
        selectedColor = Color(hue: selectedHue, saturation: selectedSaturation, brightness: 1.0)
    }

    private func calculateIndicatorPosition() -> CGPoint {
        let center = wheelSize / 2 + innerPadding
        let angle = selectedHue * 2 * .pi
        let radius = (wheelSize / 2) * selectedSaturation

        let x = center + cos(angle) * radius
        let y = center + sin(angle) * radius

        return CGPoint(x: x, y: y)
    }

    private func calculateInnerIndicatorPosition() -> CGPoint {
        let center = wheelSize / 2 + innerPadding
        let angle = selectedHue * 2 * .pi
        let radius = (wheelSize / 2) * selectedSaturation * 0.6  // Closer to center

        let x = center + cos(angle) * radius
        let y = center + sin(angle) * radius

        return CGPoint(x: x, y: y)
    }

    private func updateFromColor() {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        #if os(macOS)
            NSColor(selectedColor).getHue(
                &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #else
            UIColor(selectedColor).getHue(
                &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif

        selectedHue = hue
        selectedSaturation = saturation
    }
}

#Preview {
    ColorWheelPicker(selectedColor: .constant(Color(hue: 0.0, saturation: 0.5, brightness: 1.0)))
        .padding(40)
}
