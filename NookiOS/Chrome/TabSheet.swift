// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  TabSheet.swift
//  NookiOS
//
//  The phone's tab surface: the macOS sidebar outline at phone width. It opens
//  large because it is the deliberate surface (find, reorder, pin); quick
//  switching is the swipe on the bar. It drops to medium on a drag.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

struct TabSheet: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window
    @Environment(\.dismiss) private var dismiss

    @State private var detent: PresentationDetent = .large

    private var spaceID: UUID? { window.spaceID }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: NookDesign.Spacing.sm),
        count: 4
    )

    var body: some View {
        ScrollView {
            if let spaceID {
                LazyVStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
                    favorites(spaceID)
                    TabSheetRows(spaceID: spaceID) { dismiss() }
                }
                .padding(NookDesign.Spacing.rowPadding)
            }
        }
        .safeAreaInset(edge: .top) {
            header
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ZStack {
            // Centred regardless of the close button's width.
            SpacesList()
                .frame(height: NookDesign.Spacing.xl)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: NookDesign.Size.iconButton)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        // Clears the sheet's own drag indicator, which draws at the same top edge.
        .padding(.top, NookDesign.Spacing.xxl)
        .padding(.bottom, NookDesign.Spacing.md)
        .background(.bar)
    }

    @ViewBuilder
    private func favorites(_ spaceID: UUID) -> some View {
        let items = tabs.favorites(of: spaceID)
        if !items.isEmpty {
            LazyVGrid(columns: columns, spacing: NookDesign.Spacing.sm) {
                ForEach(items, id: \.id) { item in
                    let session = tabs.session(for: item.id)
                    PinnedTabView(
                        tabName: tabs.title(for: item),
                        tabURL: item.url?.absoluteString ?? "",
                        tabIcon: ItemFavicon(item: item, session: session),
                        isActive: tabs.selectedItemID(in: window) == item.id,
                        isUnloaded: session?.isUnloaded ?? true,
                        hasLeftPinnedURL: tabs.hasLeftHome(item.id),
                        onResetToPinnedURL: { tabs.resetToHome(item.id) },
                        action: {
                            tabs.select(item.id, in: window)
                            dismiss()
                        }
                    )
                    .frame(maxWidth: .infinity)
                    // PinnedTabView takes a generic icon and no item id, so the
                    // menu is attached here rather than inside the shared view.
                    .contextMenu {
                        TabContextMenu(itemID: item.id, context: .favorite)
                            .environment(window)
                            .environment(tabs)
                            .environment(\.tabActions, model)
                    }
                }
            }
        }
    }
}
