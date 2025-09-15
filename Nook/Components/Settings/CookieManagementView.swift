//
//  CookieManagementView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import WebKit

struct CookieManagementView: View {
    @StateObject private var cookieManager = CookieManager()
    @State private var searchText: String = ""
    @State private var selectedFilter: CookieFilter = .all
    @State private var selectedSort: CookieSortOption = .domain
    @State private var sortAscending: Bool = true
    @State private var selectedCookie: CookieInfo?
    @State private var showingCookieDetails: Bool = false
    @State private var viewMode: ViewMode = .domain
    @Environment(\.dismiss) private var dismiss
    
    enum ViewMode: String, CaseIterable {
        case domain = "By Domain"
        case list = "All Cookies"
        
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
            if cookieManager.isLoading {
                loadingView
            } else {
                contentView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            Task {
                await cookieManager.loadCookies()
            }
        }
        .sheet(isPresented: $showingCookieDetails) {
            if let cookie = selectedCookie {
                CookieDetailsView(cookie: cookie, cookieManager: cookieManager)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookie Management")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                let stats = cookieManager.getCookieStats()
                Text("\(stats.total) cookies • \(stats.session) session • \(stats.persistent) persistent • \(formatSize(stats.totalSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Refresh") {
                    Task {
                        await cookieManager.loadCookies()
                    }
                }
                .buttonStyle(.bordered)
                
                Menu("Clear Cookies") {
                    Button("Clear Expired") {
                        Task {
                            await cookieManager.deleteExpiredCookies()
                        }
                    }
                    
                    Divider()
                    
                    Button("Clear All", role: .destructive) {
                        Task {
                            await cookieManager.deleteAllCookies()
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
                TextField("Search cookies...", text: $searchText)
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
                ForEach(CookieFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            
            // Sort
            HStack(spacing: 4) {
                Picker("Sort", selection: $selectedSort) {
                    ForEach(CookieSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
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
            Text("Loading cookies...")
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
                    ForEach(filteredCookiesForGroup(group)) { cookie in
                        CookieRowView(cookie: cookie) {
                            selectedCookie = cookie
                            showingCookieDetails = true
                        } onDelete: {
                            Task {
                                await cookieManager.deleteCookie(cookie)
                            }
                        }
                    }
                } label: {
                    DomainRowView(group: group) {
                        Task {
                            await cookieManager.deleteCookiesForDomain(group.domain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - List View
    
    private var listView: some View {
        Table(filteredAndSortedCookies) {
            TableColumn("Name") { cookie in
                HStack {
                    Text(cookie.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                }
            }
            .width(min: 120, ideal: 180, max: 250)
            
            TableColumn("Domain") { cookie in
                Text(cookie.displayDomain)
                    .foregroundColor(.secondary)
            }
            .width(min: 100, ideal: 150, max: 200)
            
            TableColumn("Size") { cookie in
                Text(cookie.sizeDescription)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .width(60)
            
            TableColumn("Expires") { cookie in
                Text(cookie.expirationStatus)
                    .foregroundColor(cookie.isSessionCookie ? .orange : .secondary)
                    .font(.caption)
            }
            .width(min: 80, ideal: 120)
            
            TableColumn("Secure") { cookie in
                Image(systemName: cookie.isSecure ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(cookie.isSecure ? .green : .red)
            }
            .width(50)
            
            TableColumn("Actions") { cookie in
                HStack {
                    Button("Details") {
                        selectedCookie = cookie
                        showingCookieDetails = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button("Delete") {
                        Task {
                            await cookieManager.deleteCookie(cookie)
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
    
    private var filteredDomainGroups: [DomainCookieGroup] {
        let searchFiltered = searchText.isEmpty ? cookieManager.domainGroups : 
            cookieManager.domainGroups.filter { group in
                group.displayDomain.localizedCaseInsensitiveContains(searchText) ||
                group.cookies.contains { cookie in
                    cookie.name.localizedCaseInsensitiveContains(searchText)
                }
            }
        
        return searchFiltered
    }
    
    private func filteredCookiesForGroup(_ group: DomainCookieGroup) -> [CookieInfo] {
        let filtered = group.cookies.filter { selectedFilter.matches($0) }
        return cookieManager.sortCookies(filtered, by: selectedSort, ascending: sortAscending)
    }
    
    private var filteredAndSortedCookies: [CookieInfo] {
        let searchFiltered = searchText.isEmpty ? cookieManager.cookies : cookieManager.searchCookies(searchText)
        let filtered = cookieManager.filterCookies(selectedFilter).filter { cookie in
            searchFiltered.contains { $0.id == cookie.id }
        }
        return cookieManager.sortCookies(filtered, by: selectedSort, ascending: sortAscending)
    }
    
    // MARK: - Helper Methods
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Supporting Views

struct DomainRowView: View {
    let group: DomainCookieGroup
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayDomain)
                    .font(.headline)
                
                Text("\(group.cookieCount) cookies • \(group.totalSizeDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if group.hasExpiredCookies {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("Has expired cookies")
            }
            
            Button("Delete All") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct CookieRowView: View {
    let cookie: CookieInfo
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cookie.name)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    Text(cookie.sizeDescription)
                    Text("•")
                    Text(cookie.expirationStatus)
                    
                    if cookie.isSecure {
                        Text("• Secure")
                    }
                    
                    if cookie.isHTTPOnly {
                        Text("• HTTP Only")
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
                
                Button("Delete") {
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
