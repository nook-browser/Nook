// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PrivacySettingsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import WebKit

import NookSettings
import NookWeb

struct PrivacySettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @StateObject private var cookieManager = CookieManager()
    @StateObject private var cacheManager = CacheManager()
    @State private var showingCookieManager = false
    @State private var showingCacheManager = false
    @State private var isClearing = false

    var body: some View {
        @Bindable var settings = nookSettings

        Form {
            Section("Cookie Management") {
                cookieStatsView

                HStack {
                    Button("Manage Cookies") {
                        showingCookieManager = true
                    }
                    .buttonStyle(.bordered)

                    Menu("Clear Data") {
                        Button("Clear Expired Cookies") {
                            clearExpiredCookies()
                        }
                        Button("Clear Third-Party Cookies") {
                            clearThirdPartyCookies()
                        }
                        Button("Clear High-Risk Cookies") {
                            clearHighRiskCookies()
                        }
                        Divider()
                        Button("Clear All Cookies") {
                            clearAllCookies()
                        }
                        Button("Privacy Cleanup") {
                            performCookiePrivacyCleanup()
                        }
                        Divider()
                        Button("Clear All Website Data", role: .destructive) {
                            clearAllWebsiteData()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isClearing)

                    if isClearing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Cache Management") {
                cacheStatsView

                HStack {
                    Button("Manage Cache") {
                        showingCacheManager = true
                    }
                    .buttonStyle(.bordered)

                    Menu("Clear Cache") {
                        Button("Clear Stale Cache") {
                            clearStaleCache()
                        }
                        Button("Clear Personal Data Cache") {
                            clearPersonalDataCache()
                        }
                        Button("Clear Disk Cache") {
                            clearDiskCache()
                        }
                        Button("Clear Memory Cache") {
                            clearMemoryCache()
                        }
                        Divider()
                        Button("Privacy Cleanup") {
                            performCachePrivacyCleanup()
                        }
                        Divider()
                        Button("Clear All Cache", role: .destructive) {
                            clearAllCache()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isClearing)

                    if isClearing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Privacy Controls") {
                Toggle("Block Cross-Site Tracking", isOn: $settings.blockCrossSiteTracking)
                    .onChange(of: nookSettings.blockCrossSiteTracking) { _, enabled in
                        browserManager.contentBlockerManager.setEnabled(enabled)
                    }
            }

            Section("Website Data") {
                Button("Clear Browsing History") {
                    clearBrowsingHistory()
                }
                Button("Clear Cache") {
                    clearCache()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                await cookieManager.loadCookies()
                await cacheManager.loadCacheData()
            }
        }
        .sheet(isPresented: $showingCookieManager) {
            CookieManagementView()
        }
        .sheet(isPresented: $showingCacheManager) {
            CacheManagementView()
        }
    }
    
    // MARK: - Cache Stats View
    
    @ViewBuilder
    private var cacheStatsView: some View {
        let stats = cacheManager.getCacheStats()

        LabeledContent {
            Text("\(stats.total)")
                .foregroundStyle(.secondary)
        } label: {
            Label("Stored Cache", systemImage: "internaldrive")
        }

        if stats.total > 0 {
            LabeledContent("Disk") { Text(formatSize(stats.diskSize)) }
            LabeledContent("Memory") { Text(formatSize(stats.memorySize)) }
            if stats.staleCount > 0 {
                LabeledContent("Stale") {
                    Text("\(stats.staleCount)")
                        .foregroundStyle(.orange)
                }
            }
            LabeledContent("Total size") { Text(formatSize(stats.totalSize)) }
        }
    }

    // MARK: - Cookie Stats View
    
    @ViewBuilder
    private var cookieStatsView: some View {
        let stats = cookieManager.getCookieStats()

        LabeledContent {
            Text("\(stats.total)")
                .foregroundStyle(.secondary)
        } label: {
            Label("Stored Cookies", systemImage: "doc.on.doc")
        }

        if stats.total > 0 {
            LabeledContent("Session") { Text("\(stats.session)") }
            LabeledContent("Persistent") { Text("\(stats.persistent)") }
            if stats.expired > 0 {
                LabeledContent("Expired") {
                    Text("\(stats.expired)")
                        .foregroundStyle(.orange)
                }
            }
            LabeledContent("Total size") { Text(formatSize(stats.totalSize)) }
        }
    }

    private func clearExpiredCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteExpiredCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteAllCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllWebsiteData() {
        isClearing = true
        Task {
            await removeWebsiteData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            await cookieManager.loadCookies()
            await cacheManager.loadCacheData()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearBrowsingHistory() {
        browserManager.historyManager.clearHistory()
    }
    
    private func clearCache() {
        Task {
            await removeWebsiteData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
        }
    }

    /// Tabs use one store per space; Peek and the base config have used the default.
    @MainActor
    private func removeWebsiteData(ofTypes dataTypes: Set<String>) async {
        let tabs = browserManager.tabs
        let dataStores: [WKWebsiteDataStore] = tabs.orderedSpaces.compactMap { tabs.profile(forSpace: $0.id)?.dataStore }
            + [WKWebsiteDataStore.default()]
        for dataStore in dataStores {
            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
        }
    }
    
        
    // MARK: - Helper Methods
    
    // MARK: - Cache Action Methods
    
    private func clearStaleCache() {
        isClearing = true
        Task {
            await cacheManager.clearStaleCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearDiskCache() {
        isClearing = true
        Task {
            await cacheManager.clearDiskCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearMemoryCache() {
        isClearing = true
        Task {
            await cacheManager.clearMemoryCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCache() {
        isClearing = true
        Task {
            await cacheManager.clearAllCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    // MARK: - Privacy-Compliant Actions
    
    private func clearThirdPartyCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteThirdPartyCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearHighRiskCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteHighRiskCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCookiePrivacyCleanup() {
        isClearing = true
        Task {
            await cookieManager.performPrivacyCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearPersonalDataCache() {
        isClearing = true
        Task {
            await cacheManager.clearPersonalDataCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCachePrivacyCleanup() {
        isClearing = true
        Task {
            await cacheManager.performPrivacyCompliantCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    PrivacySettingsView()
        .environmentObject(BrowserManager(settings: NookSettingsService(), windowRegistry: WindowRegistry()))
}
