//
//  CacheManagementView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

struct CacheManagementView: View {
    @StateObject private var cacheManager = CacheManager()
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
            Form {
                summarySection
                filterSection

                if cacheManager.isLoading {
                    Section {
                        HStack(spacing: NookDesign.Spacing.md) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading cache data...")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Cached Data") {
                        switch viewMode {
                        case .domain:
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
                        case .list:
                            ForEach(filteredAndSortedCache) { cache in
                                CacheRowView(cache: cache, showsDomain: true) {
                                    selectedCache = cache
                                    showingCacheDetails = true
                                } onDelete: {
                                    Task {
                                        await cacheManager.clearSpecificCache(cache)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            actionBar
        }
        .frame(
            minWidth: NookDesign.Size.sheetLargeWidth,
            minHeight: NookDesign.Size.sheetLargeHeight
        )
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

    // MARK: - Summary

    private var summarySection: some View {
        let stats = cacheManager.getCacheStats()
        let faviconStats = cacheManager.getFaviconCacheStats()

        return Section("Cache Management") {
            LabeledContent("Cache entries") { Text("\(stats.total)") }
            LabeledContent("Total size") { Text(formatSize(stats.totalSize)) }
            LabeledContent("Stale entries") {
                Text("\(stats.staleCount)")
                    .foregroundStyle(stats.staleCount > 0 ? .orange : .secondary)
            }
            LabeledContent("Favicons cached") { Text("\(faviconStats.count)") }
        }
    }

    // MARK: - Filters

    private var filterSection: some View {
        Section("Filter") {
            LabeledContent("Search") {
                TextField("Search cache...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Show", selection: $selectedFilter) {
                ForEach(CacheFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }

            Picker("Sort by", selection: $selectedSort) {
                ForEach(CacheSortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Order", selection: $sortAscending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
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
            .fixedSize()

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
        }
        .padding(NookDesign.Spacing.xl)
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
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(group.displayDomain)
                    .font(NookDesign.Font.label)
                
                HStack {
                    Text("\(group.entryCount) entries")
                    Text("•")
                    Text(group.totalSizeDescription)
                    
                    if group.hasStaleCache {
                        Text("• Contains stale cache")
                            .foregroundStyle(.orange)
                    }
                }
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Cache efficiency indicator
            VStack(alignment: .trailing, spacing: NookDesign.Spacing.xxs) {
                Text("\(Int(group.cacheEfficiency * 100))% fresh")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(group.cacheEfficiency > 0.7 ? .green : .orange)
                
                ProgressView(value: group.cacheEfficiency)
                    .progressViewStyle(.linear)
                    .frame(width: NookDesign.Size.fieldNarrow)
            }
            
            Button("Clear All") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.vertical, NookDesign.Spacing.xs)
    }
}

struct CacheRowView: View {
    let cache: CacheInfo
    var showsDomain: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: cache.primaryCacheType.icon)
                .foregroundStyle(Color(cache.primaryCacheType.color))
            
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(showsDomain ? cache.displayDomain : cache.primaryCacheType.rawValue)
                
                HStack {
                    if showsDomain {
                        Text(cache.primaryCacheType.rawValue)
                        Text("•")
                    }
                    Text(cache.sizeDescription)
                    Text("•")
                    Text(cache.lastModifiedDescription)
                    
                    if cache.isStale {
                        Text("• Stale")
                            .foregroundStyle(.orange)
                    }
                }
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, NookDesign.Spacing.xxs)
    }
}
