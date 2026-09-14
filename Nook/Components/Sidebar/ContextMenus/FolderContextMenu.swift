//
//  FolderContextMenu.swift
//  Nook
//
//  Created by Claude on 2026-09-14.
//

import SwiftUI

/// Shared context menu for sidebar tab folders. Used both by the folder
/// header's hover menu and by its right-click menu.
struct FolderContextMenu: View {
    @ObservedObject var folder: TabFolder
    let onRename: () -> Void
    let onAddTab: () -> Void
    let onAlphabetize: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            Button(action: onRename) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button(action: onAddTab) {
                Label("Add Tab to Folder", systemImage: "plus")
            }
            Divider()
            Button(action: onAlphabetize) {
                Label("Alphabetize Tabs", systemImage: "textformat.abc")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}
