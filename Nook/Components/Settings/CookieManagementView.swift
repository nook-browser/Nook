//
//  CookieManagementView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

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
            Form {
                summarySection
                filterSection

                if cookieManager.isLoading {
                    Section {
                        HStack(spacing: NookDesign.Spacing.md) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading cookies...")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Stored Cookies") {
                        switch viewMode {
                        case .domain:
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
                        case .list:
                            ForEach(filteredAndSortedCookies) { cookie in
                                CookieRowView(cookie: cookie, showsDomain: true) {
                                    selectedCookie = cookie
                                    showingCookieDetails = true
                                } onDelete: {
                                    Task {
                                        await cookieManager.deleteCookie(cookie)
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
                await cookieManager.loadCookies()
            }
        }
        .sheet(isPresented: $showingCookieDetails) {
            if let cookie = selectedCookie {
                CookieDetailsView(cookie: cookie, cookieManager: cookieManager)
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        let stats = cookieManager.getCookieStats()

        return Section("Cookie Management") {
            LabeledContent("Cookies") { Text("\(stats.total)") }
            LabeledContent("Session") { Text("\(stats.session)") }
            LabeledContent("Persistent") { Text("\(stats.persistent)") }
            LabeledContent("Total size") { Text(formatSize(stats.totalSize)) }
        }
    }

    // MARK: - Filters

    private var filterSection: some View {
        Section("Filter") {
            LabeledContent("Search") {
                TextField("Search cookies...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Show", selection: $selectedFilter) {
                ForEach(CookieFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }

            Picker("Sort by", selection: $selectedSort) {
                ForEach(CookieSortOption.allCases, id: \.self) { option in
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
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(group.displayDomain)
                    .font(NookDesign.Font.label)
                
                Text("\(group.cookieCount) cookies • \(group.totalSizeDescription)")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if group.hasExpiredCookies {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Has expired cookies")
            }
            
            Button("Delete All") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.vertical, NookDesign.Spacing.xs)
    }
}

struct CookieRowView: View {
    let cookie: CookieInfo
    var showsDomain: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(cookie.name)
                    .font(NookDesign.Font.body.monospaced())
                
                HStack {
                    if showsDomain {
                        Text(cookie.displayDomain)
                        Text("•")
                    }
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
                
                Button("Delete") {
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
