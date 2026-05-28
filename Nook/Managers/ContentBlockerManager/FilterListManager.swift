//
//  FilterListManager.swift
//  Nook
//
//  Downloads, caches, and updates uBlock Origin / EasyList filter lists.
//  Stores raw text in ~/Library/Application Support/io.browsewithnook.nook/ContentBlocker/FilterLists/.
//  Uses conditional HTTP GET (ETag/Last-Modified) for bandwidth-efficient updates.
//

import Foundation
import CryptoKit
import OSLog

@MainActor
final class FilterListManager {

    enum FilterListCategory: String, CaseIterable, Sendable {
        case ads = "Ads"
        case privacy = "Privacy"
        case malware = "Malware"
        case annoyances = "Annoyances"
        case regional = "Regional"
        case social = "Social"
    }

    struct FilterList {
        let name: String
        let url: URL
        let filename: String
        let knownSizeRange: ClosedRange<Int>?  // Expected size range to detect gross tampering
        let category: FilterListCategory
        let isOptional: Bool

        init(name: String, url: URL, filename: String, knownSizeRange: ClosedRange<Int>?, category: FilterListCategory = .ads, isOptional: Bool = false) {
            self.name = name
            self.url = url
            self.filename = filename
            self.knownSizeRange = knownSizeRange
            self.category = category
            self.isOptional = isOptional
        }
    }

