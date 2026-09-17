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

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: NookDesign.Spacing.sectionGap) {
                if !pinned.isEmpty {
                    sectionList(.pinned(spaceID: spaceID), rows: pinned, showsTail: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }

                VStack(spacing: NookDesign.Spacing.sectionGap) {
                    separatorAndNewTab(regular: regular)
                    sectionList(.tabs(spaceID: spaceID), rows: regular, showsTail: true)
                }
            }
            .animation(NookDesign.Motion.standard, value: pinned.isEmpty)
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
    }

    // MARK: - Sections

    private func sectionList(_ section: Parent, rows allRows: [Row], showsTail: Bool) -> some View {
        let (rows, split) = splitAdjusted(allRows)
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

    @ViewBuilder
    private func rowView(_ row: Row, zone: DropZoneID, split: SplitPair?, isDropTarget: Bool) -> some View {
        if let split, row.id == split.left.id || row.id == split.right.id {
            SplitTabRow(left: split.left, right: split.right, zoneID: zone)
        } else {
            let session = tabs.session(for: row.item.id)
            NookDragSourceView(
                item: NookDragItem(tabId: row.item.id, title: tabs.title(for: row.item), urlString: tabs.currentURL(for: row.item)?.absoluteString ?? ""),
                icon: row.item.isFolder ? Image(systemName: "folder.fill") : session?.favicon,
                zoneID: zone,
                manager: dragSession
            ) {
                if row.item.isFolder {
                    TabFolderView(item: row.item, spaceID: spaceID, isDropTarget: isDropTarget)
                } else {
                    SpaceTab(item: row.item)
                }
            }
            .opacity(dragSession.draggedItem?.tabId == row.item.id ? NookDesign.Surface.unloadedOpacity : 1)
            .id(row.item.id)
        }
    }

    // MARK: - Split

    private struct SplitPair {
        let left: Item
        let right: Item
    }

    /// When both split items are visible rows of one section, the later one is dropped from the
    /// list and the earlier one renders as the split row, so every displayed row keeps one height.
    private func splitAdjusted(_ rows: [Row]) -> ([Row], SplitPair?) {
        guard let split = windowState.split,
              let leftIndex = rows.firstIndex(where: { $0.id == split.leftItemID }),
              let rightIndex = rows.firstIndex(where: { $0.id == split.rightItemID }),
              leftIndex != rightIndex else { return (rows, nil) }
        var adjusted = rows
        adjusted.remove(at: max(leftIndex, rightIndex))
        return (adjusted, SplitPair(left: rows[leftIndex].item, right: rows[rightIndex].item))
    }

    // MARK: - Separator and New Tab

    private func separatorAndNewTab(regular: [Row]) -> some View {
        let looseTabs = regular.filter { $0.depth == 0 && !$0.item.isFolder }.map(\.item.id)
        return VStack(spacing: NookDesign.Spacing.xs) {
            SpaceSeparator(
                isHovering: $isSidebarHovered,
                onClear: { tabs.close(looseTabs) },
                onOrganize: nookSettings.tabOrganizerEnabled ? {
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
