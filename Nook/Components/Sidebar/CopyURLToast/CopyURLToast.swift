//
//  CopyURLToast.swift
//  Nook
//
//  Created on 2025-01-XX.
//

import SwiftUI

struct CopyURLToast: View {
    @Environment(BrowserWindowState.self) private var windowState

    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.4), lineWidth: 1)
                }

            Text("Copied Current URL")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(12)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(hex: "3E4D2E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 2)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            hideToast()
        }
        .opacity(isVisible ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.8),
            value: isVisible
        )
        .transition(.scale(scale: 0.0, anchor: .top))
        .onAppear {
            showToast()
        }
        .onChange(of: windowState.isShowingCopyURLToast) { _, newValue in
            if newValue {
                showToast()
            } else {
                hideToast()
            }
        }
    }

    private func showToast() {
        isVisible = true
    }

    private func hideToast() {
        isVisible = false
    }
}

