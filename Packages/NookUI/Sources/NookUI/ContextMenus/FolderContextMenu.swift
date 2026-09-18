// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  FolderContextMenu.swift
//  Nook
//
//  Created by Claude on 2026-09-14.
//

import SwiftUI
import NookTabsCore
import NookWeb

/// Shared context menu for sidebar folders. Used both by the folder
/// header's hover menu and by its right-click menu.
struct FolderContextMenu: View {
    let itemID: UUID
    let onRename: () -> Void

    @Environment(BrowserWindowState.self) private var windowState: BrowserWindowState?

    @Environment(TabsController.self) private var tabs

    init(
        itemID: UUID,
        onRename: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.onRename = onRename
    }

    var body: some View {
        Group {
            Button(action: onRename) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button {
                guard let windowState else { return }
                tabs.open(url: TabsController.homeURL, in: windowState, placement: .newTab, parent: .folder(itemID: itemID))
            } label: {
                Label("Add Tab to Folder", systemImage: "plus")
            }
            if let item = tabs.item(itemID) {
                Button {
                    tabs.createFolderForRename(in: item.parent, after: itemID)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            Button {
                tabs.createFolderForRename(in: .folder(itemID: itemID), after: nil)
            } label: {
                Label("New Folder Inside", systemImage: "folder.badge.plus")
            }
            Divider()
            Button(action: alphabetize) {
                Label("Alphabetize Tabs", systemImage: "textformat.abc")
            }
            Divider()
            Button(role: .destructive) {
                tabs.close(itemID)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    /// Folders first, then tabs, each by title.
    private func alphabetize() {
        let parent = Parent.folder(itemID: itemID)
        let sorted = tabs.children(of: parent).sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return tabs.title(for: $0).localizedCaseInsensitiveCompare(tabs.title(for: $1)) == .orderedAscending
        }
        var previous: UUID?
        for child in sorted {
            tabs.move(child.id, to: parent, after: previous)
            previous = child.id
        }
    }
}
