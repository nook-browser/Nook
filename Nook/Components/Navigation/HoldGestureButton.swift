//
//  HoldGestureButton.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import SwiftUI
import AppKit

struct HoldGestureButton: View {
    let iconName: String
    let disabled: Bool
    let onTap: () -> Void
    let onHold: () -> Void
    let onHoldRelease: () -> Void

    @State private var isPressed = false
    @State private var holdTimer: Timer?
    @State private var isHoldTriggered = false

    private let holdDuration: TimeInterval = 0.5

    var body: some View {
        Button(action: onTap) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(disabled ? .secondary.opacity(0.5) : .primary)
        }
        .disabled(disabled)
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !disabled && !isPressed {
                        startHoldTimer()
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        cancelHoldTimer()
                        if isHoldTriggered {
                            onHoldRelease()
                            isHoldTriggered = false
                        }
                        isPressed = false
                    }
                }
        )
        .onDisappear {
            cancelHoldTimer()
        }
    }

    private func startHoldTimer() {
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { _ in
            isHoldTriggered = true
            onHold()
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }
}