//
//  ZoomPopupView.swift
//  Nook
//
//  Created by Assistant on 13/10/2025.
//

import SwiftUI

struct ZoomPopupView: View {
    @ObservedObject var zoomManager: ZoomManager
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomReset: () -> Void
    let onZoomPresetSelected: (Double) -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var hideTimer: Timer?

    var body: some View {
        // Just the three controls: - button, percentage, + button
        HStack(spacing: 8) {
            // Zoom out button
            Button(action: {
                onZoomOut()
                resetHideTimer()
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(zoomManager.isAtMinimumZoom)

            // Current zoom percentage (clickable for reset)
            Button(action: {
                onZoomReset()
                resetHideTimer()
            }) {
                Text(zoomManager.getZoomPercentageDisplay())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 50, maxHeight: 28)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Zoom in button
            Button(action: {
                onZoomIn()
                resetHideTimer()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(zoomManager.isAtMaximumZoom)
        }
        .padding(12)
        .frame(maxWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "2A3A1F"),
                            Color(hex: "1F2A17")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
        .onAppear {
            isVisible = true
            startHideTimer()
        }
        .onDisappear {
            hideTimer?.invalidate()
        }
    }

    // MARK: - Timer Management

    private func startHideTimer() {
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            onDismiss()
        }
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        startHideTimer()
    }
}

// MARK: - Preview

#Preview {
    ZoomPopupView(
        zoomManager: ZoomManager(),
        onZoomIn: {},
        onZoomOut: {},
        onZoomReset: {},
        onZoomPresetSelected: { _ in },
        onDismiss: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

