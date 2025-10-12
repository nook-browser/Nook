//
//  CacheManagementView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import WebKit

struct CacheManagementView: View {
    @State private var cacheManager = CacheManager()
    @State private var searchText: String = ""
    @State private var selectedFilter: CacheFilter = .all
    @State private var selectedSort: CacheSortOption = .domain
    @State private var sortAscending: Bool = true
    @State private var selectedCache: CacheInfo?
    @State private var showingCacheDetails: Bool = false
    @State private var viewMode: ViewMode = .domain
    @Environment(\.dismiss) private var dismiss
    
    enum ViewMode: String, CaseIterable {
        case domain = "By Domain"
        case list = "All Cache"
        
        var icon: String {
            switch self {
            case .domain: return "folder"
            case .list: return "list.bullet"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats and controls
            headerView
            
            Divider()
            
            // Search and filter controls
            controlsView
            
            Divider()
            
            // Main content
            if cacheManager.isLoading {
                loadingView
            } else {
                contentView
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            Task {
                await cacheManager.loadCacheData()
            }
        }
        .sheet(isPresented: $showingCacheDetails) {
            if let cache = selectedCache {
                CacheDetailsView(cache: cache, cacheManager: cacheManager)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cache Management")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                let stats = cacheManager.getCacheStats()
                let faviconStats = cacheManager.getFaviconCacheStats()
                Text("\(stats.total) cache entries • \(formatSize(stats.totalSize)) total • \(stats.staleCount) stale • \(faviconStats.count) favicons cached")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Refresh") {
                    Task {
                        await cacheManager.loadCacheData()
                    }
                }
                .buttonStyle(.bordered)
                
                Menu("Clear Cache") {
                    Button("Clear Stale Cache") {
                        Task {
                            await cacheManager.clearStaleCache()
                        }
                    }
                    
                    Button("Clear Disk Cache") {
                        Task {
                            await cacheManager.clearDiskCache()
                        }
                    }
                    
                    Button("Clear Memory Cache") {
                        Task {
                            await cacheManager.clearMemoryCache()
                        }
                    }
                    
                    Button("Clear Favicon Cache") {
                        Task {
                            cacheManager.clearFaviconCache()
                        }
                    }
                    
                    Divider()
                    
                    Button("Clear All Cache", role: .destructive) {
                        Task {
                            await cacheManager.clearAllCache()
                        }
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
            }
        }
        .padding()
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search cache...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 300)
            
            Spacer()
            
            // View mode toggle
            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            // Filter
            Picker("Filter", selection: $selectedFilter) {
                ForEach(CacheFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            
            // Sort
            HStack(spacing: 4) {
                Picker("Sort", selection: $selectedSort) {
                    ForEach(CacheSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Button(action: { sortAscending.toggle() }) {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading cache data...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .domain:
            domainView
        case .list:
            listView
        }
    }
    
    // MARK: - Domain View
    
    private var domainView: some View {
        List {
            ForEach(filteredDomainGroups) { group in
                DisclosureGroup {
                    ForEach(filteredCacheForGroup(group)) { cache in
                        CacheRowView(cache: cache) {
                            selectedCache = cache
                            showingCacheDetails = true
                        } onDelete: {
                            Task {
                                await cacheManager.clearSpecificCache(cache)
                            }
                        }
                    }
                } label: {
                    DomainCacheRowView(group: group) {
                        Task {
                            await cacheManager.clearCacheForDomain(group.domain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - List View
    
    private var listView: some View {
        Table(filteredAndSortedCache) {
            TableColumn("Domain") { cache in
                HStack {
                    Image(systemName: cache.primaryCacheType.icon)
                        .foregroundColor(Color(cache.primaryCacheType.color))
                    Text(cache.displayDomain)
                    Spacer()
                }
            }
            .width(min: 120, ideal: 200, max: 300)
            
            TableColumn("Type") { cache in
                Text(cache.primaryCacheType.rawValue)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("Size") { cache in
                Text(cache.sizeDescription)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .width(min: 60, ideal: 80)
            
            TableColumn("Last Modified") { cache in
                Text(cache.lastModifiedDescription)
                    .foregroundColor(cache.isStale ? .orange : .secondary)
                    .font(.caption)
            }
            .width(min: 100, ideal: 150)
            
            TableColumn("Status") { cache in
                HStack {
                    Circle()
                        .fill(cache.isStale ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(cache.isStale ? "Stale" : "Fresh")
                        .font(.caption)
                        .foregroundColor(cache.isStale ? .orange : .green)
                }
            }
            .width(60)
            
            TableColumn("Actions") { cache in
                HStack {
                    Button("Details") {
                        selectedCache = cache
                        showingCacheDetails = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button("Clear") {
                        Task {
                            await cacheManager.clearSpecificCache(cache)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
            }
            .width(100)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
    }
    
    // MARK: - Computed Properties
    
    private var filteredDomainGroups: [DomainCacheGroup] {
        let searchFiltered = searchText.isEmpty ? cacheManager.domainGroups :
            cacheManager.domainGroups.filter { group in
                group.displayDomain.localizedCaseInsensitiveContains(searchText) ||
                group.cacheEntries.contains { cache in
                    cache.domain.localizedCaseInsensitiveContains(searchText)
                }
            }
        
        return searchFiltered
    }
    
    private func filteredCacheForGroup(_ group: DomainCacheGroup) -> [CacheInfo] {
        let filtered = group.cacheEntries.filter { selectedFilter.matches($0) }
        return cacheManager.sortCache(filtered, by: selectedSort, ascending: sortAscending)
    }
    
    private var filteredAndSortedCache: [CacheInfo] {
        let searchFiltered = searchText.isEmpty ? cacheManager.cacheEntries : cacheManager.searchCache(searchText)
        let filtered = cacheManager.filterCache(selectedFilter).filter { cache in
            searchFiltered.contains { $0.id == cache.id }
        }
        return cacheManager.sortCache(filtered, by: selectedSort, ascending: sortAscending)
    }
    
    // MARK: - Helper Methods
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

struct DomainCacheRowView: View {
    let group: DomainCacheGroup
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "internaldrive")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayDomain)
                    .font(.headline)
                
                HStack {
                    Text("\(group.entryCount) entries")
                    Text("•")
                    Text(group.totalSizeDescription)
                    
                    if group.hasStaleCache {
                        Text("• Contains stale cache")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Cache efficiency indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(group.cacheEfficiency * 100))% fresh")
                    .font(.caption)
                    .foregroundColor(group.cacheEfficiency > 0.7 ? .green : .orange)
                
                ProgressView(value: group.cacheEfficiency)
                    .progressViewStyle(.linear)
                    .frame(width: 60)
            }
            
            Button("Clear All") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct CacheRowView: View {
    let cache: CacheInfo
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: cache.primaryCacheType.icon)
                .foregroundColor(Color(cache.primaryCacheType.color))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(cache.primaryCacheType.rawValue)
                    .font(.system(.body, design: .default))
                
                HStack {
                    Text(cache.sizeDescription)
                    Text("•")
                    Text(cache.lastModifiedDescription)
                    
                    if cache.isStale {
                        Text("• Stale")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Button("Details") {
                    onTap()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                
                Button("Clear") {
                    onDelete()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
