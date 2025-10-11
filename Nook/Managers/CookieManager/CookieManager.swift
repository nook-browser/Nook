//
//  CookieManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit
import SwiftUI
import Observation

@MainActor
@Observable
class CookieManager {
    // Active data store for cookie operations. Switchable per profile.
    private var dataStore: WKWebsiteDataStore
    // Optional profile context for diagnostics and profiling
    var currentProfileId: UUID?
    private(set) var cookies: [CookieInfo] = []
    private(set) var domainGroups: [DomainCookieGroup] = []
    private(set) var isLoading: Bool = false
    
    init(dataStore: WKWebsiteDataStore? = nil) {
        self.dataStore = dataStore ?? WKWebsiteDataStore.default()
    }

    // MARK: - Profile Switching
    /// Switch the underlying data store to operate within a different profile boundary.
    /// Clears in-memory state and optionally reloads cookies from the new store.
    func switchDataStore(_ newDataStore: WKWebsiteDataStore, profileId: UUID? = nil, eagerLoad: Bool = true) {
        self.dataStore = newDataStore
        self.currentProfileId = profileId
        self.cookies = []
        self.domainGroups = []
        print("🔁 [CookieManager] Switched data store -> profile: \(profileId?.uuidString ?? "nil"), persistent: \(newDataStore.isPersistent)")
        if eagerLoad {
            Task { await self.loadCookies() }
        }
    }
    
    // MARK: - Public Methods
    
    func loadCookies() async {
        isLoading = true
        
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let cookieInfos = httpCookies.map { CookieInfo(from: $0) }
        
        self.cookies = cookieInfos
        self.domainGroups = self.groupCookiesByDomain(cookieInfos)
        self.isLoading = false
    }
    
    func deleteCookie(_ cookie: CookieInfo) async {
        // Find the original HTTPCookie
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        
        if let httpCookie = httpCookies.first(where: { 
            $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path 
        }) {
            await dataStore.httpCookieStore.deleteCookieAsync(httpCookie)
        }
        await loadCookies() // Refresh the list
    }
    
    func deleteCookiesForDomain(_ domain: String) async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let domainCookies = httpCookies.filter { $0.domain == domain || $0.domain == ".\(domain)" }
        
        for cookie in domainCookies {
            await dataStore.httpCookieStore.deleteCookieAsync(cookie)
        }
        
