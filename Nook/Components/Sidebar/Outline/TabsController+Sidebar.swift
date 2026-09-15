//
//  TabsController+Sidebar.swift
//  Nook
//
//  Sidebar helpers built only from TabsController's public intents and reads.
//

import AppKit
import NookTabsCore
import SwiftUI

extension TabsController {
    // MARK: - Drops

    /// Applies a drop on one sidebar section's displayed rows.
    /// `before` and `into` go through `drop(...)`; `after` a row places the item next to that row
    /// at the row's own level, so an item can land after the last child of a folder.
    func drop(_ itemID: UUID, at position: DropPosition, section: Parent, rows: [Row]) {
        let index = position.index
        guard index < rows.count else {
            drop(itemID, section: section, rows: rows, index: rows.count, intoFolder: false)
            return
        }
        let row = rows[index]
        guard row.item.id != itemID else { return }
        switch position.placement {
        case .into:
            drop(itemID, section: section, rows: rows, index: index, intoFolder: true)
        case .before:
            drop(itemID, section: section, rows: rows, index: index, intoFolder: false)
        case .after:
            if index + 1 < rows.count, rows[index + 1].depth > row.depth {
                // An open folder: right below its header is its first child.
                drop(itemID, section: section, rows: rows, index: index + 1, intoFolder: false)
            } else {
                move(itemID, to: row.item.parent, after: row.item.id)
            }
        }
    }

    /// Drops into a profile's favorites grid at tile `index` of the displayed favorites.
    func dropOnFavorites(_ itemID: UUID, profileID: UUID, index: Int) {
        let favorites = favorites(of: profileID)
        let after = favorites.prefix(index).last(where: { $0.id != itemID })?.id
        move(itemID, to: .favorites(profileID: profileID), after: after)
    }

    // MARK: - Reads

    /// Every folder in a space's pinned and tabs sections, depth first, with its depth.
    func folders(inSpace spaceID: UUID) -> [(item: Item, depth: Int)] {
        var result: [(item: Item, depth: Int)] = []
        func walk(_ parent: Parent, depth: Int) {
            for child in children(of: parent) where child.isFolder {
                result.append((child, depth))
                walk(.folder(itemID: child.id), depth: depth + 1)
            }
        }
        walk(.pinned(spaceID: spaceID), depth: 0)
        walk(.tabs(spaceID: spaceID), depth: 0)
        return result
    }

    /// True for favorites and pinned items (and anything inside pinned folders).
    func isSynced(_ itemID: UUID) -> Bool {
        switch section(of: itemID) {
        case .favorites, .pinned: return true
        default: return false
        }
    }

    /// Row title: custom title, else the live page title, else the saved page title, else the host.
    func title(for item: Item) -> String {
        if let custom = item.customTitle, !custom.isEmpty { return custom }
        if let live = session(for: item.id)?.title, !live.isEmpty { return live }
        if !item.displayTitle.isEmpty { return item.displayTitle }
        return item.url?.host ?? "New Tab"
    }

    /// Current page URL: the live page, else the saved URL.
    func currentURL(for item: Item) -> URL? {
        session(for: item.id)?.url ?? item.url
    }
}

// MARK: - Rename State

/// The row being renamed inline. Shared so a context menu can start a rename its row shows.
@MainActor
@Observable
final class SidebarRenameState {
    static let shared = SidebarRenameState()
    var itemID: UUID?
}

extension TabsController {
    /// Creates "New Folder" under `parent` after `after` and starts renaming it inline.
    func createFolderForRename(in parent: Parent, after: UUID?) {
        guard let folderID = createFolder(title: "New Folder", in: parent, after: after) else { return }
        if case .folder(let outer) = parent { openFolder(outer) }
        SidebarRenameState.shared.itemID = folderID
    }
}

// MARK: - Favicon

/// A row or tile favicon: the live page's, else the cached one for the item's host, else a globe.
struct ItemFavicon: View {
    let item: Item
    let session: PageSession?
    @State private var cached: Image?

    var body: some View {
        (session?.favicon ?? cached ?? Image(systemName: "globe"))
            .resizable()
            .scaledToFit()
            // Keyed on the session too: closing a pinned tab or favorite ends its page but keeps
            // the row, and the cached icon must be loaded then.
            .task(id: "\(item.url?.host ?? "")|\(session == nil)") {
                session?.ensureFaviconLoaded()
                guard let host = item.url?.host,
                      let image = await FaviconCache.shared.cachedImage(for: host) else { return }
                cached = Image(nsImage: image)
            }
    }
}
