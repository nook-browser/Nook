//
//  SpacesListItem.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    var space: Space
    var isActive: Bool
    var compact: Bool
    @State private var isHovering: Bool = false
    @State private var selectedEmoji: String = ""
    @FocusState private var emojiFieldFocused: Bool

    private var currentSpaceID: UUID? {
        browserManager.tabManager.currentSpace?.id
    }
    
    private var cellSize: CGFloat { compact && !isActive ? 16 : 24 }
    private let dotVisualSize: CGFloat = 6
    private let cornerRadius: CGFloat = 6
    
    var body: some View {
        Button {
            browserManager.tabManager.setActiveSpace(space)
        } label: {
            ZStack {
                if compact && !isActive {
                    Circle()
                        .fill(AppColors.textTertiary)
                        .frame(width: dotVisualSize, height: dotVisualSize)
                } else {
                    if isEmoji(space.icon) {
                        // Fixed inner content size to avoid glyph cropping
                        Text(space.icon)
                            .font(.system(size: 14))
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: space.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 20, height: 20)
                            .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
                    }
                }
            }
            .frame(width: cellSize, height: cellSize)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isHovering ? AppColors.controlBackgroundHover : Color.clear)
        )
        .frame(width: cellSize, height: cellSize)
        .layoutPriority(isActive ? 1 : 0)
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(
            // Hidden TextField for capturing emoji selection
            TextField("", text: $selectedEmoji)
                .frame(width: 0, height: 0)
                .opacity(0)
                .focused($emojiFieldFocused)
                .onChange(of: selectedEmoji) { _, newValue in
                    if !newValue.isEmpty {
                        space.icon = String(newValue.last!)
                        browserManager.tabManager.persistSnapshot()
                        selectedEmoji = ""
                    }
                }
        )
        .contextMenu {
            Button("Change Icon...") {
                emojiFieldFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            }
        }
    }
    
    private func changeIcon() {
        let emojis = ["🚀", "💡", "🎯", "⚡️", "🔥", "🌟", "💼", "🏠", "🎨", "📱"]
        let randomEmoji = emojis.randomElement() ?? "🚀"
        
        space.icon = randomEmoji
        browserManager.tabManager.persistSnapshot()
    }
    
    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
            (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
            (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}