        await loadCookies() // Refresh the list
    }
    
    func deleteAllCookies() async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        
        for cookie in httpCookies {
            await dataStore.httpCookieStore.deleteCookieAsync(cookie)
        }
        
        await loadCookies() // Refresh the list
    }
    
    func deleteExpiredCookies() async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let expiredCookies = httpCookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return false }
            return expiresDate < Date()
        }
        
        for cookie in expiredCookies {
            await dataStore.httpCookieStore.deleteCookieAsync(cookie)
        }
        
        await loadCookies() // Refresh the list
    }
    
    // MARK: - Privacy-Compliant Cookie Management
    
    func deleteHighRiskCookies() async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let cookieInfos = httpCookies.map { CookieInfo(from: $0) }
        let highRiskCookies = cookieInfos.filter { $0.privacyRisk == .high }
        
        for cookieInfo in highRiskCookies {
            if let httpCookie = httpCookies.first(where: { 
                $0.name == cookieInfo.name && $0.domain == cookieInfo.domain && $0.path == cookieInfo.path 
            }) {
                await dataStore.httpCookieStore.deleteCookieAsync(httpCookie)
            }
        }
        
        await loadCookies()
    }
    
    func deleteNonCompliantCookies() async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let cookieInfos = httpCookies.map { CookieInfo(from: $0) }
        let nonCompliantCookies = cookieInfos.filter { !$0.complianceIssues.isEmpty }
        
        for cookieInfo in nonCompliantCookies {
            if let httpCookie = httpCookies.first(where: { 
                $0.name == cookieInfo.name && $0.domain == cookieInfo.domain && $0.path == cookieInfo.path 
            }) {
                await dataStore.httpCookieStore.deleteCookieAsync(httpCookie)
            }
        }
        
        await loadCookies()
    }
    
    func deleteThirdPartyCookies() async {
        let httpCookies = await dataStore.httpCookieStore.allCookiesAsync()
        let thirdPartyCookies = httpCookies.filter { $0.domain.hasPrefix(".") }
        
        for cookie in thirdPartyCookies {
            await dataStore.httpCookieStore.deleteCookieAsync(cookie)
        }
        
        await loadCookies()
    }
    
    func performPrivacyCleanup() async {
        // Comprehensive privacy-compliant cleanup
        await deleteExpiredCookies()
        await deleteHighRiskCookies()
        // Heuristic removal based on expiresDate has been removed to avoid deleting valid cookies.
        // If creation/last-access metadata becomes available in future, revisit retention logic.
        await loadCookies()
    }
    
    func searchCookies(_ query: String) -> [CookieInfo] {
        guard !query.isEmpty else { return cookies }
        
        let lowercaseQuery = query.lowercased()
        return cookies.filter { cookie in
            cookie.name.lowercased().contains(lowercaseQuery) ||
            cookie.domain.lowercased().contains(lowercaseQuery) ||
            cookie.value.lowercased().contains(lowercaseQuery)
        }
    }
    
    func filterCookies(_ filter: CookieFilter) -> [CookieInfo] {
        return cookies.filter { filter.matches($0) }
    }
    
    func sortCookies(_ cookies: [CookieInfo], by sortOption: CookieSortOption, ascending: Bool = true) -> [CookieInfo] {
        let sorted = cookies.sorted { lhs, rhs in
            switch sortOption {
            case .domain:
                return lhs.displayDomain < rhs.displayDomain
            case .name:
                return lhs.name < rhs.name
            case .size:
                return lhs.size < rhs.size
            case .expiration:
                // Handle nil expiration dates (session cookies)
                switch (lhs.expiresDate, rhs.expiresDate) {
                case (nil, nil):
                    return false // Equal
                case (nil, _):
                    return true // Session cookies first
                case (_, nil):
                    return false // Session cookies first
                case (let lhsDate?, let rhsDate?):
                    return lhsDate < rhsDate
                }
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
    
    func getCookieStats() -> (total: Int, session: Int, persistent: Int, expired: Int, totalSize: Int) {
        let sessionCount = cookies.filter { $0.isSessionCookie }.count
        let persistentCount = cookies.count - sessionCount
        let expiredCount = cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return false }
            return expiresDate < Date()
        }.count
        let totalSize = cookies.reduce(0) { $0 + $1.size }
        
        let stats = (
            total: cookies.count,
            session: sessionCount,
            persistent: persistentCount,
            expired: expiredCount,
            totalSize: totalSize
        )
        // Debug diagnostics with profile context
        print("📊 [CookieManager] Stats for profile=\(currentProfileId?.uuidString ?? "nil"): total=\(stats.total), session=\(stats.session), persistent=\(stats.persistent), expired=\(stats.expired), size=\(stats.totalSize)")
        return stats
    }
    
    // MARK: - Private Methods
    
    private func groupCookiesByDomain(_ cookies: [CookieInfo]) -> [DomainCookieGroup] {
        let grouped = Dictionary(grouping: cookies) { cookie in
            // Normalize domain for grouping
            cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        }
        
        return grouped.map { domain, cookies in
            DomainCookieGroup(id: UUID(), domain: domain, cookies: cookies.sorted { $0.name < $1.name })
        }.sorted { $0.displayDomain < $1.displayDomain }
    }
}

// MARK: - Cookie Management Extensions

extension CookieManager {
    func exportCookies() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(cookies)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            print("Error exporting cookies: \(error)")
            return ""
        }
    }
    
    func getCookieDetails(_ cookie: CookieInfo) -> [String: String] {
        var details: [String: String] = [:]
        
        details["Name"] = cookie.name
        details["Value"] = cookie.value.count > 100 ? String(cookie.value.prefix(100)) + "..." : cookie.value
        details["Domain"] = cookie.domain
        details["Path"] = cookie.path
        details["Size"] = cookie.sizeDescription
        details["Secure"] = cookie.isSecure ? "Yes" : "No"
        details["HTTP Only"] = cookie.isHTTPOnly ? "Yes" : "No"
        details["Same Site"] = cookie.sameSitePolicy
        details["Expires"] = cookie.expirationStatus
        
        return details
    }
}

// MARK: - Async WKHTTPCookieStore Bridging

extension WKHTTPCookieStore {
    /// Async wrapper for `getAllCookies` that bridges the completion-handler API into Swift concurrency.
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            self.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
    
    /// Async wrapper for `delete(_:completionHandler:)` to make each deletion awaitable.
    func deleteCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            self.delete(cookie) {
                continuation.resume()
            }
        }
    }
}
