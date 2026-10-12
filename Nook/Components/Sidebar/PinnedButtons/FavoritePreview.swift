// Licensed under GPL-3.0. See LICENSE.
//
//  FavoritePreview.swift
//  Nook
//
//  The card under a favorite the pointer rests on: the pages last visited on its site, and on
//  github.com the person's open pull requests. Nothing is fetched until the pointer rests.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

@MainActor
@Observable
final class FavoritePreview {
    static let shared = FavoritePreview()

    struct Row: Identifiable, Hashable {
        let url: URL
        let title: String
        let isPullRequest: Bool
        var id: URL { url }
    }

    /// The favorite whose card is up and the window showing it.
    private(set) var itemID: UUID?
    private(set) var windowID: UUID?
    private(set) var rows: [Row] = []

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var tileUnderPointer: UUID?
    @ObservationIgnored private var pointerOverCard = false
    @ObservationIgnored private var cache: [UUID: (at: Date, rows: [Row])] = [:]

    private static let restDelay: Duration = .milliseconds(600)
    /// Moving from one favorite to the next while a card is up.
    private static let switchDelay: Duration = .milliseconds(150)
    /// Time to travel from the tile into the card.
    private static let closeDelay: Duration = .milliseconds(200)
    private static let cacheAge: TimeInterval = 60
    private static let rowLimit = 6

    func tileHover(_ item: Item, hovering: Bool, in window: BrowserWindowState, tabs: TabsController) {
        guard hovering else {
            if tileUnderPointer == item.id {
                tileUnderPointer = nil
                closeSoon()
            }
            return
        }
        tileUnderPointer = item.id
        guard itemID != item.id, tabs.settings.favoritePreviews, !NookDragSessionManager.shared.isDragging else { return }
        pending?.cancel()
        let delay = itemID == nil ? Self.restDelay : Self.switchDelay
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, tileUnderPointer == item.id else { return }
            let rows = await load(item, tabs: tabs)
            guard !Task.isCancelled, tileUnderPointer == item.id else { return }
            guard !rows.isEmpty else { return dismiss() }
            self.rows = rows
            itemID = item.id
            windowID = window.id
        }
    }

    func cardHover(_ hovering: Bool) {
        pointerOverCard = hovering
        if hovering { pending?.cancel() } else { closeSoon() }
    }

    func dismiss() {
        pending?.cancel()
        itemID = nil
        windowID = nil
        rows = []
    }

    private func closeSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled, tileUnderPointer == nil, !pointerOverCard else { return }
            dismiss()
        }
    }

    private func load(_ item: Item, tabs: TabsController) async -> [Row] {
        if let cached = cache[item.id], Date().timeIntervalSince(cached.at) < Self.cacheAge { return cached.rows }
        guard let home = item.url, let host = home.host else { return [] }
        var rows: [Row] = []
        if host == "github.com", let spaceID = tabs.spaceID(of: item.id) {
            rows = await tabs.pullRequests(inSpace: spaceID).map { Row(url: $0.url, title: $0.title, isPullRequest: true) }
        }
        let visited = await tabs.history?.searchHistory(query: host, offset: 0, limit: 40).entries ?? []
        var seen = Set(rows.map(\.url) + [home])
        var titles = Set(rows.map(\.title))
        for entry in visited where entry.url.host == host && entry.url.path.count > 1 {
            // One row per page: a site that puts state in the query gives many URLs one title.
            guard seen.insert(entry.url).inserted, titles.insert(entry.displayTitle).inserted else { continue }
            rows.append(Row(url: entry.url, title: entry.displayTitle, isPullRequest: false))
        }
        rows = Array(rows.prefix(Self.rowLimit))
        cache[item.id] = (Date(), rows)
        return rows
    }
}

/// The hovered favorite's frame, reported so the card can hang under it.
struct FavoritePreviewAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Drawn in the window, like `ExtensionLibraryOverlay`.
struct FavoritePreviewOverlay: View {
    let anchor: Anchor<CGRect>?

    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    private let preview = FavoritePreview.shared
    private let cardWidth: CGFloat = 280

    var body: some View {
        GeometryReader { proxy in
            if let anchor, let itemID = preview.itemID, preview.windowID == windowState.id {
                let tile = proxy[anchor]
                let edge = NookDesign.Spacing.md
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    ForEach(preview.rows) { row in
                        Button {
                            open(row.url, in: itemID)
                        } label: {
                            HStack(spacing: NookDesign.Spacing.md) {
                                Image(systemName: row.isPullRequest ? "arrow.triangle.pull" : "clock")
                                    .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(row.title)
                                    .font(NookDesign.Font.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(RectNavButtonStyle())
                    }
                }
                .padding(NookDesign.Spacing.xs)
                .frame(width: cardWidth)
                .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                .onHoverTracking { preview.cardHover($0) }
                .offset(
                    x: min(max(edge, tile.minX), max(edge, proxy.size.width - cardWidth - edge)),
                    y: tile.maxY + NookDesign.Spacing.xs
                )
                .transition(.opacity)
            }
        }
        .animation(NookDesign.Motion.quick, value: preview.itemID)
    }

    private func open(_ url: URL, in itemID: UUID) {
        preview.dismiss()
        tabs.select(itemID, in: windowState)
        tabs.session(for: itemID)?.load(url)
    }
}
