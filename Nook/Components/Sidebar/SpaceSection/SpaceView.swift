// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//
//  A space's sidebar outline: pinned section rows, the separator and new-tab button, then
//  tabs section rows. Rows come flattened from `TabsController.rows(space:)`; each section is
//  one drop zone whose rows all share `Size.row` height and `Spacing.rowGap` spacing, which the
//  drop position math in `NookDragSessionManager` relies on.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

struct SpaceView: View {
    let spaceID: UUID
    let isActive: Bool
    @Binding var isSidebarHovered: Bool

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(TabOrganizerManager.self) private var tabOrganizerManager
    @Environment(\.nookSettings) private var nookSettings
    @ObservedObject private var dragSession = NookDragSessionManager.shared
    @State private var isNewTabHovering = false

    init(spaceID: UUID, isActive: Bool, isSidebarHovered: Binding<Bool>) {
        self.spaceID = spaceID
        self.isActive = isActive
        self._isSidebarHovered = isSidebarHovered
    }

    private var tabs: TabsController { browserManager.tabs }

    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        return max(browserManager.getSavedSidebarWidth(for: windowState), 0)
    }

    private var innerWidth: CGFloat {
        max(outerWidth - NookDesign.Spacing.sidebarInset * 2, 0)
    }

    var body: some View {
        let rows = tabs.rows(space: spaceID)
        let pinned = rows.filter { $0.section == .pinned }
        let regular = rows.filter { $0.section == .tabs }
        let split = splitPair(in: rows)
        let pinnedZone = DropZoneID.section(.pinned(spaceID: spaceID))
        let showsPinnedAppendSlot = dragSession.isDragging
            && !dragSession.isSettlingDrop
            && dragSession.sourceZone != pinnedZone
        let isAddingBookmark = dragSession.isDragging
            && !dragSession.isSettlingDrop
            && dragSession.sourceZone != .favorites(spaceID: spaceID)
        let hasFavorites = !tabs.favorites(of: spaceID).isEmpty
        let hasPins = !pinned.isEmpty
        let hasFavoritesOrPins = hasFavorites || hasPins || showsPinnedAppendSlot || isAddingBookmark || tabOrganizerManager.isOrganizing

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: NookDesign.Spacing.sectionGap) {
                if !pinned.isEmpty || showsPinnedAppendSlot {
                    sectionList(.pinned(spaceID: spaceID), rows: pinned, split: split, showsTail: false, showsAppendSlot: showsPinnedAppendSlot)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }

                VStack(spacing: NookDesign.Spacing.sectionGap) {
                    separatorAndNewTab(regular: regular, hasFavoritesOrPins: hasFavoritesOrPins)
                    sectionList(.tabs(spaceID: spaceID), rows: regular, split: split, showsTail: true)
                }
            }
            .animation(NookDesign.Motion.quick, value: hasFavoritesOrPins)
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
    }

    // MARK: - Sections

    private func sectionList(_ section: Parent, rows allRows: [Row], split: SplitPair?, showsTail: Bool, showsAppendSlot: Bool = false) -> some View {
        // The pair is one row at its anchor; the other half's own row is hidden.
        let rows = split.map { split in allRows.filter { !split.contains($0.id) || $0.id == split.anchorID } } ?? allRows
        let zone = DropZoneID.section(section)
        let position = dragSession.dropPosition?.zone == zone ? dragSession.dropPosition : nil
        return NookDropZoneHostView(
            zoneID: zone,
            layout: .rows(rows),
            manager: dragSession,
            onDrop: { itemID, position in
                tabs.drop(itemID, at: position, section: section, rows: rows)
            }
        ) {
            VStack(spacing: NookDesign.Spacing.rowGap) {
                LazyVStack(spacing: NookDesign.Spacing.rowGap) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, zone: zone, split: split, isDropTarget: position == DropPosition(zone: zone, index: index, placement: .into))
                            .padding(.leading, CGFloat(row.depth) * NookDesign.Spacing.folderIndent)
                            // The line is indented to the level the drop lands at (dropDepth), so a
                            // line that puts the item inside a folder is always drawn inside it.
                            .overlay(alignment: .top) {
                                if position == DropPosition(zone: zone, index: index, placement: .before) {
                                    dropLine.offset(y: -NookDesign.Spacing.rowGap)
                                        .padding(.leading, dropLineIndent)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if position == DropPosition(zone: zone, index: index, placement: .after)
                                    || (index == rows.count - 1 && position == DropPosition(zone: zone, index: rows.count, placement: .before)) {
                                    dropLine.offset(y: NookDesign.Spacing.rowGap)
                                        .padding(.leading, dropLineIndent)
                                }
                            }
                    }
                }
                .animation(NookDesign.Motion.quick, value: rows.map(\.id))

                if showsAppendSlot {
                    pinAppendSlot
                }

                if showsTail {
                    Color.clear
                        .contentShape(Rectangle())
                        .conditionalWindowDrag()
                        .frame(minHeight: NookDesign.Size.dropTail, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            .contentShape(Rectangle())
            // Rows have their own menus; this one covers the gaps and the tail of the section.
            .contextMenu {
                Button {
                    tabs.createFolderForRename(in: section, after: tabs.children(of: section).last?.id)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    /// Leading inset of a drop line. The overlay spans the row including its depth padding.
    private var dropLineIndent: CGFloat {
        CGFloat(dragSession.dropDepth) * NookDesign.Spacing.folderIndent
    }

    private var dropLine: some View {
        Rectangle()
            .fill(NookDesign.Surface.dropBorderActive)
            .frame(height: NookDesign.Spacing.rowGap)
            .clipShape(Capsule())
    }

    private var pinAppendSlot: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Image(systemName: "pin")
                .font(NookDesign.Font.caption)
            Text("Pin in this space")
                .font(NookDesign.Font.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, NookDesign.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: NookDesign.Size.row, alignment: .leading)
        .background {
            NookDesign.Radius.shape(NookDesign.Radius.lg)
                .strokeBorder(
                    NookDesign.Surface.dropBorderActive,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowView(_ row: Row, zone: DropZoneID, split: SplitPair?, isDropTarget: Bool) -> some View {
        if let split, row.id == split.anchorID {
            SplitTabRow(left: split.left, right: split.right, zoneID: zone)
        } else {
            let session = tabs.session(for: row.item.id)
            NookDragSourceView(
                item: NookDragItem(tabId: row.item.id, title: tabs.title(for: row.item), urlString: tabs.currentURL(for: row.item)?.absoluteString ?? "", isFolder: row.item.isFolder),
                icon: row.item.isFolder ? Image(systemName: "folder.fill") : session?.favicon,
                zoneID: zone,
                manager: dragSession
            ) {
                if row.item.isFolder {
                    TabFolderView(item: row.item, spaceID: spaceID, isDropTarget: isDropTarget)
                } else {
                    SpaceTab(item: row.item, hasChildren: row.hasChildren)
                }
            }
            .opacity(dragSession.draggedItem?.tabId == row.item.id
                     ? (dragSession.isSettlingDrop ? 0 : NookDesign.Surface.unloadedOpacity)
                     : 1)
            .id(row.item.id)
        }
    }

    // MARK: - Split

    private struct SplitPair {
        let left: Item
        let right: Item
        /// The row the pair is drawn at.
        let anchorID: UUID

        func contains(_ id: UUID) -> Bool { id == left.id || id == right.id }
    }

    /// The window's split pair, anchored at the left tab's row, or the right tab's when the left
    /// has no visible row (a favorite, or inside a closed folder).
    private func splitPair(in rows: [Row]) -> SplitPair? {
        guard let split = windowState.split,
              let left = tabs.item(split.leftItemID), let right = tabs.item(split.rightItemID),
              let anchor = [left.id, right.id].first(where: { id in rows.contains { $0.id == id } })
        else { return nil }
        return SplitPair(left: left, right: right, anchorID: anchor)
    }

    // MARK: - Separator and New Tab

    @ViewBuilder
    private func separatorAndNewTab(regular: [Row], hasFavoritesOrPins: Bool) -> some View {
        let looseTabs = regular.filter { $0.depth == 0 && !$0.item.isFolder }.map(\.item.id)
        if hasFavoritesOrPins {
            VStack(spacing: NookDesign.Spacing.xs) {
                SpaceSeparator(
                    isHovering: $isSidebarHovered,
                    // Clear empties the section: a tab goes with its whole trail.
                    onClear: { looseTabs.forEach(tabs.remove) },
                    onOrganize: nookSettings.tabOrganizerEnabled && tabOrganizerManager.isAvailable ? {
                        Task {
                            await tabOrganizerManager.organizeTabs(in: spaceID, using: tabs)
                        }
                    } : nil,
                    isOrganizing: tabOrganizerManager.isOrganizing,
                    tabCount: looseTabs.count
                )
                .padding(.horizontal, NookDesign.Spacing.md)

                newTabButton
            }
        } else {
            newTabButton
        }
    }

    private var newTabButton: some View {
        Button {
            commandPalette.open()
        } label: {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: NookDesign.Size.favicon, weight: .medium))
                Text("New Tab")
                    .font(NookDesign.Font.body)
                Spacer(minLength: 0)
                if isNewTabHovering {
                    Text("⌘T")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isNewTabHovering ? .secondary : .tertiary)
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(maxWidth: .infinity)
            .background(isNewTabHovering ? NookDesign.Surface.fill : Color.clear)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) { isNewTabHovering = hovering }
        }
    }
}
