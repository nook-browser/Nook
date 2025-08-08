//
//  EmojiGridPicker.swift
//  Pulse
//
//  Created by Jonathan Caudill
//

import SwiftUI

struct EmojiGridPicker: View {
    let onEmojiSelected: (String) -> Void
    
    private let emojis = [
        "🚀", "💡", "🎯", "⚡️", "🔥", "🌟", "💼", "🏠", "🎨", "📱",
        "💻", "🎵", "🍎", "☕️", "📚", "🎮", "🏃‍♂️", "🧠", "💰", "🔧",
        "🎪", "🌈", "🦄", "🎭", "🎨", "🎸", "🎤", "🎬", "📷", "🎯",
        "🏆", "🥇", "🎊", "🎉", "🎈", "🎀", "💎", "👑", "🔮", "✨"
    ]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Choose an Icon")
                .font(.headline)
                .padding(.bottom, 4)
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button(action: {
                        onEmojiSelected(emoji)
                    }) {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.gray.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        // Add hover effect if needed
                    }
                }
            }
        }
        .frame(width: 300, height: 200)
    }
}