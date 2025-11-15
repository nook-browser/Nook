//
//  SpacesListItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    var space: Space
    var isActive: Bool
    var compact: Bool
    @State private var isHovering: Bool = false
    @State private var selectedEmoji: String = ""
    @FocusState private var emojiFieldFocused: Bool

    private var currentSpaceID: UUID? {
        windowState.currentSpaceId
    }

    private var cellSize: CGFloat { compact && !isActive ? 16 : 32 }
    private let dotVisualSize: CGFloat = 6
    private let cornerRadius: CGFloat = 6

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)){
                browserManager.setActiveSpace(space, in: windowState)
            }
        } label: {
            if compact && !isActive {
                Circle()
                    .fill(iconColor)
                    .frame(width: dotVisualSize, height: dotVisualSize)
            } else {
                if isEmoji(space.icon) {
                    // Fixed inner content size to avoid glyph cropping
                    Text(space.icon)
                } else {
                    Image(systemName: space.icon)
                        .foregroundStyle(iconColor)
                }
            }
        }
        
        .labelStyle(.iconOnly)
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
        .layoutPriority(isActive ? 1 : 0)
        .onHover { hovering in
            isHovering = hovering
        }
        // Removed profile badge overlay to reduce UI noise
        .overlay(
            // Hidden TextField for capturing emoji selection
            TextField("", text: $selectedEmoji)
                .frame(width: 0, height: 0)
                .opacity(0)
                .focused($emojiFieldFocused)
                .onChange(of: selectedEmoji) { _, newValue in
                    if !newValue.isEmpty {
                        // Safely unwrap the last character
                        guard let lastChar = newValue.last else { return }
                        space.icon = String(lastChar)
                        browserManager.tabManager.persistSnapshot()
                        selectedEmoji = ""
                    }
                }
        )
        .contextMenu {
            // Profile assignment
            let currentName =
                resolvedProfileName(for: space.profileId) ?? browserManager
                .profileManager.profiles.first?.name ?? "Default"
            Text("Current Profile: \(currentName)")
                .foregroundStyle(.secondary)
            Divider()
            ProfilePickerView(
                selectedProfileId: Binding(
                    get: {
                        space.profileId ?? browserManager.profileManager
                            .profiles.first?.id ?? UUID()
                    },
                    set: { assignProfile($0) }
                ),
                onSelect: { _ in },
                compact: true
            )
            .environmentObject(browserManager)

            Divider()
            Button("Change Icon...") {
                emojiFieldFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            }
        }
    }

    private var iconColor: Color {
        return browserManager.gradientColorManager.isDark
            ? AppColors.spaceTabTextDark : AppColors.spaceTabTextLight
    }

    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }

    private func assignProfile(_ id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func resolvedProfileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: {
            $0.id == id
        })?.name
    }
}
