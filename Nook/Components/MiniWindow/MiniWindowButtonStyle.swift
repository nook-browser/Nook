//
//  MiniWindowButtonStyle.swift
//  Nook
//
//  Created by Codex on 26/08/2025.
//

import SwiftUI

struct MiniWindowPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.18),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.18),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.18),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
