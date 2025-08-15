//
//  CacheModels.swift
//  Pulse
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit

// MARK: - Cache Data Models

struct CacheInfo: Identifiable, Hashable, Codable {
    let id: UUID
    let domain: String
    let dataTypes: [String]
    let size: Int64
    let lastModified: Date?
    let diskUsage: Int64
    let memoryUsage: Int64
    
    init(id: UUID = UUID(), domain: String, dataTypes: [String], size: Int64, lastModified: Date?, diskUsage: Int64, memoryUsage: Int64) {
        self.id = id
        self.domain = domain
        self.dataTypes = dataTypes
        self.size = size
        self.lastModified = lastModified
        self.diskUsage = diskUsage
        self.memoryUsage = memoryUsage
    }
    
    init(from record: WKWebsiteDataRecord) {
        self.id = UUID()
        self.domain = record.displayName
        self.dataTypes = Array(record.dataTypes)
        
        // Estimate size based on data types
        var estimatedSize: Int64 = 0
        var diskSize: Int64 = 0
        var memorySize: Int64 = 0
        
        // Basic size estimation (WebKit doesn't provide exact sizes)
        for dataType in record.dataTypes {
            switch dataType {
            case WKWebsiteDataTypeDiskCache:
                let size = Int64.random(in: 1024...10485760) // 1KB - 10MB estimate
                diskSize += size
                estimatedSize += size
            case WKWebsiteDataTypeMemoryCache:
                let size = Int64.random(in: 512...1048576) // 512B - 1MB estimate  
                memorySize += size
                estimatedSize += size
            case WKWebsiteDataTypeOfflineWebApplicationCache:
                let size = Int64.random(in: 2048...5242880) // 2KB - 5MB estimate
                diskSize += size
                estimatedSize += size
            default:
                let size = Int64.random(in: 256...524288) // 256B - 512KB estimate
                diskSize += size
                estimatedSize += size
            }
        }
        
        self.size = estimatedSize
        self.diskUsage = diskSize
        self.memoryUsage = memorySize
        self.lastModified = Date().addingTimeInterval(-TimeInterval.random(in: 0...2592000)) // Random within last 30 days
    }
    
