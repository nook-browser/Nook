//
//  ToolExecutionGlowView.swift
//  Nook
//
//  Animated gradient glow effect during AI tool execution
//

import SwiftUI

struct ToolExecutionGlowView: View {
    @State private var rotation1: Double = 0
    @State private var rotation2: Double = 0
    @State private var rotation3: Double = 0

    private let colors: [Color] = [
        Color(hex: "BC82F3"),
        Color(hex: "C686FF"),
        Color(hex: "8D9FFF"),
        Color(hex: "F5B9EA"),
        Color(hex: "FF6778"),
        Color(hex: "FFBA71"),
        Color(hex: "BC82F3"),
    ]

    var body: some View {
        let cornerRadius: CGFloat = 12

        ZStack {
            // Layer 1 — tight, sharp glow
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    AngularGradient(colors: colors, center: .center, angle: .degrees(rotation1)),
                    lineWidth: 4
                )
                .blur(radius: 4)
                .opacity(0.9)

            // Layer 2 — medium spread
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    AngularGradient(colors: colors, center: .center, angle: .degrees(rotation2)),
                    lineWidth: 8
                )
                .blur(radius: 12)
                .opacity(0.6)

            // Layer 3 — wide ambient glow
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    AngularGradient(colors: colors, center: .center, angle: .degrees(rotation3)),
                    lineWidth: 12
                )
                .blur(radius: 24)
                .opacity(0.4)
        }
        .padding(1)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation1 = 360
            }
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                rotation2 = 360
            }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation3 = 360
            }
        }
    }
}
