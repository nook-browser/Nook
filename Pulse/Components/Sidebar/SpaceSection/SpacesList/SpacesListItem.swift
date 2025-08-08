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
    @State private var isHovering: Bool = false
    @State private var showingIconPicker: Bool = false

    private var currentSpaceID: UUID? {
        browserManager.tabManager.currentSpace?.id
    }
    
    var body: some View {
        Button {
            browserManager.tabManager.setActiveSpace(space)
        } label: {
            if isEmoji(space.icon) {
                Text(space.icon)
                    .font(.system(size: 14))
                    .padding(4)
            } else {
                Image(systemName: space.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(4)
                    .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? AppColors.controlBackgroundHover : Color.clear)
                .frame(width: 24, height: 24)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Change Icon...") {
                showingIconPicker = true
            }
        }
        .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
            EmojiGridPicker { selectedEmoji in
                space.icon = selectedEmoji
                browserManager.tabManager.persistSnapshot()
                showingIconPicker = false
            }
            .padding()
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
