//
//  HistoryView.swift
//  Pulse
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var historyEntries: [HistoryEntry] = []
    @State private var searchText: String = ""
    @State private var selectedTimeRange: TimeRange = .week
    @State private var isLoading: Bool = false
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
        
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
                HStack {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button(range.rawValue) {
                            selectedTimeRange = range
                            loadHistory()
                        }
                        .foregroundColor(selectedTimeRange == range ? .accentColor : .secondary)
                        .font(.system(size: 12, weight: selectedTimeRange == range ? .semibold : .regular))
                        .buttonStyle(PlainButtonStyle())
                        
                        if range != TimeRange.allCases.last {
                            Text("•")
                                .foregroundColor(AppColors.textTertiary)
                                .font(.system(size: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)
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
                        ForEach(historyEntries) { entry in
                            HistoryRowView(
                                entry: entry,
                                onTap: { openInCurrentTab(entry.url) },
                                onDelete: { deleteEntry(entry) }
                            )
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .onAppear {
            loadHistory()
        }
    }
    
    // MARK: - Actions
    
    private func loadHistory() {
        isLoading = true
        
        Task { @MainActor in
            let entries = browserManager.historyManager.getHistory(days: selectedTimeRange.days)
            
            withAnimation(.easeInOut(duration: 0.2)) {
                historyEntries = entries
                isLoading = false
            }
        }
    }
    
    private func searchHistory() {
        isLoading = true
        
        Task { @MainActor in
            let entries: [HistoryEntry]
            
            if searchText.isEmpty {
                entries = browserManager.historyManager.getHistory(days: selectedTimeRange.days)
            } else {
                entries = browserManager.historyManager.searchHistory(query: searchText)
            }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                historyEntries = entries
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

struct HistoryRowView: View {
    let entry: HistoryEntry
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Favicon placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 4) {
                    Text(entry.url.host ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if entry.visitCount > 1 {
                        Text("• \(entry.visitCount) visits")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                
                Text(entry.timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }
            
            Spacer()
            
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove from history")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovered
            }
        }
        .onTapGesture {
            onTap()
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
}
