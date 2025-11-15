//
//  TabClosureToast.swift
//  Nook
//
//  Created by Jonathan Caudill on 02/10/2025.
//

import SwiftUI

struct TabClosureToast: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState

    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
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

            VStack(alignment: .leading, spacing: 2) {
                Text("\(browserManager.tabClosureToastCount) tab\(browserManager.tabClosureToastCount > 1 ? "s" : "") closed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Text("Press ⌘Z to undo")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
            }

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
            browserManager.hideTabClosureToast()
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
        .onChange(of: browserManager.showTabClosureToast) { _, newValue in
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
