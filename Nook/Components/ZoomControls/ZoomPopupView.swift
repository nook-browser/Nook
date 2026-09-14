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
                    .font(NookDesign.Font.secondary)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .fill(.white.opacity(0.15))
                    )
                    .overlay(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
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
                    .font(NookDesign.Font.label)
                    .foregroundColor(.white)
                    .frame(minWidth: 50, maxHeight: 28)
                    .padding(.horizontal, 8)
                    .background(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .fill(.white.opacity(0.2))
                    )
                    .overlay(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
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
                    .font(NookDesign.Font.secondary)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .fill(.white.opacity(0.15))
                    )
                    .overlay(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(zoomManager.isAtMaximumZoom)
        }
        .padding(12)
        .frame(maxWidth: 160)
        .background(
            NookDesign.Radius.shape(NookDesign.Radius.lg)
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
            NookDesign.Radius.shape(NookDesign.Radius.lg)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .nookElevation(.floating)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(NookDesign.Motion.spring, value: isVisible)
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

