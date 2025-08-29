//
//  HistoryView.swift
//  Pulse
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import SwiftUI
import FaviconFinder

struct HistoryView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var historyEntries: [HistoryEntry] = []
    @State private var searchText: String = ""
    @State private var selectedTimeRange: TimeRange = .week
    @State private var isLoading: Bool = false
    @State private var currentPage: Int = 0
    @State private var hasMoreResults: Bool = true
    @State private var isLoadingMore: Bool = false
    
    private let pageSize: Int = 50
    private let maxResults: Int = 1000
    
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                
                Spacer()
                
                // Clear history button
                Button(action: clearHistory) {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.textSecondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear History")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 14))
                
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { _, newValue in
                        searchHistory()
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.clear)
            
            // Time range picker
            if searchText.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(TimeRange.allCases.enumerated()), id: \.element) { index, range in
                        TimeRangeButton(
                            range: range,
                            isSelected: selectedTimeRange == range,
                            onTap: {
                                selectedTimeRange = range
                                loadHistory()
                            }
                        )
                        .fixedSize()  // Prevent compression
                        
                        if range != TimeRange.allCases.last {
                            Text("•")
                                .foregroundColor(AppColors.textTertiary)
                                .font(.system(size: 8))
                                .fixedSize()  // Prevent bullet compression
                        }
                    }
                    Spacer(minLength: 0)  // Flexible spacing
                }
                .padding(.horizontal, 8)  // Reduced horizontal padding for narrow sidebar
                .padding(.bottom, 12)
            }
            
            Divider()
            
            // Content
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading history...")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if historyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textTertiary)
                    
                    Text(searchText.isEmpty ? "No history yet" : "No results found")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                    
                    if searchText.isEmpty {
                        Text("Visit some websites to see your history here")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyEntries.indices, id: \.self) { index in
                            let entry = historyEntries[index]
                            HistoryRowView(
                                entry: entry,
                                onTap: { openInCurrentTab(entry.url) },
                                onDelete: { deleteEntry(entry) }
                            )
                            .onAppear {
                                // Load more when approaching the end
                                if index == historyEntries.count - 10 && hasMoreResults && !isLoadingMore {
                                    loadMoreHistory()
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
        .background(Color.clear)
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear {
            loadHistory()
        }
    }
    
    // MARK: - Actions
    
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
                hasMoreResults = result.hasMore
                isLoading = false
            }
        }
    }
    
    private func loadMoreHistory() {
        guard hasMoreResults && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        Task { @MainActor in
            let result: (entries: [HistoryEntry], hasMore: Bool)
            
            if searchText.isEmpty {
                result = browserManager.historyManager.getHistory(
                    days: selectedTimeRange.days,
                    page: currentPage,
                    pageSize: pageSize
                )
            } else {
                result = browserManager.historyManager.searchHistory(
                    query: searchText,
                    page: currentPage,
                    pageSize: pageSize
                )
            }
            
            // Add delay for animation performance with large datasets
            let animationDelay = historyEntries.count > 100 ? 0.1 : 0.2
            
            withAnimation(.easeInOut(duration: animationDelay)) {
                historyEntries.append(contentsOf: result.entries)
                hasMoreResults = result.hasMore
                isLoadingMore = false
            }
        }
    }
    
    private func searchHistory() {
        isLoading = true
        currentPage = 0
        
        Task { @MainActor in
            let result: (entries: [HistoryEntry], hasMore: Bool)
            
            if searchText.isEmpty {
                result = browserManager.historyManager.getHistory(
                    days: selectedTimeRange.days,
                    page: currentPage,
                    pageSize: pageSize
                )
            } else {
                result = browserManager.historyManager.searchHistory(
                    query: searchText,
                    page: currentPage,
                    pageSize: pageSize
                )
            }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                historyEntries = result.entries
                hasMoreResults = result.hasMore
                isLoading = false
            }
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
    }
    
    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText = "Are you sure you want to clear your browsing history? This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            browserManager.historyManager.clearHistory()
            historyEntries.removeAll()
        }
    }
}

struct TimeRangeButton: View {
    let range: HistoryView.TimeRange
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(range.rawValue) {
            onTap()
        }
        .foregroundColor(isSelected ? .accentColor : (isHovered ? AppColors.textPrimary : .secondary))
        .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
        .lineLimit(1)
        .fixedSize()  // Ensure button never shrinks
        .padding(.horizontal, 6)  // Reduced padding for narrow widths
        .padding(.vertical, 4)
        .frame(minWidth: 24)  // Minimum width to ensure visibility
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered || isSelected ? Color.secondary.opacity(0.15) : Color.clear)
        )
        .buttonStyle(PlainButtonStyle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: HistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var favicon: SwiftUI.Image = Image(systemName: "globe")
    
    var body: some View {
        HStack(spacing: 8) {
            // Favicon
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 16, height: 16)
                .overlay(
                    favicon
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(AppColors.textSecondary)
                )
            
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                
                HStack(spacing: 3) {
                    Text(entry.url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                    
                    if entry.visitCount > 1 {
                        Text("• \(entry.visitCount)")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textTertiary)
                            .fixedSize()
                    }
                }
                
                Text(entry.timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize()
            }
            
            Spacer(minLength: 0)
            
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove from history")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                // This would need to be passed in as a parameter
                // For now, just open in current tab
                onTap()
            }
            Divider()
            Button("Remove from History") { onDelete() }
        }
    }
    
    private func fetchFavicon() async {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        
        // Skip favicon fetching for non-web schemes
        guard entry.url.scheme == "http" || entry.url.scheme == "https", entry.url.host != nil else {
            await MainActor.run {
                self.favicon = defaultFavicon
            }
            return
        }
        
        // Check cache first
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
                
                // Cache the favicon
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
