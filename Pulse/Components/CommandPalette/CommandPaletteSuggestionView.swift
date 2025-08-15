//
//  CommandPaletteSuggestionView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI

struct CommandPaletteSuggestionView: View {
    var favicon: SwiftUI.Image
    var text: String
    var isSelected: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(alignment: .center,spacing: 12) {
            favicon
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 12, weight: .medium))
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
            
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.25)
        } else if isHovered {
            return Color.white.opacity(0.15)
        } else {
            return Color.clear
        }
    }
    
}
