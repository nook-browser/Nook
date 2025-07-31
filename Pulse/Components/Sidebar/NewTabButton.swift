//
//  NewTabButton.swift
//  Pulse
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct NewTabButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false
    
    
    var body: some View {
        Button {
            browserManager.isCommandPaletteVisible = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("New Tab")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.3))
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
        .buttonStyle(PlainButtonStyle()) // Removes default button styling
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        
    }
    
    private var backgroundColor: Color {
        if browserManager.isCommandPaletteVisible {
            return Color.white.opacity(0.28)
        } else if isHovering {
            return Color.white.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}
