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
    @State private var isHovering: Bool = false
    
    
    var body: some View {
        Button {
            browserManager.openCommandPalette()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("New Tab")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        
    }
    
    private var backgroundColor: Color {
        if windowState.isCommandPaletteVisible {
            return AppColors.controlBackgroundActive
        } else if isHovering {
            return AppColors.controlBackgroundHover
        } else {
            return Color.clear
        }
    }
}
