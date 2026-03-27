//
//  ContentRuleListCompiler.swift
//  Nook
//
//  Uses SafariConverterLib to convert AdGuard/uBlock filter rules into
//  WKContentRuleList JSON and advanced rules text for scriptlet/CSS injection.
//  Compiles JSON via WKContentRuleListStore in chunks.
//
//  Caches compiled rule lists: if the rules hash hasn't changed since the last
//  compile, previously compiled WKContentRuleLists are looked up from the store
//  instead of recompiling, making subsequent launches near-instant.
//

import Foundation
import WebKit
import OSLog
import CryptoKit
import ContentBlockerConverter

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentRuleListCompiler {

    private static let chunkSize = 30_000
    private static let storeIdentifierPrefix = "NookAdBlocker"

    struct CompilationResult {
        let ruleLists: [WKContentRuleList]
        let advancedRulesText: String?
    }

    // MARK: - Cache

    private static var cacheDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("io.browsewithnook.nook/ContentBlocker/Cache", isDirectory: true)
    }

    private static var hashFile: URL { cacheDir.appendingPathComponent("rules.sha256") }
    private static var chunkCountFile: URL { cacheDir.appendingPathComponent("chunk-count.txt") }
    private static var advancedRulesFile: URL { cacheDir.appendingPathComponent("advanced-rules.txt") }

    // MARK: - Public API

    /// Compile filter rules via SafariConverterLib.
    /// Returns WKContentRuleLists for network blocking + advancedRulesText for scriptlet/CSS injection.
    /// Uses cached compiled lists when rules haven't changed since last compile.
    static func compile(rules: [String]) async -> CompilationResult {
        guard let store = WKContentRuleListStore.default() else {
            cbLog.error("No WKContentRuleListStore available")
            return CompilationResult(ruleLists: [], advancedRulesText: nil)
        }

        // Compute hash off main thread
        let rulesHash = await Task.detached(priority: .userInitiated) {
            computeRulesHash(rules)
        }.value

        // Try cache
        if let cached = await loadFromCache(hash: rulesHash, store: store) {
            cbLog.info("Cache hit: loaded \(cached.ruleLists.count) rule list(s) without recompiling")
            return cached
        }

        cbLog.info("Cache miss — converting \(rules.count) rules via SafariConverterLib")

        // Run SafariConverterLib conversion off the main thread
        let (jsonEntries, advancedText, stats) = await Task.detached(priority: .userInitiated) {
            // Pre-process: promote cosmetic ##rules containing :has() to #?# (extended CSS).
            // SafariConverterLib routes ## :has() rules into safariRulesJSON as css-display-none,
            // but WKContentRuleList doesn't support :has() selectors — they silently fail.
            // Using #?# sends them through advancedRulesText → AdvancedBlockingEngine,
            // where they're CSS-injected into a <style> element (WebKit CSS supports :has()).
            let preprocessed = rules.map { rule -> String in
                guard rule.contains("##") && !rule.contains("#?#") && !rule.contains("#@") else { return rule }
                // Only cosmetic hiding rules (##), not scriptlet (##+js) or CSS inject (#$#)
                guard let range = rule.range(of: "##"),
                      !rule[range.upperBound...].hasPrefix("+js("),
                      !rule[range.upperBound...].hasPrefix("$"),
                      !rule[range.upperBound...].hasPrefix("%"),
                      rule[range.upperBound...].contains(":has(") else { return rule }
                return rule.replacingCharacters(in: range, with: "#?#")
            }

            let converter = ContentBlockerConverter()
            let result = converter.convertArray(
                rules: preprocessed,
                safariVersion: SafariVersion.autodetect(),
                advancedBlocking: true
            )

            let stats = (result.sourceRulesCount, result.safariRulesCount, result.advancedRulesCount, result.errorsCount)

            // Parse JSON off main thread too
            var entries: [[String: Any]] = []
            if let data = result.safariRulesJSON.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                entries = parsed
            }

            return (entries, result.advancedRulesText, stats)
        }.value

        cbLog.info("SafariConverterLib: \(stats.0) source, \(stats.1) safari, \(stats.2) advanced, \(stats.3) errors")

        // Prepend built-in YouTube rules
        var allEntries = jsonEntries
        allEntries.insert(contentsOf: youTubeNetworkRules(), at: 0)

        // Remove old rule lists
        await removeOldRuleLists(store: store)

        // Compile in chunks
        let chunks = stride(from: 0, to: allEntries.count, by: chunkSize).map { start in
            Array(allEntries[start..<min(start + chunkSize, allEntries.count)])
        }

        var compiled: [WKContentRuleList] = []
        for (index, chunk) in chunks.enumerated() {
            let identifier = "\(storeIdentifierPrefix)_\(index)"
            if let list = await compileChunk(chunk, identifier: identifier, store: store) {
                compiled.append(list)
            } else {
                cbLog.info("Retrying chunk \(index) as two halves")
                let half = chunk.count / 2
                if let r1 = await compileChunk(Array(chunk[0..<half]), identifier: "\(identifier)a", store: store) {
                    compiled.append(r1)
                }
                if let r2 = await compileChunk(Array(chunk[half...]), identifier: "\(identifier)b", store: store) {
                    compiled.append(r2)
                }
            }
        }

        cbLog.info("Compiled \(compiled.count) rule list(s) from \(allEntries.count) entries")

        // Persist cache metadata for next launch
        saveCache(hash: rulesHash, chunkCount: compiled.count, advancedRulesText: advancedText)

        return CompilationResult(
            ruleLists: compiled,
            advancedRulesText: advancedText
        )
    }

    /// Remove all previously compiled rule lists from the store.
    static func removeAll() async {
        guard let store = WKContentRuleListStore.default() else { return }
        await removeOldRuleLists(store: store)
        clearCache()
    }

    // MARK: - Cache Implementation

    private static nonisolated func computeRulesHash(_ rules: [String]) -> String {
        var hasher = SHA256()
        for rule in rules {
            hasher.update(data: Data(rule.utf8))
            hasher.update(data: Data([0x0a])) // newline separator
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func loadFromCache(hash: String, store: WKContentRuleListStore) async -> CompilationResult? {
        // Check hash matches
        guard let storedHash = try? String(contentsOf: hashFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              storedHash == hash else {
            return nil
        }

        // Read chunk count
        guard let countStr = try? String(contentsOf: chunkCountFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let chunkCount = Int(countStr), chunkCount > 0 else {
            return nil
        }

        // Look up all compiled rule lists from the store
        var lists: [WKContentRuleList] = []
        for i in 0..<chunkCount {
            let identifier = "\(storeIdentifierPrefix)_\(i)"
            guard let list = await lookupRuleList(identifier: identifier, store: store) else {
                cbLog.info("Cache invalid: rule list \(identifier, privacy: .public) not found in store")
                return nil
            }
            lists.append(list)
        }

        // Load advanced rules text
        let advancedText = try? String(contentsOf: advancedRulesFile, encoding: .utf8)

        return CompilationResult(ruleLists: lists, advancedRulesText: advancedText)
    }

    private static func saveCache(hash: String, chunkCount: Int, advancedRulesText: String?) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? hash.write(to: hashFile, atomically: true, encoding: .utf8)
        try? "\(chunkCount)".write(to: chunkCountFile, atomically: true, encoding: .utf8)
        if let text = advancedRulesText {
            try? text.write(to: advancedRulesFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: advancedRulesFile)
        }
    }

    private static func clearCache() {
        try? FileManager.default.removeItem(at: hashFile)
        try? FileManager.default.removeItem(at: chunkCountFile)
        try? FileManager.default.removeItem(at: advancedRulesFile)
    }

    private static func lookupRuleList(identifier: String, store: WKContentRuleListStore) async -> WKContentRuleList? {
        await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                cont.resume(returning: list)
            }
        }
    }

    // MARK: - Rule List Management

    private static func removeOldRuleLists(store: WKContentRuleListStore) async {
        let identifiers = await withCheckedContinuation { (cont: CheckedContinuation<[String]?, Never>) in
            store.getAvailableContentRuleListIdentifiers { ids in
                cont.resume(returning: ids)
            }
        }

        guard let ids = identifiers else { return }

        for id in ids where id.hasPrefix(storeIdentifierPrefix) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.removeContentRuleList(forIdentifier: id) { _ in
                    cont.resume()
                }
            }
        }
    }

    private static func compileChunk(
        _ rules: [[String: Any]],
        identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            cbLog.error("Failed to serialize chunk \(identifier, privacy: .public)")
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error {
                    cbLog.error("Compile error for \(identifier, privacy: .public) (\(rules.count) rules): \(error.localizedDescription, privacy: .public)")
                }
                cont.resume(returning: list)
            }
        }
    }

    // MARK: - Built-in YouTube Rules

    private static func youTubeNetworkRules() -> [[String: Any]] {
        let ytDomain = ["*youtube.com", "*youtu.be"]
        return [
            ["trigger": ["url-filter": "googlevideo\\.com/initplayback.*adsp", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/pagead/", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/api/stats/ads", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/get_midroll_info", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "doubleclick\\.net", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "googleadservices\\.com", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/youtubei/v1/player/ad_break", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "youtube\\.com/ptracking", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": ".*", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "css-display-none",
                        "selector": "ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer, #masthead-ad, #player-ads, .video-ads, ytd-rich-item-renderer:has(ytd-ad-slot-renderer)"] as [String: Any]],
        ]
    }
}
