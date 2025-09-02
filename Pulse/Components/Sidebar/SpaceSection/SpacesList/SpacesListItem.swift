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
        .overlay(alignment: .bottomTrailing) {
            // Show only when there is an explicit assignment or multiple profiles exist,
            // and hide in dot mode (compact && !isActive)
            if (space.profileId != nil || browserManager.profileManager.profiles.count > 1) && !(compact && !isActive) {
                SpaceProfileBadge(space: space, size: .compact)
                    .environmentObject(browserManager)
                    .offset(x: 1.5, y: 1.5)
            }
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
            // Profile assignment
            let currentName = resolvedProfileName(for: space.profileId) ?? "None"
            Text("Current Profile: \(currentName)")
                .foregroundStyle(.secondary)
            Divider()
            ProfilePickerView(
                selectedProfileId: Binding(get: { space.profileId }, set: { assignProfile($0) }),
                onSelect: { _ in },
                compact: true,
                showNoneOption: true
            )
            .environmentObject(browserManager)

            Divider()
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

    private func assignProfile(_ id: UUID?) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func resolvedProfileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: { $0.id == id })?.name
    }
}
