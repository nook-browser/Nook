// Licensed under GPL-3.0. See LICENSE.
//
//  FavoritesGrid.swift
//  NookiOS
//
//  A space's favorites as four tiles to a row, above the outline. The phone
//  shows it in the tab sheet and the iPad in the sidebar, so it lives on its own
//  rather than inside either.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

struct FavoritesGrid: View {
    let spaceID: UUID
    /// Runs after a tile is chosen; the sheet closes, the sidebar does not.
    let onSelect: () -> Void

    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: NookDesign.Spacing.sm),
        count: 4
    )

    var body: some View {
        let items = tabs.favorites(of: spaceID)
        if !items.isEmpty {
            LazyVGrid(columns: columns, spacing: NookDesign.Spacing.sm) {
                ForEach(items, id: \.id) { item in
                    tile(item)
                }
            }
            // The grid takes a drop anywhere in it; favorites append rather than
            // land at an index, the way the Mac's pin intent does.
            .dropDestination(for: String.self) { ids, _ in
                guard let first = ids.first, let dragged = UUID(uuidString: first) else { return false }
                tabs.pin(dragged, to: .favorites(spaceID: spaceID))
                Haptics.alignment()
                return true
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        let session = tabs.session(for: item.id)
        return PinnedTabView(
            tabName: tabs.title(for: item),
            tabURL: item.url?.absoluteString ?? "",
            tabIcon: ItemFavicon(item: item, session: session),
            isActive: tabs.selectedItemID(in: window) == item.id,
            isUnloaded: session?.isUnloaded ?? true,
            hasLeftPinnedURL: tabs.hasLeftHome(item.id),
            onResetToPinnedURL: { tabs.resetToHome(item.id) },
            action: {
                tabs.select(item.id, in: window)
                onSelect()
            }
        )
        .frame(maxWidth: .infinity)
        // PinnedTabView takes a generic icon and no item id, so the menu is
        // attached here rather than inside the shared view.
        .contextMenu {
            TabContextMenu(itemID: item.id, context: .favorite)
                .environment(window)
                .environment(tabs)
                .environment(\.tabActions, model)
        }
        .draggable(item.id.uuidString)
    }
}
