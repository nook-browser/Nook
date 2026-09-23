// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuHistoryTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import FaviconFinder
import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct HistorySection: Identifiable {
    var id: String { title }
    let title: String
    let entries: [HistoryEntry]
}

enum TimeRange: String, CaseIterable {
    case today = "D"
    case week = "W"
    case month = "M"
    case all = "ALL"

    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .all: return HistoryManager.retentionDays
        }
    }
}

struct SidebarMenuHistoryTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var text: String = ""

    @State private var historyEntries: [HistoryEntry] = []
    @State private var groupedHistoryEntries: [HistorySection] = []
    @State private var selectedTimeRange: TimeRange = .week
    @State private var isLoading: Bool = false
    @State private var hasMoreResults: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var isShowingFilters: Bool = false
    @State private var isFiltersHovered: Bool = false

    @State private var historyTask: Task<Void, Never>?
    @State private var requestID = UUID()

    private let pageSize: Int = 50

    var body: some View {
        ScrollView {
            list
                .padding(.horizontal, NookDesign.Spacing.md)
                .padding(.bottom, NookDesign.Spacing.md)
        }
        // The rows scroll under the search field and filters, which float as glass with the
        // system's soft blur at the edge behind them, the way a macOS 26 toolbar does.
        .safeAreaBar(edge: .top, spacing: 0) {
            header
                .padding(NookDesign.Spacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onAppear {
            loadHistory()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            loadHistory()
        }
        .onChange(of: browserManager.historyManager.currentProfileId) { _, _ in
            loadHistory()
        }
        .onDisappear { historyTask?.cancel() }
    }

    private var header: some View {
        VStack(spacing: NookDesign.Spacing.md) {
            HStack(spacing: NookDesign.Spacing.xs) {
                SidebarMenuSearchField(prompt: "Search history...", text: $text)
                    .onChange(of: text) { _, _ in loadHistory() }

                Button {
                    isShowingFilters.toggle()
                } label: {
                    // Always glass, like the search field beside it: both float over the list.
                    HStack(spacing: NookDesign.Spacing.xs) {
                        Image(systemName: isShowingFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                            .font(NookDesign.Font.title)
                        Text("Filters")
                            .font(NookDesign.Font.body)
                    }
                    .foregroundStyle(isShowingFilters || isFiltersHovered ? .primary : .secondary)
                    .padding(.horizontal, NookDesign.Spacing.lg)
                    .frame(height: NookDesign.Size.glassControl)
                    .contentShape(Capsule())
                    .nookControlGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .animation(NookDesign.Motion.quick, value: isShowingFilters)
                .animation(NookDesign.Motion.quick, value: isFiltersHovered)
                .onHoverTracking { isFiltersHovered = $0 }
            }
            if isShowingFilters {
                FiltersSelectView(selectedTimeRange: $selectedTimeRange)
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: NookDesign.Spacing.rowGap) {
            // A reload keeps the list on screen; only a first load shows the spinner.
            if isLoading && groupedHistoryEntries.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading history...")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if groupedHistoryEntries.isEmpty {
                VStack(spacing: NookDesign.Spacing.md) {
                    Image(systemName: "clock")
                        .font(NookDesign.Font.titleLarge)
                        .foregroundStyle(.tertiary)

                    Text(
                        text.isEmpty
                            ? "No history yet" : "No results found"
                    )
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.secondary)

                    if text.isEmpty {
                        Text(
                            "Visit some websites to see your history here"
                        )
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ForEach(groupedHistoryEntries) { section in
                    Text(section.title)
                        .font(NookDesign.Font.captionStrong)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, NookDesign.Spacing.rowPadding)
                        .padding(.top, NookDesign.Spacing.md)
                        .padding(.bottom, NookDesign.Spacing.xs)

                    ForEach(section.entries) { entry in
                        HistoryRowView(
                            entry: entry,
                            onTap: { openInCurrentTab(entry.url) },
                            onOpenInNewTab: { openInNewTab(entry.url) },
                            onDelete: { deleteEntry(entry) }
                        )
                    }
                }

                // Loads the next page when it scrolls into view, however short the last
                // section is. A new identity per page means a page that leaves it on
                // screen asks again, and one that pushes it off screen waits.
                if hasMoreResults {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading more...")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.md)
                    .id(historyEntries.count)
                    .onAppear { loadMoreHistory() }
                }
            }
        }
    }

    // MARK: Functions

    private func loadHistory() {
        requestHistory(reset: true)
    }

    private func loadMoreHistory() {
        guard hasMoreResults, !isLoading, !isLoadingMore else { return }
        requestHistory(reset: false)
    }

    private func requestHistory(reset: Bool) {
        historyTask?.cancel()
        let id = UUID()
        requestID = id
        let query = text
        let days = selectedTimeRange.days
        let offset = reset ? 0 : historyEntries.count
        let profile = browserManager.historyManager.currentProfileId
        isLoading = reset
        isLoadingMore = !reset
        historyTask = Task { @MainActor in
            if reset && !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(125)) } catch { return }
            }
            let result: (entries: [HistoryEntry], hasMore: Bool)
            if query.isEmpty {
                result = await browserManager.historyManager.getHistory(days: days, offset: offset, limit: pageSize)
            } else {
                result = await browserManager.historyManager.searchHistory(query: query, offset: offset, limit: pageSize)
            }
            guard !Task.isCancelled, requestID == id,
                  browserManager.historyManager.currentProfileId == profile else { return }
            withAnimation(NookDesign.Motion.standard) {
                historyEntries = reset ? result.entries : historyEntries + result.entries
                groupedHistoryEntries = groupHistoryEntries(historyEntries)
                hasMoreResults = result.hasMore
                isLoading = false
                isLoadingMore = false
            }
        }
    }

    /// Sections ordered by their newest visit, which is the order the labels describe.
    private func groupHistoryEntries(_ entries: [HistoryEntry])
        -> [HistorySection]
    {
        let calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.year, .month, .weekOfYear], from: now)

        let grouped = Dictionary(grouping: entries) { entry in
            let components = calendar.dateComponents(
                [.year, .month, .weekOfYear],
                from: entry.lastVisited
            )

            if calendar.isDate(entry.lastVisited, inSameDayAs: now) {
                return "Today"
            } else if calendar.isDateInYesterday(entry.lastVisited) {
                return "Yesterday"
            } else if components.year == nowComponents.year
                && components.weekOfYear == nowComponents.weekOfYear
            {
                return "This Week"
            } else if let weekDiff = calendar.dateComponents(
                [.weekOfYear],
                from: entry.lastVisited,
                to: now
            ).weekOfYear {
                // Under seven days but in an earlier calendar week counts 0 whole weeks.
                if weekDiff <= 1 {
                    return "Last Week"
                } else if weekDiff <= 4 {
                    return "\(weekDiff) weeks ago"
                } else if components.year == nowComponents.year
                    && components.month == nowComponents.month
                {
                    return "This Month"
                } else if let monthDiff = calendar.dateComponents(
                    [.month],
                    from: entry.lastVisited,
                    to: now
                ).month {
                    if monthDiff == 1 {
                        return "Last Month"
                    } else if monthDiff <= 12 {
                        return "\(monthDiff) months ago"
                    } else {
                        let yearDiff =
                            calendar.dateComponents(
                                [.year],
                                from: entry.lastVisited,
                                to: now
                            ).year ?? 0
                        return yearDiff == 1
                            ? "Last Year" : "\(yearDiff) years ago"
                    }
                } else {
                    return "Older"
                }
            } else {
                return "Older"
            }
        }

        // Newest first inside each section, and sections by their newest entry: sorting the
        // titles put "10 months ago" above "2 months ago" and "2 months ago" above "2 weeks ago".
        return grouped
            .map { HistorySection(title: $0.key, entries: $0.value.sorted { $0.lastVisited > $1.lastVisited }) }
            .sorted { $0.entries[0].lastVisited > $1.entries[0].lastVisited }
    }

    private func openInCurrentTab(_ url: URL) {
        guard let window = browserManager.windowRegistry?.activeWindow else { return }
        browserManager.tabs.open(url: url, in: window, placement: window.selectedItemID == nil ? .newTab : .replaceCurrent)
    }

    private func openInNewTab(_ url: URL) {
        guard let window = browserManager.windowRegistry?.activeWindow else { return }
        browserManager.tabs.open(url: url, in: window, placement: .newTab)
    }

    /// Paging is by offset from what is on screen, so dropping the row here keeps the next page
    /// lined up with the store; reloading from the top lost every page past the first.
    private func deleteEntry(_ entry: HistoryEntry) {
        browserManager.historyManager.deleteHistoryEntry(entry.id)
        withAnimation(NookDesign.Motion.standard) {
            historyEntries.removeAll { $0.id == entry.id }
            groupedHistoryEntries = groupHistoryEntries(historyEntries)
        }
    }
}

