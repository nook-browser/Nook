// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  MiniWindowButtonStyle.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import NookDesign

struct MiniWindowPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NookDesign.Font.secondary)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .nookElevation(configuration.isPressed ? .raised : .floating)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }

    private func background(for isPressed: Bool) -> some View {
        LinearGradient(
            colors: isPressed ? pressedColors : normalColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var normalColors: [Color] {
        [Color(hex: "5FA8FF"), Color(hex: "407CFF")]
    }

    private var pressedColors: [Color] {
        [Color(hex: "4D8FDF"), Color(hex: "3263D1")]
    }
}

struct MiniWindowSuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NookDesign.Font.secondary)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .nookElevation(configuration.isPressed ? .raised : .floating)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }

    private func background(for isPressed: Bool) -> some View {
        LinearGradient(
            colors: isPressed ? pressedColors : normalColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var normalColors: [Color] {
        [Color(hex: "4CAF50"), Color(hex: "388E3C")]
    }

    private var pressedColors: [Color] {
        [Color(hex: "43A047"), Color(hex: "2E7D32")]
    }
}

struct MiniWindowErrorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NookDesign.Font.secondary)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .nookElevation(configuration.isPressed ? .raised : .floating)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }

    private func background(for isPressed: Bool) -> some View {
        LinearGradient(
            colors: isPressed ? pressedColors : normalColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var normalColors: [Color] {
        [Color(hex: "F44336"), Color(hex: "D32F2F")]
    }

    private var pressedColors: [Color] {
        [Color(hex: "E53935"), Color(hex: "C62828")]
    }
}
