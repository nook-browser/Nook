// Licensed under GPL-3.0. See LICENSE.
//
//  RoundedSpinner.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI
struct RoundedSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.05, to: 0.75)
            .stroke(
                .foreground,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

/// Where a `RoundedSpinner` stood when the work finished: draws a circle, then a tick inside it.
struct RoundedCheckmark: View {
    @State private var circle: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: circle)
                .stroke(.foreground, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Tick()
                .trim(from: 0, to: tick)
                .stroke(.foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { circle = 1 }
            withAnimation(.easeOut(duration: 0.2).delay(0.25)) { tick = 1 }
        }
    }

    private struct Tick: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.52))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.67))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
            }
        }
    }
}