    static let defaultLists: [FilterList] = [
        FilterList(name: "EasyList", url: URL(string: "https://easylist.to/easylist/easylist.txt")!, filename: "easylist.txt", knownSizeRange: 100_000...10_000_000, category: .ads),
        FilterList(name: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!, filename: "easyprivacy.txt", knownSizeRange: 50_000...5_000_000, category: .privacy),
        FilterList(name: "Peter Lowe's", url: URL(string: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0")!, filename: "peter-lowes.txt", knownSizeRange: 10_000...2_000_000, category: .ads),
        FilterList(name: "uBlock Filters", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt")!, filename: "ublock-filters.txt", knownSizeRange: 50_000...5_000_000, category: .ads),
        FilterList(name: "uBlock Unbreak", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt")!, filename: "ublock-unbreak.txt", knownSizeRange: 5_000...2_000_000, category: .ads),
        FilterList(name: "uBlock Badware", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt")!, filename: "ublock-badware.txt", knownSizeRange: 5_000...2_000_000, category: .malware),
        FilterList(name: "uBlock Privacy", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt")!, filename: "ublock-privacy.txt", knownSizeRange: 5_000...2_000_000, category: .privacy),
        FilterList(name: "Nook Filters", url: URL(string: "https://raw.githubusercontent.com/nook-browser/nook-filters/main/nook-filters.txt")!, filename: "nook-filters.txt", knownSizeRange: 1_000...1_000_000, category: .ads),
        FilterList(name: "uBlock Quick Fixes", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt")!, filename: "ublock-quick-fixes.txt", knownSizeRange: 1_000...2_000_000, category: .ads),
        FilterList(name: "Online Malicious URL Blocklist", url: URL(string: "https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-online.txt")!, filename: "urlhaus-filter.txt", knownSizeRange: 10_000...5_000_000, category: .malware),
    ]

    static let optionalLists: [FilterList] = [
        // Annoyances
        FilterList(name: "AdGuard Annoyances", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/14.txt")!, filename: "adguard-annoyances.txt", knownSizeRange: 10_000...5_000_000, category: .annoyances, isOptional: true),
        FilterList(name: "uBlock Annoyances (cookies)", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-cookies.txt")!, filename: "ublock-annoyances-cookies.txt", knownSizeRange: 1_000...2_000_000, category: .annoyances, isOptional: true),
        FilterList(name: "uBlock Annoyances (others)", url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt")!, filename: "ublock-annoyances-others.txt", knownSizeRange: 1_000...2_000_000, category: .annoyances, isOptional: true),
        FilterList(name: "EasyList Cookie", url: URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!, filename: "easylist-cookie.txt", knownSizeRange: 10_000...5_000_000, category: .annoyances, isOptional: true),
        FilterList(name: "Fanboy's Annoyance", url: URL(string: "https://secure.fanboy.co.nz/fanboy-annoyance.txt")!, filename: "fanboy-annoyance.txt", knownSizeRange: 10_000...5_000_000, category: .annoyances, isOptional: true),
        FilterList(name: "Fanboy's Social", url: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!, filename: "fanboy-social.txt", knownSizeRange: 5_000...5_000_000, category: .social, isOptional: true),
        // AdGuard
        FilterList(name: "AdGuard Base", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/2.txt")!, filename: "adguard-base.txt", knownSizeRange: 50_000...10_000_000, category: .ads, isOptional: true),
        FilterList(name: "AdGuard Mobile Ads", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/11.txt")!, filename: "adguard-mobile.txt", knownSizeRange: 5_000...5_000_000, category: .ads, isOptional: true),
        FilterList(name: "AdGuard Tracking Protection", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/3.txt")!, filename: "adguard-tracking.txt", knownSizeRange: 10_000...5_000_000, category: .privacy, isOptional: true),
        // Regional
        FilterList(name: "AdGuard Chinese", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/224.txt")!, filename: "adguard-chinese.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard Japanese", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/7.txt")!, filename: "adguard-japanese.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard French", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/16.txt")!, filename: "adguard-french.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard German", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/6.txt")!, filename: "adguard-german.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard Russian", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/1.txt")!, filename: "adguard-russian.txt", knownSizeRange: 10_000...10_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard Spanish/Portuguese", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/9.txt")!, filename: "adguard-spanish.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "AdGuard Turkish", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/13.txt")!, filename: "adguard-turkish.txt", knownSizeRange: 5_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "IndianList", url: URL(string: "https://raw.githubusercontent.com/nickspaargaren/IndianList/master/IndianList.txt")!, filename: "indianlist.txt", knownSizeRange: 1_000...5_000_000, category: .regional, isOptional: true),
        FilterList(name: "KoreanList", url: URL(string: "https://raw.githubusercontent.com/nickspaargaren/Korean-Adblock-List/master/koreanlist.txt")!, filename: "koreanlist.txt", knownSizeRange: 1_000...5_000_000, category: .regional, isOptional: true),
    ]

    /// Returns currently enabled optional lists
    var enabledOptionalLists: [FilterList] {
        let enabled = enabledOptionalFilterListFilenames
        return Self.optionalLists.filter { enabled.contains($0.filename) }
    }

    /// Filenames of enabled optional filter lists (persisted externally via NookSettingsService)
    nonisolated(unsafe) var enabledOptionalFilterListFilenames: Set<String> = []

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "FilterListManager")

    private let cacheDir: URL
    private let etagDir: URL
    private let session: URLSession

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("io.browsewithnook.nook/ContentBlocker/FilterLists", isDirectory: true)
        self.cacheDir = base
        self.etagDir = base.appendingPathComponent(".etags", isDirectory: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: etagDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Returns all cached filter list contents. Downloads any missing lists first.
    func loadAllFilterLists() async -> [String] {
        var results: [String] = []

        for list in Self.defaultLists {
            if let content = loadCachedList(list) {
                results.append(content)
            }
        }

        return results
    }

    /// Returns true if any lists were actually downloaded (changed on disk).
    var hasCachedLists: Bool {
        for list in Self.defaultLists {
            let file = cacheDir.appendingPathComponent(list.filename)
            if FileManager.default.fileExists(atPath: file.path) {
                return true
            }
        }
        return false
    }

    /// Download all filter lists (default + enabled optional). Returns true if any list was updated.
    @discardableResult
    func downloadAllLists() async -> Bool {
        var anyUpdated = false

        let allLists = Self.defaultLists + enabledOptionalLists

        await withTaskGroup(of: Bool.self) { group in
            for list in allLists {
                group.addTask { [self] in
                    await self.downloadList(list)
                }
            }

            for await updated in group {
                if updated { anyUpdated = true }
            }
        }

        return anyUpdated
    }

    /// Load all cached filter lists and return as individual rule lines for SafariConverterLib.
    nonisolated func loadAllFilterRulesAsLines() -> [String] {
        var allLines: [String] = []

        let enabledFilenames = enabledOptionalFilterListFilenames
        let optionalLists = Self.optionalLists.filter { enabledFilenames.contains($0.filename) }

        for list in Self.defaultLists + optionalLists {
            guard let content = loadCachedList(list) else { continue }
            let lines = content.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            allLines.append(contentsOf: lines)
        }

        return allLines
    }

    // MARK: - Private

    private nonisolated func loadCachedList(_ list: FilterList) -> String? {
        let file = cacheDir.appendingPathComponent(list.filename)
        if let content = try? String(contentsOf: file, encoding: .utf8) {
            return content
        }

        // Fallback: load bundled default copy if available
        // Try exact filename first, then with "-default" suffix (e.g., nook-filters-default.txt)
        let bundleName = (list.filename as NSString).deletingPathExtension
        let bundleExt = (list.filename as NSString).pathExtension
        for name in [bundleName, bundleName + "-default"] {
            if let bundlePath = Bundle.main.path(forResource: name, ofType: bundleExt),
               let bundleContent = try? String(contentsOfFile: bundlePath, encoding: .utf8) {
                return bundleContent
            }
        }

        return nil
    }

    /// Download a single filter list. Returns true if the list was updated.
    private func downloadList(_ list: FilterList) async -> Bool {
        let destFile = cacheDir.appendingPathComponent(list.filename)
        let etagFile = etagDir.appendingPathComponent(list.filename + ".etag")

        var request = URLRequest(url: list.url)

        // Conditional GET
        if let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if FileManager.default.fileExists(atPath: destFile.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destFile.path),
           let modDate = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            request.setValue(formatter.string(from: modDate), forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 304 {
                Self.log.info("\(list.name): not modified")
                return false
            }

            guard httpResponse.statusCode == 200 else {
                Self.log.warning("\(list.name): HTTP \(httpResponse.statusCode)")
                return false
            }

            // Validate content before writing to disk
            guard let content = String(data: data, encoding: .utf8) else {
                Self.log.warning("\(list.name): downloaded data is not valid UTF-8")
                return false
            }

            if !validateFilterListContent(content, for: list) {
                Self.log.warning("\(list.name): validation failed, keeping previous cached version")
                return false
            }

            // Compute hash and check for changes
            let newHash = computeHash(content)
            if let previousHash = storedHash(for: list), previousHash != newHash {
                Self.log.info("\(list.name): content hash changed from \(previousHash.prefix(16)) to \(newHash.prefix(16))")
            }

            // Save content
            try data.write(to: destFile, options: .atomic)

            // Store hash alongside the list
            storeHash(newHash, for: list)

            // Save ETag
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
            }

            Self.log.info("\(list.name): updated (\(data.count) bytes, hash: \(newHash.prefix(16)))")
            return true
        } catch {
            Self.log.error("\(list.name): download failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Content Validation

    private func validateFilterListContent(_ content: String, for list: FilterList) -> Bool {
        // Basic structural validation
        guard !content.isEmpty else { return false }

        // Filter lists should be text-based with recognizable patterns
        let lines = content.components(separatedBy: "\n")
        guard lines.count > 10 else { return false }  // Too small to be a real filter list

        // Check that first non-empty line looks like a filter list header
        let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let validHeaders = ["[Adblock", "! Title:", "! Homepage:", "!", "#"]
        let looksLikeFilterList = validHeaders.contains(where: { firstNonEmpty.hasPrefix($0) })

        if !looksLikeFilterList {
            Self.log.warning("Filter list '\(list.name)' has unexpected header: \(firstNonEmpty.prefix(50))")
            return false
        }

        // Check size is within expected range (if specified)
        if let sizeRange = list.knownSizeRange {
            let contentSize = content.utf8.count
            if !sizeRange.contains(contentSize) {
                Self.log.warning("Filter list '\(list.name)' size \(contentSize) outside expected range \(sizeRange)")
                return false
            }
        }

        // Check for suspicious patterns that shouldn't be in filter lists
        let suspiciousPatterns = [
            "eval(", "Function(", "new Function",
            "document.cookie", "localStorage.", "sessionStorage.",
            "XMLHttpRequest", "fetch(", ".send(",
            "window.location =", "window.location.href ="
        ]

        // Only flag if these appear outside of standard scriptlet patterns
        // (scriptlets legitimately contain some of these for interception purposes)
        var suspiciousCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comment lines and standard filter rules
            if trimmed.hasPrefix("!") || trimmed.hasPrefix("#") { continue }
            // Check non-filter-rule lines for suspicious content
            for pattern in suspiciousPatterns {
                if trimmed.contains(pattern) {
                    suspiciousCount += 1
                }
            }
        }

        if suspiciousCount > 50 {
            Self.log.warning("Filter list '\(list.name)' contains \(suspiciousCount) suspicious patterns")
            return false
        }

        return true
    }

    // MARK: - Hash Verification

    private func computeHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func storeHash(_ hash: String, for list: FilterList) {
        let hashFile = cacheDir.appendingPathComponent(list.filename + ".sha256")
        try? hash.write(to: hashFile, atomically: true, encoding: .utf8)
    }

    private func storedHash(for list: FilterList) -> String? {
        let hashFile = cacheDir.appendingPathComponent(list.filename + ".sha256")
        return try? String(contentsOf: hashFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