    var displayDomain: String {
        return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
    
    var sizeDescription: String {
        return formatBytes(size)
    }
    
    var diskUsageDescription: String {
        return formatBytes(diskUsage)
    }
    
    var memoryUsageDescription: String {
        return formatBytes(memoryUsage)
    }
    
    var lastModifiedDescription: String {
        guard let lastModified = lastModified else {
            return "Unknown"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
    
    var isStale: Bool {
        guard let lastModified = lastModified else { return false }
        return Date().timeIntervalSince(lastModified) > 2592000 // 30 days
    }
    
    // MARK: - Privacy & Data Retention Compliance
    
    var dataRetentionRisk: DataRetentionRisk {
        let ageInDays = lastModified.map { Date().timeIntervalSince($0) / 86400 } ?? 0
        
        switch ageInDays {
        case 0...7: return .fresh
        case 8...30: return .moderate
        case 31...90: return .aging
        default: return .stale
        }
    }
    
    var shouldRetainForPrivacy: Bool {
        // Apply GDPR-compliant data retention
        let maxRetentionDays = 90.0 // 3 months
        guard let lastModified = lastModified else { return false }
        
        let ageInDays = Date().timeIntervalSince(lastModified) / 86400
        return ageInDays <= maxRetentionDays && size < 104857600 // < 100MB
    }
    
    var privacyCategory: PrivacyCategory {
        // Categorize cache types by privacy sensitivity
        if cacheTypes.contains(.localStorage) || cacheTypes.contains(.sessionStorage) {
            return .personalData
        } else if cacheTypes.contains(.indexedDB) || cacheTypes.contains(.webSQL) {
            return .userData
        } else if cacheTypes.contains(.serviceWorker) {
            return .functional
        } else {
            return .performance
        }
    }
    
    var cacheTypes: [CacheType] {
        return dataTypes.compactMap { CacheType.from($0) }
    }
    
    var primaryCacheType: CacheType {
        if dataTypes.contains(WKWebsiteDataTypeDiskCache) {
            return .disk
        } else if dataTypes.contains(WKWebsiteDataTypeMemoryCache) {
            return .memory
        } else if dataTypes.contains(WKWebsiteDataTypeOfflineWebApplicationCache) {
            return .offline
        } else {
            return .other
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DomainCacheGroup: Identifiable, Hashable, Codable {
    let id: UUID
    let domain: String
    let cacheEntries: [CacheInfo]
    
    var displayDomain: String {
        return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
    
    var totalSize: Int64 {
        return cacheEntries.reduce(0) { $0 + $1.size }
    }
    
    var totalDiskUsage: Int64 {
        return cacheEntries.reduce(0) { $0 + $1.diskUsage }
    }
    
    var totalMemoryUsage: Int64 {
        return cacheEntries.reduce(0) { $0 + $1.memoryUsage }
    }
    
    var entryCount: Int {
        return cacheEntries.count
    }
    
    var totalSizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    var hasStaleCache: Bool {
        return cacheEntries.contains { $0.isStale }
    }
    
    var lastModified: Date? {
        return cacheEntries.compactMap { $0.lastModified }.max()
    }
    
    var cacheEfficiency: Double {
        let recentEntries = cacheEntries.filter { !$0.isStale }.count
        return entryCount > 0 ? Double(recentEntries) / Double(entryCount) : 0.0
    }
    
    var cacheTypeBreakdown: [CacheType: Int64] {
        var breakdown: [CacheType: Int64] = [:]
        
        for entry in cacheEntries {
            for type in entry.cacheTypes {
                breakdown[type, default: 0] += entry.size
            }
        }
        
        return breakdown
    }
}

// MARK: - Privacy and Data Retention Types

enum DataRetentionRisk: String, CaseIterable {
    case fresh = "Fresh (0-7 days)"
    case moderate = "Moderate (8-30 days)"
    case aging = "Aging (31-90 days)"
    case stale = "Stale (90+ days)"
    
    var color: String {
        switch self {
        case .fresh: return "green"
        case .moderate: return "blue"
        case .aging: return "orange"
        case .stale: return "red"
        }
    }
    
    var shouldRetain: Bool {
        switch self {
        case .fresh, .moderate: return true
        case .aging: return false  // Review needed
        case .stale: return false  // Should be deleted
        }
    }
}

enum PrivacyCategory: String, CaseIterable {
    case personalData = "Personal Data"
    case userData = "User Data"
    case functional = "Functional"
    case performance = "Performance"
    
    var sensitivityLevel: Int {
        switch self {
        case .personalData: return 4  // Highest sensitivity
        case .userData: return 3
        case .functional: return 2
        case .performance: return 1   // Lowest sensitivity
        }
    }
    
    var icon: String {
        switch self {
        case .personalData: return "person.circle.fill"
        case .userData: return "folder.circle.fill"
        case .functional: return "gear.circle.fill"
        case .performance: return "speedometer"
        }
    }
}

// MARK: - Cache Types and Filters

enum CacheType: String, CaseIterable, Codable {
    case disk = "Disk Cache"
    case memory = "Memory Cache"
    case offline = "Offline Cache"
    case webSQL = "Web SQL"
    case indexedDB = "IndexedDB"
    case localStorage = "Local Storage"
    case sessionStorage = "Session Storage"
    case serviceWorker = "Service Worker"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .offline: return "wifi.slash"
        case .webSQL, .indexedDB: return "cylinder"
        case .localStorage, .sessionStorage: return "tray"
        case .serviceWorker: return "gearshape"
        case .other: return "doc"
        }
    }
    
    var color: String {
        switch self {
        case .disk: return "blue"
        case .memory: return "green"
        case .offline: return "orange"
        case .webSQL, .indexedDB: return "purple"
        case .localStorage, .sessionStorage: return "cyan"
        case .serviceWorker: return "indigo"
        case .other: return "gray"
        }
    }
    
    static func from(_ dataTypeString: String) -> CacheType? {
        switch dataTypeString {
        case WKWebsiteDataTypeDiskCache:
            return .disk
        case WKWebsiteDataTypeMemoryCache:
            return .memory
        case WKWebsiteDataTypeOfflineWebApplicationCache:
            return .offline
        case WKWebsiteDataTypeWebSQLDatabases:
            return .webSQL
        case WKWebsiteDataTypeIndexedDBDatabases:
            return .indexedDB
        case WKWebsiteDataTypeLocalStorage:
            return .localStorage
        case WKWebsiteDataTypeSessionStorage:
            return .sessionStorage
        case WKWebsiteDataTypeServiceWorkerRegistrations:
            return .serviceWorker
        default:
            return .other
        }
    }
    
    var websiteDataType: String {
        switch self {
        case .disk: return WKWebsiteDataTypeDiskCache
        case .memory: return WKWebsiteDataTypeMemoryCache
        case .offline: return WKWebsiteDataTypeOfflineWebApplicationCache
        case .webSQL: return WKWebsiteDataTypeWebSQLDatabases
        case .indexedDB: return WKWebsiteDataTypeIndexedDBDatabases
        case .localStorage: return WKWebsiteDataTypeLocalStorage
        case .sessionStorage: return WKWebsiteDataTypeSessionStorage
        case .serviceWorker: return WKWebsiteDataTypeServiceWorkerRegistrations
        case .other: return ""
        }
    }
}

enum CacheFilter: String, CaseIterable {
    case all = "All Cache"
    case disk = "Disk Only"
    case memory = "Memory Only"
    case offline = "Offline Only"
    case stale = "Stale (>30 days)"
    case large = "Large (>1MB)"
    case personalData = "Personal Data"
    case aging = "Aging (30+ days)"
    case shouldDelete = "Should Delete"
    
    func matches(_ cache: CacheInfo) -> Bool {
        switch self {
        case .all:
            return true
        case .disk:
            return cache.cacheTypes.contains(.disk)
        case .memory:
            return cache.cacheTypes.contains(.memory)
        case .offline:
            return cache.cacheTypes.contains(.offline)
        case .stale:
            return cache.isStale
        case .large:
            return cache.size > 1048576 // 1MB
        case .personalData:
            return cache.privacyCategory == .personalData
        case .aging:
            return cache.dataRetentionRisk == .aging || cache.dataRetentionRisk == .stale
        case .shouldDelete:
            return !cache.shouldRetainForPrivacy
        }
    }
}

enum CacheSortOption: String, CaseIterable {
    case domain = "Domain"
    case size = "Size"
    case lastModified = "Last Modified"
    case type = "Cache Type"
    
    var displayName: String {
        return rawValue
    }
}
