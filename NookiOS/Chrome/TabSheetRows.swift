// Licensed under GPL-3.0. See LICENSE.
//
//  TabSheetRows.swift
//  NookiOS
//
//  The outline body of the tab sheet. Rows come from the same
//  tabs.rows(space:) the macOS sidebar walks, rendered with the same shared
//  views. Only the indent constant differs, and that lives in NookDesign.
//
//  Drag shares no gesture code with the Mac's NSView drag session; both ends
//  call the same TabsController.drop, which already does the index maths.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

struct TabSheetRows: View {
    let spaceID: UUID
    /// Closes the sheet once a row has been chosen.
    let onSelect: () -> Void

    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window

    @State private var dropTarget: UUID?

    var body: some View {
        let rows = tabs.rows(space: spaceID)
        LazyVStack(spacing: NookDesign.Spacing.rowGap) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                // A rule where pinned ends, since a pinned row and a tab row
                // look alike in the outline.
                if index > 0, rows[index - 1].section != row.section {
                    Divider()
                        .padding(.vertical, NookDesign.Spacing.xs)
                }

                rowView(row)
                    .padding(.leading, CGFloat(row.depth) * NookDesign.Spacing.folderIndent)
                    .draggable(row.item.id.uuidString)
                    .dropDestination(for: String.self) { ids, _ in
                        accept(ids, rows: rows, index: index, intoFolder: row.item.isFolder)
                    } isTargeted: { targeted in
                        dropTarget = targeted ? row.item.id : (dropTarget == row.item.id ? nil : dropTarget)
                    }
            }

            // Without this there is no way to drop below the last row.
            Color.clear
                .frame(height: NookDesign.Size.dropTail)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    accept(ids, rows: rows, index: rows.count, intoFolder: false)
                }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        Group {
            if row.item.isFolder {
                TabFolderView(item: row.item, spaceID: spaceID, isDropTarget: dropTarget == row.item.id)
            } else {
                SpaceTab(item: row.item)
                    .simultaneousGesture(TapGesture().onEnded { onSelect() })
            }
        }
    }

    private func accept(_ ids: [String], rows: [Row], index: Int, intoFolder: Bool) -> Bool {
        guard let first = ids.first, let dragged = UUID(uuidString: first) else { return false }
        // The section the drop lands in, which is the target row's, or the last
        // row's for the tail.
        let target = index < rows.count ? rows[index] : rows.last
        guard let section = target?.section.parent(in: spaceID) else { return false }
        tabs.drop(dragged, section: section, rows: rows, index: index, intoFolder: intoFolder)
        Haptics.alignment()
        return true
    }
}
