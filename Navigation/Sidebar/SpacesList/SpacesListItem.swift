//
//  SpacesListItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    let space: Space
    let isActive: Bool
    let compact: Bool
    let isFaded: Bool
    let onHoverChange: ((Bool) -> Void)?

    @State private var isHovering: Bool = false
    @StateObject private var emojiManager = EmojiPickerManager()

    private let dotSize: CGFloat = 6

    init(
        space: Space,
        isActive: Bool,
        compact: Bool,
        isFaded: Bool,
        onHoverChange: ((Bool) -> Void)? = nil
    ) {
        self.space = space
        self.isActive = isActive
        self.compact = compact
        self.isFaded = isFaded
        self.onHoverChange = onHoverChange
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                browserManager.setActiveSpace(space, in: windowState)
            }
        } label: {
            spaceIcon
                .frame(maxWidth: .infinity)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SpaceListItemButtonStyle())
        .layoutPriority(2)
        .foregroundStyle(Color.primary)
        .layoutPriority(isActive ? 1 : 0)
        .opacity(isFaded ? 0.3 : 1.0)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange?(hovering)
        }
        .contextMenu {
            spaceContextMenu
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var spaceIcon: some View {
        if compact && !isActive {
            // Compact mode: show dot
            Circle()
                .fill(iconColor)
                .frame(width: dotSize, height: dotSize)
        } else {
            // Normal mode: show icon or emoji
            if isEmoji(space.icon) {
                Text(space.icon)
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        space.icon = newValue
                        browserManager.tabManager.persistSnapshot()
                    }
            } else {
                Image(systemName: space.icon)
                    .foregroundStyle(iconColor)
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        space.icon = newValue
                        browserManager.tabManager.persistSnapshot()
                    }
            }
        }
    }

    private var iconColor: Color {
        browserManager.gradientColorManager.isDark
            ? AppColors.spaceTabTextDark
            : AppColors.spaceTabTextLight
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var spaceContextMenu: some View {
        Button {
            showSpaceEditDialog()
        } label: {
            Label("Space Settings", systemImage: "gear")
        }

        if browserManager.tabManager.spaces.count > 1 {
            Button(role: .destructive) {
                showDeleteConfirmation()
            } label: {
                Label("Delete Space", systemImage: "trash")
            }
        }
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        // Count both regular and space-pinned tabs
        let regularTabsCount = browserManager.tabManager.tabsBySpace[space.id]?.count ?? 0
        let spacePinnedTabsCount = browserManager.tabManager.spacePinnedTabs(for: space.id).count
        let tabsCount = regularTabsCount + spacePinnedTabsCount

        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabsCount,
                isLastSpace: browserManager.tabManager.spaces.count <= 1,
                onDelete: {
                    browserManager.tabManager.removeSpace(space.id)
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func showSpaceEditDialog() {
        browserManager.dialogManager.showDialog(
            SpaceEditDialog(
                space: space,
                mode: .icon,
                onSave: { newName, newIcon, newProfileId in
                    do {
                        if newIcon != space.icon {
                            try browserManager.tabManager.updateSpaceIcon(
                                spaceId: space.id,
                                icon: newIcon
                            )
                        }

                        if newName != space.name {
                            try browserManager.tabManager.renameSpace(
                                spaceId: space.id,
                                newName: newName
                            )
                        }

                        // Update profile if changed
                        if newProfileId != space.profileId, let profileId = newProfileId {
                            browserManager.tabManager.assign(spaceId: space.id, toProfile: profileId)
                        }

                        browserManager.dialogManager.closeDialog()
                    } catch {
                        print("⚠️ Failed to update space \(space.id.uuidString):", error)
                    }
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func isEmoji(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) // Emoticons & pictographs
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF) // Miscellaneous symbols
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF) // Dingbats
        }
    }
}

struct SpaceListItemButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.primary.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))

            configuration.label
                .foregroundStyle(.primary)
        }
        .frame(height: size)
        .frame(maxWidth: size)
        .opacity(isEnabled ? 1.0 : 0.3)
        
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var size: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }
    
//    private var iconSize: CGFloat {
//        switch controlSize {
//        case .mini: 12
//        case .small: 14
//        case .regular: 16
//        case .large: 18
//        case .extraLarge: 20
//        @unknown default: 16
//        }
//    }
    
    private var cornerRadius: CGFloat {
        8
    }
    
    private func backgroundColorOpacity(isPressed: Bool) -> Double {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? 0.2 : 0.1
        } else {
            return 0.0
        }
    }
}
