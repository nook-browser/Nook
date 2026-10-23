// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//
//  A space's sidebar outline: pinned section rows, the separator and new-tab button, then
//  tabs section rows. Rows come flattened from `TabsController.rows(space:)`; each section is
//  one drop zone whose rows all share `Tab.stride` height (including vertical card insets), which the
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
    @State private var isUserScrolling = false
    @State private var showsScrollIndicator = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        ScrollView(.vertical) {
            VStack(spacing: NookDesign.Spacing.sectionGap) {
                // An empty pinned section shows a drop slot only while a drag is on.
                if !pinned.isEmpty {
                    sectionList(.pinned(spaceID: spaceID), rows: pinned, split: split, showsTail: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }

                VStack(spacing: NookDesign.Spacing.sectionGap) {
                    separatorAndNewTab(regular: regular)
                    sectionList(.tabs(spaceID: spaceID), rows: regular, split: split, showsTail: true)
                }
            }
            .animation(NookDesign.Motion.standard, value: pinned.isEmpty)
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            // Inset the rows, not the scroll viewport: the indicator belongs at the sidebar edge.
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        }
        .contentMargins(.trailing, 0, for: .scrollIndicators)
        .scrollIndicators(showsScrollIndicator && !windowState.isSidebarResizeHovered ? .visible : .hidden)
        .onScrollPhaseChange { _, phase in
            // Tracking alone (a finger resting on the pad) is not scrolling.
            isUserScrolling = phase == .interacting || phase == .decelerating
            if isUserScrolling { showsScrollIndicator = true }
        }
        .task(id: isUserScrolling) {
            guard !isUserScrolling else { return }
            do {
                try await Task.sleep(for: .milliseconds(650))
                showsScrollIndicator = false
            } catch {
                // A new scroll cancels the pending hide.
            }
        }
        .onDisappear {
            isUserScrolling = false
            showsScrollIndicator = false
        }
        .contentShape(Rectangle())
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
    }

    // MARK: - Sections

    private func sectionList(_ section: Parent, rows allRows: [Row], split: SplitPair?, showsTail: Bool) -> some View {
        // The pair is one row at its anchor; the other half's own row is hidden.
        let rows = split.map { split in allRows.filter { !split.contains($0.id) || $0.id == split.anchorID } } ?? allRows
        let zone = DropZoneID.section(section)
        let position = dragSession.dropPosition?.zone == zone ? dragSession.dropPosition : nil
        let isSource = dragSession.isDragging && dragSession.sourceZone == zone
        let isDestination = position != nil || (isSource && dragSession.dropPosition == nil && dragSession.activeZone == zone)
        let boundary = position.map { $0.index + ($0.placement == .after ? 1 : 0) }
        let preview = TabReorderPreview(
            rows: rows, draggedID: dragSession.draggedItem?.tabId ?? spaceID,
            destinationBoundary: boundary, sourceInThisSection: isSource,
            isDestination: isDestination, isIntoFolder: position?.placement == .into
        )
        return NookDropZoneHostView(
            zoneID: zone,
            layout: .rows(rows),
            manager: dragSession,
            onDrop: { itemID, position in
                tabs.drop(itemID, at: position, section: section, rows: rows)
            }
        ) {
            VStack(spacing: 0) {
                let content = Group {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, zone: zone, split: split, isDropTarget: position == DropPosition(zone: zone, index: index, placement: .into))
                            .padding(.leading, CGFloat(row.depth) * NookDesign.Spacing.folderIndent)
                            // Zen keeps a dimmed source in place while its floating card
                            // follows the pointer freely; only the insertion marker moves.
                            .opacity(preview.containsDraggedRow(id: row.id) ? (dragSession.isFinishingDrag ? 0 : 0.3) : 1)
                            // Only release makes the neighboring rows move aside, in sync
                            // with the native floating card's 100ms landing animation.
                            .offset(y: dragSession.isFinishingDrag ? CGFloat(preview.rowOffset(for: row.id)) * NookDesign.Tab.stride : 0)
                            .animation(reduceMotion ? nil : NookDesign.Motion.tabReorder, value: dragSession.isFinishingDrag)
                    }
                }
                if dragSession.isDragging {
                    VStack(spacing: 0) { content }
                } else {
                    LazyVStack(spacing: 0) { content }
                }
                if dragSession.isFinishingDrag, !isSource, isDestination, preview.gapIndex != nil, !rows.isEmpty {
                    Color.clear.frame(height: NookDesign.Tab.stride)
                }

                if allRows.isEmpty, !showsTail {
                    emptySectionSlot(isActive: dragSession.activeZone == zone)
                }

                if showsTail {
                    Color.clear
                        .contentShape(Rectangle())
                        .conditionalWindowDrag()
                        .frame(minHeight: NookDesign.Size.dropTail, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if !dragSession.isFinishingDrag, let gap = boundary, preview.gapIndex != nil {
                    dropLine
                        .padding(.leading, dropLineIndent)
                        .offset(y: CGFloat(gap) * NookDesign.Tab.stride)
                        .animation(reduceMotion ? nil : NookDesign.Motion.tabReorder, value: gap)
                        .allowsHitTesting(false)
                }
            }
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

    private func emptySectionSlot(isActive: Bool) -> some View {
        NookDesign.Radius.shape(NookDesign.Radius.md)
            .strokeBorder(style: StrokeStyle(lineWidth: NookDesign.Size.hairlineWidth, dash: [NookDesign.Spacing.sm, NookDesign.Spacing.xs]))
            .foregroundStyle(isActive ? NookDesign.Surface.dropBorderActive : NookDesign.Surface.dropBorderIdle)
            .background(NookDesign.Radius.shape(NookDesign.Radius.md).fill(isActive ? NookDesign.Surface.fillPressed : Color.clear))
            .frame(height: NookDesign.Tab.height)
            .padding(.vertical, NookDesign.Tab.verticalInset)
            .animation(NookDesign.Motion.quick, value: isActive)
    }

    /// Leading inset of a drop line. The overlay spans the row including its depth padding.
    private var dropLineIndent: CGFloat {
        CGFloat(dragSession.dropDepth) * NookDesign.Spacing.folderIndent
    }

    private var dropLine: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(Color.primary.opacity(0.7), lineWidth: NookDesign.Tab.dropIndicatorHeight)
                .frame(width: NookDesign.Tab.dropIndicatorDot, height: NookDesign.Tab.dropIndicatorDot)
            Capsule()
                .fill(Color.primary.opacity(0.7))
                .frame(height: NookDesign.Tab.dropIndicatorHeight)
        }
        .frame(height: NookDesign.Tab.dropIndicatorDot)
        .offset(y: -NookDesign.Tab.dropIndicatorDot / 2)
    }

    @ViewBuilder
    private func rowView(_ row: Row, zone: DropZoneID, split: SplitPair?, isDropTarget: Bool) -> some View {
        if let split, row.id == split.anchorID {
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
                    SpaceTab(item: row.item, hasChildren: row.hasChildren)
                }
            }
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

    private func separatorAndNewTab(regular: [Row]) -> some View {
        let looseTabs = regular.filter { $0.depth == 0 && !$0.item.isFolder }.map(\.item.id)
        return VStack(spacing: NookDesign.Spacing.xs) {
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

            if tabs.rows(space: spaceID).allSatisfy({ $0.section != .pinned }), dragSession.isDragging {
                // Reuse the New Tab slot, so revealing an empty pin target cannot push the
                // whole list down beneath the pointer at the start of a drag.
                sectionList(.pinned(spaceID: spaceID), rows: [], split: nil, showsTail: false)
            } else {
                newTabButton
            }
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
                    .font(NookDesign.Tab.font)
                Spacer(minLength: 0)
                if isNewTabHovering {
                    Text("⌘T")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isNewTabHovering ? .secondary : .tertiary)
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Tab.height)
            .frame(maxWidth: .infinity)
            .background(isNewTabHovering ? NookDesign.Surface.fill : Color.clear)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .padding(.vertical, NookDesign.Tab.verticalInset)
        }
        .buttonStyle(NookTabButtonStyle())
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) { isNewTabHovering = hovering }
        }
    }
}
