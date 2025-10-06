//
//  NewTabButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct NewTabButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering: Bool = false

    var body: some View {
        Button {
            browserManager.openCommandPalette()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .frame(width: 20, height: 20)
                Text("New Tab")
                    .font(.system(size: 14, weight: .regular))
                Spacer()
            }
            .foregroundStyle(
                colorScheme == .dark
                    ? AppColors.sidebarTextLight : AppColors.sidebarTextDark
            )
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }

    }

    private var backgroundColor: Color {
        if windowState.isCommandPaletteVisible {
            return colorScheme == .dark ? AppColors.spaceTabActiveLight : AppColors.spaceTabActiveDark
        } else if isHovering {
            return colorScheme == .dark ? AppColors.spaceTabHoverLight : AppColors.spaceTabHoverDark
        } else {
            return Color.clear
        }
    }
}