struct HistoryRowView: View {
    let entry: HistoryEntry
    let onTap: () -> Void
    let onOpenInNewTab: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var favicon: SwiftUI.Image?

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            (favicon ?? SwiftUI.Image(systemName: "globe"))
                .resizable()
                .scaledToFit()
                .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.displayTitle)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()

                Text(entry.url.host ?? "")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .nookTrailingFade()

            if isHovered {
                HStack(spacing: 0) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .help("Remove from history")

                    Button(action: onOpenInNewTab) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("Open in a new tab")
                }
                .font(NookDesign.Font.caption)
                .buttonStyle(NookIconButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .padding(.vertical, NookDesign.Spacing.sm)
        .background(isHovered ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { hovered in
            withAnimation(NookDesign.Motion.quick) {
                isHovered = hovered
            }
        }
        .onTapGesture {
            onTap()
        }
        // Cancelled when the row scrolls away; the old onAppear Task kept fetching for rows long gone.
        .task(id: entry.url.host) {
            guard entry.url.scheme == "http" || entry.url.scheme == "https",
                  let host = entry.url.host else { return }
            if let cached = await FaviconCache.shared.cachedImage(for: host) {
                favicon = SwiftUI.Image(nsImage: cached)
                return
            }
            guard let image = try? await FaviconFinder(url: entry.url).fetchFaviconURLs().download().largest().image?.image,
                  !Task.isCancelled else { return }
            FaviconCache.shared.store(image, for: host)
            favicon = SwiftUI.Image(nsImage: image)
        }
        .contextMenu {
            Button("Open") { onTap() }
            Button("Open in New Tab") {
                onOpenInNewTab()
            }
            Divider()
            Button("Remove from History") { onDelete() }
        }
    }
}

