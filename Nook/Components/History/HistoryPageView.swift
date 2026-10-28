// Licensed under GPL-3.0. See LICENSE.
//
//  HistoryPageView.swift
//  Nook
//
//  History as a page over the web content, as Arc's is: search, every visit grouped by day,
//  checkboxes to delete several at once. Opened with Cmd-Y; selecting a tab closes it.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct HistoryPageView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    @State private var query = ""
    @State private var entries: [HistoryEntry] = []
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var selection: Set<UUID> = []
    @State private var loadTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private let navWidth: CGFloat = 260
    private let pageSize = 100
    private let contentMaxWidth: CGFloat = 960
    private let timeWidth: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            navigation
                .frame(width: navWidth)
            Divider()
            VStack(spacing: NookDesign.Spacing.lg) {
                toolbar
                list
            }
            .padding(.horizontal, NookDesign.Spacing.xxxl)
            .padding(.top, NookDesign.Spacing.xl)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(NookDesign.Surface.windowBackground)
        .onAppear {
            searchFocused = true
            reload()
        }
        .onChange(of: query) { _, _ in reload() }
        // Choosing a tab or a space leaves History, as leaving Arc's history tab does.
        .onChange(of: windowState.selectedItemID) { _, _ in close() }
        .onChange(of: windowState.spaceID) { _, _ in close() }
        .onExitCommand(perform: close)
    }

    // MARK: - Navigation

    private var navigation: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(NookDesign.Font.titleLarge)
                Text("History")
                    .font(NookDesign.Font.display)
                Spacer()
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .nookIconButtons()
                    .help("Close History")
            }
            .padding(.bottom, NookDesign.Spacing.lg)

            navRow("Nook History", symbol: "clock", isSelected: true) {}
            navRow("Clear Browsing Data…", symbol: "trash", isSelected: false) {
                browserManager.openSettings(tab: .privacy)
            }
            Spacer()
        }
        .padding(NookDesign.Spacing.xl)
    }

    private func navRow(_ title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(NookDesign.Font.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NookDesign.Spacing.rowPadding)
                .frame(height: NookDesign.Size.row + NookDesign.Spacing.xs)
                .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .nookRowSelection(isSelected)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        if selection.isEmpty {
            HStack(spacing: NookDesign.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .font(NookDesign.Font.body)
            .padding(.horizontal, NookDesign.Spacing.lg)
            .frame(height: NookDesign.Size.row + NookDesign.Spacing.md)
            .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
        } else {
            HStack(spacing: NookDesign.Spacing.md) {
                Text("\(selection.count) selected")
                    .font(NookDesign.Font.label)
                    .contentTransition(.numericText())
                Spacer()
                Button("Cancel") { withAnimation(NookDesign.Motion.standard) { selection.removeAll() } }
                    .buttonStyle(RectNavButtonStyle())
                Button("Delete", systemImage: "trash", action: deleteSelected)
                    .buttonStyle(RectNavButtonStyle())
            }
            .padding(.horizontal, NookDesign.Spacing.lg)
            .frame(height: NookDesign.Size.row + NookDesign.Spacing.md)
            .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if entries.isEmpty && !isLoading {
                    Text(query.isEmpty ? "No history yet" : "No results")
                        .font(NookDesign.Font.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NookDesign.Spacing.xxxl)
                }
                ForEach(Self.days(entries), id: \.day) { group in
                    Text(Self.title(for: group.day))
                        .font(NookDesign.Font.heading)
                        .padding(.horizontal, NookDesign.Spacing.lg)
                        .padding(.top, NookDesign.Spacing.xl)
                        .padding(.bottom, NookDesign.Spacing.md)
                    ForEach(group.entries) { entry in
                        HistoryPageRow(
                            entry: entry,
                            timeWidth: timeWidth,
                            isSelected: selection.contains(entry.id),
                            onToggle: { toggle(entry.id) },
                            onOpen: { open(entry.url, newTab: false) },
                            onOpenInNewTab: { open(entry.url, newTab: true) },
                            onDelete: { delete([entry.id]) })
                    }
                }
                if hasMore {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NookDesign.Spacing.lg)
                        .id(entries.count)
                        .onAppear(perform: loadMore)
                }
            }
            .padding(.bottom, NookDesign.Spacing.xl)
            .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
            .padding(.bottom, NookDesign.Spacing.xl)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: - Data

    private func reload() {
        load(reset: true)
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        load(reset: false)
    }

    private func load(reset: Bool) {
        loadTask?.cancel()
        let text = query
        let offset = reset ? 0 : entries.count
        isLoading = true
        loadTask = Task { @MainActor in
            if reset && !text.isEmpty {
                do { try await Task.sleep(for: .milliseconds(125)) } catch { return }
            }
            let history = browserManager.historyManager
            let result = text.isEmpty
                ? await history.getHistory(days: HistoryManager.retentionDays, offset: offset, limit: pageSize)
                : await history.searchHistory(query: text, offset: offset, limit: pageSize)
            guard !Task.isCancelled else { return }
            entries = reset ? result.entries : entries + result.entries
            hasMore = result.hasMore
            isLoading = false
            if reset { selection.removeAll() }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func deleteSelected() {
        delete(Array(selection))
    }

    /// Rows leave in place, so paging by offset stays lined up with the store.
    private func delete(_ ids: [UUID]) {
        for id in ids { browserManager.historyManager.deleteHistoryEntry(id) }
        withAnimation(NookDesign.Motion.standard) {
            entries.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }

    private func open(_ url: URL, newTab: Bool) {
        close()
        browserManager.tabs.open(url: url, in: windowState,
                                 placement: newTab || windowState.selectedItemID == nil ? .newTab : .replaceCurrent)
    }

    private func close() {
        withAnimation(NookDesign.Motion.standard) { windowState.isHistoryPageVisible = false }
    }

    // MARK: - Days

    private struct Day {
        let day: Date
        let entries: [HistoryEntry]
    }

    private static func days(_ entries: [HistoryEntry]) -> [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.lastVisited) }
        return grouped.keys.sorted(by: >).map { day in
            Day(day: day, entries: grouped[day]!.sorted { $0.lastVisited > $1.lastVisited })
        }
    }

    private static func title(for day: Date) -> String {
        let full = day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today - " + full }
        if calendar.isDateInYesterday(day) { return "Yesterday - " + full }
        return full
    }
}

private struct HistoryPageRow: View {
    let entry: HistoryEntry
    let timeWidth: CGFloat
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            Toggle("Select", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(entry.lastVisited.formatted(date: .omitted, time: .shortened))
                .font(NookDesign.Font.secondary.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: timeWidth, alignment: .leading)
            HistoryFavicon(url: entry.url)
            HStack(spacing: NookDesign.Spacing.sm) {
                Text(entry.displayTitle)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                Text(entry.url.host ?? "")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Open in New Tab", action: onOpenInNewTab)
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
                }
                Divider()
                Button("Remove from History", action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(NookIconButtonStyle())
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, NookDesign.Spacing.lg)
        .frame(height: NookDesign.Size.row + NookDesign.Spacing.md)
        .background(isHovered || isSelected ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .padding(.horizontal, NookDesign.Spacing.sm)
        .onHoverTracking { hovered in
            withAnimation(NookDesign.Motion.quick) { isHovered = hovered }
        }
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Open in New Tab", action: onOpenInNewTab)
            Divider()
            Button("Remove from History", action: onDelete)
        }
    }
}
