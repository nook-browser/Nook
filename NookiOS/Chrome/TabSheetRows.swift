// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  TabSheetRows.swift
//  NookiOS
//
//  The outline body of the tab sheet. Rows come from the same
//  tabs.rows(space:) the macOS sidebar walks, rendered with the same shared
//  views. Only the indent constant differs, and that lives in NookDesign.
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
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if row.item.isFolder {
            TabFolderView(item: row.item, spaceID: spaceID)
        } else {
            SpaceTab(item: row.item)
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
        }
    }
}
