// Licensed under GPL-3.0. See LICENSE.
//
//  SpacesListItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb

struct SpacesListItem: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    let space: SpaceRecord
    let isActive: Bool
    let isFaded: Bool

    @State private var showsAppearance = false
    @State private var showsIconPicker = false
    @Environment(\.tabActions) private var actions

    private let dotSize: CGFloat = NookDesign.Spacing.sm
    private let activeDotSize: CGFloat = NookDesign.Spacing.md
    // Match Zen’s macOS workspace target independently of the small dot.
    private let buttonSize: CGFloat = 32

    init(
        space: SpaceRecord,
        isActive: Bool,
        isFaded: Bool
    ) {
        self.space = space
        self.isActive = isActive
        self.isFaded = isFaded
    }

    var body: some View {
        Button {
            guard windowState.spaceID != space.id else { return }
            // A macOS trackpad already supplies the physical click feedback.
            #if !os(macOS)
            Haptics.alignment()
            #endif
            withAnimation(NookDesign.Motion.standard) {
                tabs.setSpace(space.id, in: windowState)
            }
        } label: {
            spaceDot
                .fixedSize()
                .frame(width: 20, height: 20, alignment: .center)
                .scaleEffect(space.icon.isEmpty && !space.isAgent ? 1 : 0.82)
                .saturation(isActive ? 1 : 0)
                .opacity(isActive ? 1 : 0.45)
                .animation(NookDesign.Motion.quick, value: isActive)
                .frame(width: buttonSize, height: buttonSize, alignment: .center)
                .contentShape(Rectangle())
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle(size: buttonSize))
        .layoutPriority(isActive ? 1 : 0)
        .opacity(isFaded ? 0.3 : 1.0)
        .accessibilityLabel(space.name)
        .popover(isPresented: $showsAppearance) {
            SpaceAppearancePicker(appearance: Binding(
                get: { tabs.space(space.id)?.resolvedAppearance ?? space.resolvedAppearance },
                set: { tabs.updateSpaceAppearance(space.id, appearance: $0) }
            ))
        }
        .popover(isPresented: $showsIconPicker) {
            SpaceIconPicker(icon: Binding(
                get: { tabs.space(space.id)?.icon ?? space.icon },
                set: { tabs.updateSpace(space.id, name: nil, icon: $0, accentHex: nil) }
            ), onSelect: { showsIconPicker = false })
        }
        .contextMenu {
            if !space.isAgent {
                Button("Change Icon or Emoji…", systemImage: "face.smiling") {
                    DispatchQueue.main.async { showsIconPicker = true }
                }
                Button("Customize Appearance…", systemImage: "paintpalette") {
                    DispatchQueue.main.async { showsAppearance = true }
                }
                Divider()
            }
            SpaceContextMenu(
                space: space,
                canDelete: tabs.switchableSpaces(for: windowState).count > 1,
                onOpenSettings: { actions?.openSpaceSettings() },
                onDeleteSpace: { tabs.deleteSpace(space.id) }
            )
            .environment(tabs)
            .environment(\.tabActions, actions)
        }
    }

    // MARK: - Dot

    @ViewBuilder
    private var spaceDot: some View {
        if space.isAgent {
            Image(systemName: "sparkles")
                .font(.system(size: NookDesign.Size.spaceIcon, weight: .semibold))
                .foregroundStyle(NookDesign.Surface.agentGradient)
        } else if space.icon.isEmpty {
            plainDot
        } else {
            SpaceIcon(space.icon)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }

    private var plainDot: some View {
        Circle()
            .fill(isActive ? AnyShapeStyle(space.accentColor) : AnyShapeStyle(.tertiary))
            .frame(width: isActive ? activeDotSize : dotSize, height: isActive ? activeDotSize : dotSize)
            .animation(NookDesign.Motion.standard, value: isActive)
    }
}
