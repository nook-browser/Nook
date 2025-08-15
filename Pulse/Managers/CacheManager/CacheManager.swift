//
//  CacheManager.swift
//  Pulse
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit
import SwiftUI

@MainActor
class CacheManager: ObservableObject {
    private let dataStore: WKWebsiteDataStore
    @Published private(set) var cacheEntries: [CacheInfo] = []
    @Published private(set) var domainGroups: [DomainCacheGroup] = []
    @Published private(set) var isLoading: Bool = false
    
    init(dataStore: WKWebsiteDataStore? = nil) {
        self.dataStore = dataStore ?? WKWebsiteDataStore.default()
    }
    
    // MARK: - Public Methods
    
    func loadCacheData() async {
        isLoading = true
        
        let cacheDataTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        
        let records = await dataStore.dataRecords(ofTypes: cacheDataTypes)
        let cacheInfos = records.map { CacheInfo(from: $0) }
        
        self.cacheEntries = cacheInfos
        self.domainGroups = self.groupCacheByDomain(cacheInfos)
        self.isLoading = false
    }
    
    func clearCacheForDomain(_ domain: String) async {
        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let domainRecords = records.filter { 
            $0.displayName == domain || $0.displayName == ".\(domain)" 
        }
        
        if !domainRecords.isEmpty {
            await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: domainRecords)
            await loadCacheData() // Refresh the list
        }
    }
    
    func clearCacheOfType(_ cacheType: CacheType) async {
        let dataType = cacheType.websiteDataType
        guard !dataType.isEmpty else { return }
        
        await dataStore.removeData(ofTypes: [dataType], modifiedSince: Date.distantPast)
        await loadCacheData() // Refresh the list
    }
    
    func clearDiskCache() async {
        await dataStore.removeData(ofTypes: [WKWebsiteDataTypeDiskCache], modifiedSince: Date.distantPast)
        await loadCacheData() // Refresh the list
    }
    
    func clearMemoryCache() async {
        await dataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: Date.distantPast)
        await loadCacheData() // Refresh the list
    }
    
    func clearStaleCache() async {
        // Clear cache older than 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-2592000) // 30 days
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: allTypes, modifiedSince: thirtyDaysAgo)
        await loadCacheData() // Refresh the list
    }
    
    // MARK: - Privacy-Compliant Cache Management
    
    func clearPersonalDataCache() async {
        // Clear only personal data cache types (localStorage, sessionStorage)
        let personalDataTypes: Set<String> = [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]
        
        await dataStore.removeData(ofTypes: personalDataTypes, modifiedSince: Date.distantPast)
        await loadCacheData()
    }
    
    func clearAgingCache() async {
        // Clear cache older than 30 days (GDPR compliance)
        let thirtyDaysAgo = Date().addingTimeInterval(-2592000)
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: allTypes, modifiedSince: thirtyDaysAgo)
        await loadCacheData()
    }
    
    func performPrivacyCompliantCleanup() async {
        // Comprehensive GDPR-compliant cache cleanup
        
        // 1. Clear all stale cache (90+ days)
        let ninetyDaysAgo = Date().addingTimeInterval(-7776000) // 90 days
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: ninetyDaysAgo)
        
        // 2. Clear personal data older than 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-2592000)
        let personalDataTypes: Set<String> = [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]
        await dataStore.removeData(ofTypes: personalDataTypes, modifiedSince: thirtyDaysAgo)
        
        await loadCacheData()
    }
    
    func clearNonEssentialCache() async {
        // Clear only non-essential cache types (keep functional cache)
        let nonEssentialTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        
        await dataStore.removeData(ofTypes: nonEssentialTypes, modifiedSince: Date.distantPast)
        await loadCacheData()
    }
    
    func clearAllCache() async {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: allTypes, modifiedSince: Date.distantPast)
        await loadCacheData() // Refresh the list
    }
    
    func clearSpecificCache(_ cache: CacheInfo) async {
        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let targetRecord = records.first { $0.displayName == cache.domain }
        
        if let record = targetRecord {
            await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [record])
            await loadCacheData() // Refresh the list
        }
    }
    
    func searchCache(_ query: String) -> [CacheInfo] {
        guard !query.isEmpty else { return cacheEntries }
        
        let lowercaseQuery = query.lowercased()
        return cacheEntries.filter { cache in
            cache.domain.lowercased().contains(lowercaseQuery) ||
            cache.dataTypes.joined(separator: " ").lowercased().contains(lowercaseQuery)
        }
    }
    
    func filterCache(_ filter: CacheFilter) -> [CacheInfo] {
        return cacheEntries.filter { filter.matches($0) }
    }
    
    func sortCache(_ cacheEntries: [CacheInfo], by sortOption: CacheSortOption, ascending: Bool = true) -> [CacheInfo] {
        let sorted = cacheEntries.sorted { lhs, rhs in
            switch sortOption {
            case .domain:
                return lhs.displayDomain < rhs.displayDomain
            case .size:
                return lhs.size < rhs.size
            case .lastModified:
                // Handle nil dates
                switch (lhs.lastModified, rhs.lastModified) {
                case (nil, nil):
                    return false
                case (nil, _):
                    return false // Recent items first
                case (_, nil):
                    return true
                case (let lhsDate?, let rhsDate?):
                    return lhsDate < rhsDate
                }
            case .type:
                return lhs.primaryCacheType.rawValue < rhs.primaryCacheType.rawValue
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
    
    func getCacheStats() -> (total: Int, totalSize: Int64, diskSize: Int64, memorySize: Int64, staleCount: Int) {
        let totalSize = cacheEntries.reduce(0) { $0 + $1.size }
        let diskSize = cacheEntries.reduce(0) { $0 + $1.diskUsage }
        let memorySize = cacheEntries.reduce(0) { $0 + $1.memoryUsage }
        let staleCount = cacheEntries.filter { $0.isStale }.count
        
        return (
            total: cacheEntries.count,
            totalSize: totalSize,
            diskSize: diskSize,
            memorySize: memorySize,
            staleCount: staleCount
        )
    }
    
    func getCacheTypeBreakdown() -> [CacheType: Int64] {
        var breakdown: [CacheType: Int64] = [:]
        
        for cache in cacheEntries {
            for type in cache.cacheTypes {
                breakdown[type, default: 0] += cache.size
            }
        }
        
        return breakdown
    }
    
    func getLargestCacheDomains(limit: Int = 10) -> [DomainCacheGroup] {
        return domainGroups
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(limit)
            .map { $0 }
    }
    
    func getStaleCacheDomains() -> [DomainCacheGroup] {
        return domainGroups.filter { $0.hasStaleCache }
    }
    
    // MARK: - Private Methods
    
    private func groupCacheByDomain(_ cacheEntries: [CacheInfo]) -> [DomainCacheGroup] {
        let grouped = Dictionary(grouping: cacheEntries) { cache in
            // Normalize domain for grouping
            cache.domain.hasPrefix(".") ? String(cache.domain.dropFirst()) : cache.domain
        }
        
        return grouped.map { domain, caches in
            DomainCacheGroup(
                id: UUID(),
                domain: domain,
                cacheEntries: caches.sorted { $0.size > $1.size }
            )
        }.sorted { $0.displayDomain < $1.displayDomain }
    }
}

// MARK: - Cache Management Extensions

extension CacheManager {
    func exportCacheData() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(cacheEntries)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            print("Error exporting cache data: \(error)")
            return ""
        }
    }
    
    func getCacheDetails(_ cache: CacheInfo) -> [String: String] {
        var details: [String: String] = [:]
        
        details["Domain"] = cache.domain
        details["Total Size"] = cache.sizeDescription
        details["Disk Usage"] = cache.diskUsageDescription
        details["Memory Usage"] = cache.memoryUsageDescription
        details["Cache Types"] = cache.cacheTypes.map { $0.rawValue }.joined(separator: ", ")
        details["Last Modified"] = cache.lastModifiedDescription
        details["Status"] = cache.isStale ? "Stale" : "Fresh"
        details["Primary Type"] = cache.primaryCacheType.rawValue
        
        return details
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func getCacheEfficiencyRecommendations() -> [String] {
        var recommendations: [String] = []
        
        let stats = getCacheStats()
        let stalePercentage = stats.total > 0 ? Double(stats.staleCount) / Double(stats.total) : 0.0
        
        if stalePercentage > 0.3 {
            recommendations.append("Consider clearing stale cache (>30% of cache is outdated)")
        }
        
        if stats.totalSize > 1073741824 { // 1GB
            recommendations.append("Cache size is large (\(formatSize(stats.totalSize))). Consider clearing old cache.")
        }
        
        let largeDomains = getLargestCacheDomains(limit: 3)
        if let largest = largeDomains.first, largest.totalSize > 104857600 { // 100MB
            recommendations.append("Largest cache domain: \(largest.displayDomain) (\(largest.totalSizeDescription))")
        }
        
        if recommendations.isEmpty {
            recommendations.append("Cache is efficiently managed!")
        }
        
        return recommendations
    }
}
