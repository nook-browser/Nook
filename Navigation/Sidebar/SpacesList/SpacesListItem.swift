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

    private let dotSize: CGFloat = NookDesign.Spacing.sm

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
                .frame(maxWidth: .infinity)

        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle())
        .background(NookDesign.Radius.shape(NookDesign.Radius.md).fill(isActive ? NookDesign.Surface.fill : .clear))
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
            Circle()
                .fill(.tertiary)
                .frame(width: dotSize, height: dotSize)
        } else {
            SpaceIconView(icon: space.icon, tint: isActive ? space.accentColor : AppColors.textTertiary)
        }
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
}
