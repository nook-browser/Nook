//
//  NewTabButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct NewTabButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false
    
    
    var body: some View {
        Button {
            browserManager.openCommandPalette()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.white.opacity(0.45))
                    Text("New Tab")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
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
        if browserManager.isCommandPaletteVisible {
            return .white.opacity(0.2)
        } else if isHovering {
            return .white.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}
