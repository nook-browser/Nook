//
//  SidebarMenuHistoryTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import FaviconFinder
import Garnish
import SwiftUI

struct HistorySection: Identifiable {
    let id = UUID()
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
        case .all: return 100
        }
    }
}

struct SidebarMenuHistoryTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var isHovering: Bool = false
    @State private var text: String = ""
    @FocusState private var isSearchFocused: Bool

    @State private var historyEntries: [HistoryEntry] = []
    @State private var groupedHistoryEntries: [HistorySection] = []
    @State private var selectedTimeRange: TimeRange = .week
    @State private var isLoading: Bool = false
    @State private var currentPage: Int = 0
    @State private var hasMoreResults: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var isShowingFilters: Bool = false

    private let pageSize: Int = 50
    private let maxResults: Int = 1000

    private var contrastText: Color {
        Garnish.contrastingShade(of: gradientColorManager.primaryColor, targetRatio: 4.5, blendStyle: .strong) ?? .white
    }

    private var contrastTextSecondary: Color {
        contrastText.opacity(0.7)
    }

    private var contrastTextTertiary: Color {
        contrastText.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 3) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(contrastTextTertiary)
                        .frame(width: 16, height: 16)
                    TextField("Search history...", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(contrastTextTertiary)
                        .focused($isSearchFocused)
                        .onChange(of: text) { _, _ in
                            searchHistory()
                        }

                    if !text.isEmpty {
                        Button(action: {
                            text = ""
                            loadHistory()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background(
                    isHovering ? contrastText.opacity(0.08) : contrastText.opacity(0.05)
                )
                .animation(.easeInOut(duration: 0.1), value: isHovering)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onHover { state in
                    isHovering = state
                }
                .onTapGesture {
                    isSearchFocused = true
                }

                Button {
                    isShowingFilters.toggle()
                } label: {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(
                                isShowingFilters
                                    ? Color(hex: "1E1E1E") : contrastTextSecondary
                            )
                        Text("Filters")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                isShowingFilters
                                    ? Color(hex: "1E1E1E") : contrastTextSecondary
                            )
                    }
                    .padding(10)
                    .background(
                        isShowingFilters
                            ? contrastText.opacity(0.6) : contrastText.opacity(0.05)
                    )
                    .animation(
                        .easeInOut(duration: 0.1),
                        value: isShowingFilters
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
            if isShowingFilters {
                FiltersSelectView(selectedTimeRange: $selectedTimeRange)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading history...")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if groupedHistoryEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.textTertiary)

                            Text(
                                text.isEmpty
                                    ? "No history yet" : "No results found"
                            )
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)

                            if text.isEmpty {
                                Text(
                                    "Visit some websites to see your history here"
                                )
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                                .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        ForEach(groupedHistoryEntries) { section in
                            VStack(alignment: .leading, spacing: 0) {
                                // Section Header
                                HStack {
                                    Text(section.title)
                                        .font(
                                            .system(size: 13, weight: .semibold)
                                        )
                                        .foregroundColor(
                                            AppColors.textPrimary.opacity(0.7)
                                        )
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                // Section Entries
                                ForEach(section.entries.indices, id: \.self) {
                                    index in
                                    let entry = section.entries[index]
                                    HistoryRowView(
                                        entry: entry,
                                        onTap: { openInCurrentTab(entry.url) },
                                        onDelete: { deleteEntry(entry) }
                                    )
                                    .onAppear {
                                        // Load more when approaching the end of the last section
                                        if section.id
                                            == groupedHistoryEntries.last?.id
                                            && index == section.entries.count
                                            - 5
                                            && hasMoreResults && !isLoadingMore
                                        {
                                            loadMoreHistory()
                                        }
                                    }
                                }
                            }
                        }

                        // Load more indicator
                        if isLoadingMore {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading more...")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding(8)
        .onAppear {
            loadHistory()
        }
    }

    // MARK: Functions

    private func loadHistory() {
        isLoading = true
        currentPage = 0

        Task { @MainActor in
            let result = browserManager.historyManager.getHistory(
                days: selectedTimeRange.days,
                page: currentPage,
                pageSize: pageSize
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                historyEntries = result.entries
                groupedHistoryEntries = groupHistoryEntries(result.entries)
                hasMoreResults = result.hasMore
                isLoading = false
            }
        }
    }

    private func loadMoreHistory() {
        guard hasMoreResults, !isLoadingMore else { return }

        isLoadingMore = true
        currentPage += 1

        Task { @MainActor in
            let result: (entries: [HistoryEntry], hasMore: Bool)

            if text.isEmpty {
                result = browserManager.historyManager.getHistory(
                    days: selectedTimeRange.days,
                    page: currentPage,
                    pageSize: pageSize
                )
            } else {
                result = browserManager.historyManager.searchHistory(
                    query: text,
                    page: currentPage,
                    pageSize: pageSize
                )
            }

            let animationDelay = historyEntries.count > 100 ? 0.1 : 0.2

            withAnimation(.easeInOut(duration: animationDelay)) {
                historyEntries.append(contentsOf: result.entries)
                groupedHistoryEntries = groupHistoryEntries(historyEntries)
                hasMoreResults = result.hasMore
                isLoadingMore = false
            }
        }
    }

    private func searchHistory() {
        guard !text.isEmpty else {
            loadHistory()
            return
        }

        isLoading = true
        currentPage = 0

        Task { @MainActor in
            let result = browserManager.historyManager.searchHistory(
                query: text,
                page: currentPage,
                pageSize: pageSize
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                historyEntries = result.entries
                groupedHistoryEntries = groupHistoryEntries(result.entries)
                hasMoreResults = result.hasMore
                isLoading = false
            }
        }
    }

    private func groupHistoryEntries(_ entries: [HistoryEntry])
        -> [HistorySection]
    {
        let calendar = Calendar.current
        let now = Date()

        let grouped = Dictionary(grouping: entries) { entry in
            let components = calendar.dateComponents(
                [.year, .month, .weekOfYear, .day],
                from: entry.lastVisited
            )
            let nowComponents = calendar.dateComponents(
                [.year, .month, .weekOfYear, .day],
                from: now
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
                if weekDiff == 1 {
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

        let sortedKeys = grouped.keys.sorted { key1, key2 in
            let priority: [String: Int] = [
                "Today": 0,
                "Yesterday": 1,
                "This Week": 2,
                "Last Week": 3,
                "This Month": 4,
                "Last Month": 5,
            ]

            if let p1 = priority[key1], let p2 = priority[key2] {
                return p1 < p2
            } else if priority[key1] != nil {
                return true
            } else if priority[key2] != nil {
                return false
            } else {
                return key1 < key2
            }
        }

        return sortedKeys.compactMap { (key: String) -> HistorySection? in
            guard let entries = grouped[key], !entries.isEmpty else {
                return nil
            }
            let sortedEntries = entries.sorted {
                (entry1: HistoryEntry, entry2: HistoryEntry) in
                entry1.lastVisited > entry2.lastVisited
            }
            return HistorySection(title: key, entries: sortedEntries)
        }
    }

    private func openInCurrentTab(_ url: URL) {
        if let currentTab = browserManager.tabManager.currentTab {
            currentTab.loadURL(url)
        } else {
            _ = browserManager.tabManager.createNewTab(url: url.absoluteString)
        }
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        browserManager.historyManager.deleteHistoryEntry(entry.id)
        historyEntries.removeAll { $0.id == entry.id }
        groupedHistoryEntries = groupHistoryEntries(historyEntries)
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText =
            "Are you sure you want to clear your browsing history? This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            browserManager.historyManager.clearHistory()
            historyEntries.removeAll()
            groupedHistoryEntries.removeAll()
        }
    }
}

struct HistoryRowView: View {
    let entry: HistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var isHovered: Bool = false
    @State private var isTrashIconHovered: Bool = false
    @State private var isArrowIconHovered: Bool = false
    @State private var favicon: SwiftUI.Image = Image(systemName: "globe")

    private var contrastText: Color {
        Garnish.contrastingShade(of: gradientColorManager.primaryColor, targetRatio: 4.5, blendStyle: .strong) ?? .white
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.clear)
                .frame(width: 16, height: 16)
                .overlay(
                    favicon
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(contrastText)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(contrastText.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)

                Text(entry.url.host ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(contrastText.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if isHovered {
                HStack(spacing: 2) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(contrastText.opacity(0.6))
                            .frame(width: 16, height: 16)
                    }
                    .padding(8)
                    .background(
                        isTrashIconHovered ? contrastText.opacity(0.1) : .clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove from history")
                    .transition(.scale.combined(with: .opacity))
                    .onHover { state in
                        isTrashIconHovered = state
                    }
                    // Open in a new tab
                    Button(action: onDelete) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(contrastText.opacity(0.6))
                            .frame(width: 16, height: 16)
                    }
                    .padding(8)
                    .background(
                        isArrowIconHovered ? contrastText.opacity(0.1) : .clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(PlainButtonStyle())
                    .help("Open in a new tab")
                    .transition(.scale.combined(with: .opacity))
                    .onHover { state in
                        isArrowIconHovered = state
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? contrastText.opacity(0.1) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovered
            }
        }
        .onTapGesture {
            onTap()
        }
        .onAppear {
            Task {
                await fetchFavicon()
            }
        }
        .contextMenu {
            Button("Open") { onTap() }
            Button("Open in New Tab") {
                onTap()
            }
            Divider()
            Button("Remove from History") { onDelete() }
        }
    }

    private func fetchFavicon() async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")

        guard entry.url.scheme == "http" || entry.url.scheme == "https",
              entry.url.host != nil
        else {
            await MainActor.run {
                self.favicon = defaultFavicon
            }
            return
        }

        let cacheKey = entry.url.host ?? entry.url.absoluteString
        if let cachedFavicon = Tab.getCachedFavicon(for: cacheKey) {
            await MainActor.run {
                self.favicon = cachedFavicon
            }
            return
        }

        do {
            let favicon = try await FaviconFinder(url: entry.url)
                .fetchFaviconURLs()
                .download()
                .largest()

            if let faviconImage = favicon.image {
                let nsImage = faviconImage.image
                let swiftUIImage = SwiftUI.Image(nsImage: nsImage)

                Tab.cacheFavicon(swiftUIImage, for: cacheKey)

                await MainActor.run {
                    self.favicon = swiftUIImage
                }
            } else {
                await MainActor.run {
                    self.favicon = defaultFavicon
                }
            }
        } catch {
            await MainActor.run {
                self.favicon = defaultFavicon
            }
        }
    }
}

struct FiltersSelectView: View {
    @Binding var selectedTimeRange: TimeRange
    @EnvironmentObject var gradientColorManager: GradientColorManager

    private var contrastText: Color {
        Garnish.contrastingShade(of: gradientColorManager.primaryColor, targetRatio: 4.5, blendStyle: .strong) ?? .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("When was the tab closed?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(contrastText.opacity(0.6))
                Spacer()
            }

            VStack(spacing: 8) {
                HStack {
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

                    Spacer()
                }
                HStack {
                    FiltersSelectButton(
                        text: "This month",
                        isActive: selectedTimeRange == .month
                    ) {
                        selectedTimeRange = .month
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct FiltersSelectButton: View {
    var text: String
    var isActive: Bool
    var action: () -> Void

    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var isHovering: Bool = false

    private var contrastText: Color {
        Garnish.contrastingShade(of: gradientColorManager.primaryColor, targetRatio: 4.5, blendStyle: .strong) ?? .white
    }

    var body: some View {
        Button {
            action()
        } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    isActive ? Color(hex: "1E1E1E") : contrastText.opacity(0.5)
                )
                .lineLimit(1)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    isActive
                        ? contrastText.opacity(0.6)
                        : isHovering
                        ? contrastText.opacity(0.08) : contrastText.opacity(0.05)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .animation(.easeInOut(duration: 0.1), value: isActive)
        .onHover { state in
            isHovering = state
        }
    }
}