struct FiltersSelectView: View {
    @Binding var selectedTimeRange: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            Text("When was the tab closed?")
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
                HStack(spacing: NookDesign.Spacing.sm) {
                    FiltersSelectButton(
                        text: "All time",
                        isActive: selectedTimeRange == .all
                    ) {
                        selectedTimeRange = .all
                    }
                    FiltersSelectButton(
                        text: "Today",
                        isActive: selectedTimeRange == .today
                    ) {
                        selectedTimeRange = .today
                    }
                    FiltersSelectButton(
                        text: "This week",
                        isActive: selectedTimeRange == .week
                    ) {
                        selectedTimeRange = .week
                    }
                }
                FiltersSelectButton(
                    text: "This month",
                    isActive: selectedTimeRange == .month
                ) {
                    selectedTimeRange = .month
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A filter chip. Every chip is glass, since the row floats over the list; the chosen one is
/// tinted with the space's accent.
struct FiltersSelectButton: View {
    var text: String
    var isActive: Bool
    var action: () -> Void

    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var isHovering: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(text)
                .font(NookDesign.Font.body)
                .foregroundStyle(isActive || isHovering ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, NookDesign.Spacing.lg)
                .frame(height: NookDesign.Size.iconButton)
                .contentShape(Capsule())
                .nookControlGlass(tint: isActive ? gradientColorManager.accentColor : nil, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(NookDesign.Motion.quick, value: isHovering)
        .animation(NookDesign.Motion.standard, value: isActive)
        .onHoverTracking { state in
            isHovering = state
        }
    }
}
