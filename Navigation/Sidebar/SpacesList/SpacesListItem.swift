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
    @EnvironmentObject var tabManager: TabManager
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
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(NookDesign.Motion.standard) {
                browserManager.setActiveSpace(space, in: windowState)
            }
        } label: {
            spaceIcon
                .opacity(isActive ? 1.0 : 0.7)
                .frame(maxWidth: .infinity)

        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(radius: NookDesign.Radius.lg))
        .layoutPriority(2)
        .foregroundStyle(Color.primary)
        .layoutPriority(isActive ? 1 : 0)
        .opacity(isFaded ? 0.3 : 1.0)
        .onHoverTracking { hovering in
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
                    .colorMultiply(isActive ? .white : .gray)
                    .blendMode(isActive ? .normal : .luminosity)
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        space.icon = newValue
                        tabManager.persistSnapshot()
                    }

            } else {
                Image(systemName: space.icon)
                    .foregroundStyle(iconColor)
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                        space.icon = newValue
                        tabManager.persistSnapshot()
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
            browserManager.showSpaceSettings(for: space)
        } label: {
            Label("Space Settings", systemImage: "gear")
        }

        if tabManager.spaces.count > 1 {
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
        let regularTabsCount = tabManager.tabsBySpace[space.id]?.count ?? 0
        let spacePinnedTabsCount = tabManager.spacePinnedTabs(for: space.id).count
        let tabsCount = regularTabsCount + spacePinnedTabsCount

        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabsCount,
                isLastSpace: tabManager.spaces.count <= 1,
                onDelete: {
                    tabManager.removeSpace(space.id)
                    browserManager.dialogManager.closeDialog()
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
