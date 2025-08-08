//
//  EmojiPicker.swift
//  Pulse
//
//  Created by Jonathan Caudill
//

import SwiftUI

struct EmojiPicker: View {
    let currentIcon: String
    let onIconSelected: (String) -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            onIconSelected("🚀") // For now, just set a rocket emoji
        }) {
            HStack(spacing: 8) {
                Text(isEmoji(currentIcon) ? currentIcon : "✨")
                    .font(.system(size: 16))
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? .gray.opacity(0.1) : .clear)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
            (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
            (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}
