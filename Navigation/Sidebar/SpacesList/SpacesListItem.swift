//
//  SpacesListItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import NookTabsCore
import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    let space: SpaceRecord
    let isActive: Bool
    let isFaded: Bool
    let onHoverChange: ((Bool) -> Void)?

    @State private var isHovering: Bool = false
    @Environment(\.nookSettings) private var nookSettings
    @Environment(\.openSettings) private var openSettings

    private let dotSize: CGFloat = NookDesign.Spacing.sm
    private let activeDotSize: CGFloat = NookDesign.Spacing.md
    // A tight hit target so the 28pt default icon-button padding doesn't push the dots apart.
    private let buttonSize: CGFloat = NookDesign.Spacing.xl

    init(
        space: SpaceRecord,
        isActive: Bool,
        isFaded: Bool,
        onHoverChange: ((Bool) -> Void)? = nil
    ) {
        self.space = space
        self.isActive = isActive
        self.isFaded = isFaded
        self.onHoverChange = onHoverChange
    }

    var body: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(NookDesign.Motion.standard) {
                tabs.setSpace(space.id, in: windowState)
            }
        } label: {
            spaceDot
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(size: buttonSize))
        .layoutPriority(isActive ? 1 : 0)
        .opacity(isFaded ? 0.3 : 1.0)
        .onHoverTracking { hovering in
            isHovering = hovering
            onHoverChange?(hovering)
        }
        .contextMenu {
            SpaceContextMenu(
                space: space,
                canDelete: tabs.switchableSpaces(for: windowState).count > 1,
                onOpenSettings: {
                    SettingsNavigation.shared.currentSettingsTab = .spaces
                    openSettings()
                },
                onDeleteSpace: { tabs.deleteSpace(space.id) }
            )
            .environmentObject(browserManager)
        }
    }

    // MARK: - Dot

    @ViewBuilder
    private var spaceDot: some View {
        Circle()
            .fill(isActive ? AnyShapeStyle(space.accentColor) : AnyShapeStyle(.tertiary))
            .frame(width: isActive ? activeDotSize : dotSize, height: isActive ? activeDotSize : dotSize)
            .animation(NookDesign.Motion.standard, value: isActive)
    }
}
