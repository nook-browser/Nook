//
//  DeclarativeNetRequestManager.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  Manages declarativeNetRequest API for content blocking
//

import Foundation
import WebKit
import os.log

/// Manages declarativeNetRequest rules and content blocking
/// Converts Chrome declarativeNetRequest rules to Apple WKContentRuleList
@available(macOS 15.4, *)
class DeclarativeNetRequestManager {
    
    // MARK: - Types
    
    /// Chrome declarativeNetRequest rule
    struct DNRRule: Codable {
        let id: Int
        let priority: Int?
        let action: DNRAction
        let condition: DNRCondition
    }
    
    struct DNRAction: Codable {
        let type: ActionType
        let redirect: RedirectAction?
        let requestHeaders: [ModifyHeaderInfo]?
        let responseHeaders: [ModifyHeaderInfo]?
        
        enum ActionType: String, Codable {
            case block
            case allow
            case allowAllRequests
            case upgradeScheme
            case redirect
            case modifyHeaders
        }
    }
    
    struct RedirectAction: Codable {
        let url: String?
        let extensionPath: String?
        let transform: URLTransform?
        let regexSubstitution: String?
    }
    
    struct URLTransform: Codable {
        let scheme: String?
        let host: String?
        let port: String?
        let path: String?
        let query: String?
        let queryTransform: QueryTransform?
        let fragment: String?
        let username: String?
        let password: String?
    }
    
    struct QueryTransform: Codable {
        let addOrReplaceParams: [[String: String]]?
        let removeParams: [String]?
    }
    
    struct DNRCondition: Codable {
        let urlFilter: String?
        let regexFilter: String?
        let isUrlFilterCaseSensitive: Bool?
        let initiatorDomains: [String]?
        let excludedInitiatorDomains: [String]?
        let requestDomains: [String]?
        let excludedRequestDomains: [String]?
        let domains: [String]?
        let excludedDomains: [String]?
        let resourceTypes: [String]?
        let excludedResourceTypes: [String]?
        let requestMethods: [String]?
        let excludedRequestMethods: [String]?
        let domainType: String?
        let tabIds: [Int]?
        let excludedTabIds: [Int]?
    }
    
    struct ModifyHeaderInfo: Codable {
        let header: String
        let operation: String
        let value: String?
    }
    
    enum DNRError: Error {
        case compilationFailed(String)
        case invalidRule(String)
        case quotaExceeded
        case rulesetNotFound(String)
    }
    
    // MARK: - Properties
    
    /// Compiled rule lists per extension
    private var compiledRuleLists: [String: WKContentRuleList] = [:]
    
    /// Static rules per extension (from manifest)
    private var staticRules: [String: [DNRRule]] = [:]
    
    /// Dynamic rules per extension
    private var dynamicRules: [String: [DNRRule]] = [:]
    
    /// Session rules per extension
    private var sessionRules: [String: [DNRRule]] = [:]
    
    /// Rule compilation queue
    private let compilationQueue = DispatchQueue(label: "com.nook.dnr.compilation", qos: .userInitiated)
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Logger
    private let logger = Logger(subsystem: "com.nook.DeclarativeNetRequestManager", category: "DNR")
    
    /// Maximum number of dynamic rules per extension
    private let maxDynamicRules = 5000
    
    /// Maximum number of session rules per extension
    private let maxSessionRules = 5000
    
    // MARK: - Public API
    
    /// Load static rules from extension manifest
    func loadStaticRules(for extensionId: String, from rulesets: [[String: Any]]) async throws {
        logger.info("📋 Loading static rules for extension \(extensionId)")
        
        var allRules: [DNRRule] = []
        
        for ruleset in rulesets {
            guard let enabled = ruleset["enabled"] as? Bool, enabled,
                  let path = ruleset["path"] as? String else {
                continue
            }
            
            // Load rules from file path (you'll need to resolve this relative to extension bundle)
            if let rules = try? await loadRulesFromFile(extensionId: extensionId, path: path) {
                allRules.append(contentsOf: rules)
            }
        }
        
        lock.lock()
        staticRules[extensionId] = allRules
        lock.unlock()
        
        logger.info("✅ Loaded \(allRules.count) static rules for extension \(extensionId)")
        
        // Compile rules
        try await compileRules(for: extensionId)
    }
    
    /// Update dynamic rules
    func updateDynamicRules(for extensionId: String, options: [String: Any]) async throws {
        let addRules = (options["addRules"] as? [[String: Any]] ?? []).compactMap { parseRule(from: $0) }
        let removeRuleIds = options["removeRuleIds"] as? [Int] ?? []
        
        lock.lock()
        var rules = dynamicRules[extensionId] ?? []
        
        // Remove rules
        rules.removeAll { removeRuleIds.contains($0.id) }
        
        // Add new rules
        rules.append(contentsOf: addRules)
        
        // Check quota
        guard rules.count <= maxDynamicRules else {
            lock.unlock()
            throw DNRError.quotaExceeded
        }
        
        dynamicRules[extensionId] = rules
        lock.unlock()
        
        logger.info("🔄 Updated dynamic rules for \(extensionId): +\(addRules.count) -\(removeRuleIds.count)")
        
        // Recompile with new rules
        try await compileRules(for: extensionId)
    }
    
    /// Update session rules
    func updateSessionRules(for extensionId: String, options: [String: Any]) async throws {
        let addRules = (options["addRules"] as? [[String: Any]] ?? []).compactMap { parseRule(from: $0) }
        let removeRuleIds = options["removeRuleIds"] as? [Int] ?? []
        
        lock.lock()
        var rules = sessionRules[extensionId] ?? []
        
        // Remove rules
        rules.removeAll { removeRuleIds.contains($0.id) }
        
        // Add new rules
        rules.append(contentsOf: addRules)
        
        // Check quota
        guard rules.count <= maxSessionRules else {
            lock.unlock()
            throw DNRError.quotaExceeded
        }
        
        sessionRules[extensionId] = rules
        lock.unlock()
        
        logger.info("🔄 Updated session rules for \(extensionId): +\(addRules.count) -\(removeRuleIds.count)")
        
        // Recompile with new rules
        try await compileRules(for: extensionId)
    }
    
    /// Get dynamic rules
    func getDynamicRules(for extensionId: String) -> [DNRRule] {
        lock.lock()
        defer { lock.unlock() }
        return dynamicRules[extensionId] ?? []
    }
    
    /// Get session rules
    func getSessionRules(for extensionId: String) -> [DNRRule] {
        lock.lock()
        defer { lock.unlock() }
        return sessionRules[extensionId] ?? []
    }
    
    /// Get compiled rule list for an extension
    func getRuleList(for extensionId: String) -> WKContentRuleList? {
        lock.lock()
        defer { lock.unlock() }
        return compiledRuleLists[extensionId]
    }
    
    // MARK: - Rule Compilation
    
    /// Compile all rules for an extension into WKContentRuleList
    private func compileRules(for extensionId: String) async throws {
        logger.info("🔨 Compiling rules for extension \(extensionId)")
        
        // Collect all rules
        lock.lock()
        let static = staticRules[extensionId] ?? []
        let dynamic = dynamicRules[extensionId] ?? []
        let session = sessionRules[extensionId] ?? []
        lock.unlock()
        
        let allRules = static + dynamic + session
        
        guard !allRules.isEmpty else {
            logger.info("ℹ️ No rules to compile for \(extensionId)")
            return
        }
        
        logger.info("📊 Total rules to compile: \(allRules.count) (static: \(static.count), dynamic: \(dynamic.count), session: \(session.count))")
        
        // Convert to WKContentRuleList format
        let wkRules = try convertToWKContentRules(allRules)
        
        // Compile using WKContentRuleListStore
        let identifier = "extension-\(extensionId)-rules"
        let ruleList = try await compileWKContentRuleList(identifier: identifier, rules: wkRules)
        
        lock.lock()
        compiledRuleLists[extensionId] = ruleList
        lock.unlock()
        
        logger.info("✅ Successfully compiled \(allRules.count) rules for \(extensionId)")
    }
    
    /// Convert DNR rules to WKContentRuleList JSON format
    private func convertToWKContentRules(_ rules: [DNRRule]) throws -> String {
        var wkRules: [[String: Any]] = []
        
        for rule in rules {
            if let wkRule = convertSingleRule(rule) {
                wkRules.append(wkRule)
            }
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: wkRules, options: [.prettyPrinted])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw DNRError.compilationFailed("Failed to serialize rules to JSON")
        }
        
        return jsonString
    }
    
    /// Convert a single DNR rule to WKContentRuleList format
    private func convertSingleRule(_ rule: DNRRule) -> [String: Any]? {
        var wkRule: [String: Any] = [:]
        
        // Build trigger
        var trigger: [String: Any] = [:]
        
        // URL filter (required)
        if let urlFilter = rule.condition.urlFilter {
            trigger["url-filter"] = convertURLFilter(urlFilter)
        } else if let regexFilter = rule.condition.regexFilter {
            trigger["url-filter"] = regexFilter
        } else {
            // No filter = match all
            trigger["url-filter"] = ".*"
        }
        
        // Case sensitivity
        if rule.condition.isUrlFilterCaseSensitive == true {
            trigger["url-filter-is-case-sensitive"] = true
        }
        
        // Resource types
        if let resourceTypes = rule.condition.resourceTypes, !resourceTypes.isEmpty {
            trigger["resource-type"] = resourceTypes.compactMap { convertResourceType($0) }
        }
        
        // Load type (first-party / third-party)
        if let domainType = rule.condition.domainType {
            trigger["load-type"] = [domainType == "firstParty" ? "first-party" : "third-party"]
        }
        
        // If-domain (initiator domains)
        if let domains = rule.condition.initiatorDomains ?? rule.condition.domains, !domains.isEmpty {
            trigger["if-domain"] = domains.map { "*" + $0 }
        }
        
        // Unless-domain (excluded domains)
        if let excludedDomains = rule.condition.excludedInitiatorDomains ?? rule.condition.excludedDomains, !excludedDomains.isEmpty {
            trigger["unless-domain"] = excludedDomains.map { "*" + $0 }
        }
        
        wkRule["trigger"] = trigger
        
        // Build action
        var action: [String: Any] = [:]
        
        switch rule.action.type {
        case .block:
            action["type"] = "block"
            
        case .allow, .allowAllRequests:
            action["type"] = "ignore-previous-rules"
            
        case .upgradeScheme:
            action["type"] = "make-https"
            
        case .redirect:
            // WKContentRuleList doesn't support full redirect
            // Best effort: block the request
            action["type"] = "block"
            
        case .modifyHeaders:
            // WKContentRuleList doesn't support header modification
            // Silently ignore
            return nil
        }
        
        wkRule["action"] = action
        
        return wkRule
    }
    
    /// Convert Chrome URL filter to WebKit format
    private func convertURLFilter(_ filter: String) -> String {
        var result = filter
        
        // Chrome format: ||domain.com^  ->  WebKit: .*domain\.com[/:?]
        result = result.replacingOccurrences(of: "||", with: ".*")
        result = result.replacingOccurrences(of: "^", with: "[/:?]")
        
        // Escape dots
        result = result.replacingOccurrences(of: ".", with: "\\.")
        
        // Handle wildcards
        result = result.replacingOccurrences(of: "*", with: ".*")
        
        return result
    }
    
    /// Convert Chrome resource type to WebKit format
    private func convertResourceType(_ type: String) -> String? {
        switch type.lowercased() {
        case "main_frame": return "document"
        case "sub_frame": return "document"
        case "stylesheet": return "style-sheet"
        case "script": return "script"
        case "image": return "image"
        case "font": return "font"
        case "xmlhttprequest": return "fetch"
        case "ping": return "ping"
        case "media": return "media"
        case "websocket": return "websocket"
        default: return nil
        }
    }
    
    /// Compile WKContentRuleList from JSON
    private func compileWKContentRuleList(identifier: String, rules: String) async throws -> WKContentRuleList {
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: rules
            ) { ruleList, error in
                if let error = error {
                    self.logger.error("❌ Rule compilation failed: \(error.localizedDescription)")
                    continuation.resume(throwing: DNRError.compilationFailed(error.localizedDescription))
                } else if let ruleList = ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: DNRError.compilationFailed("Unknown error"))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Load rules from file
    private func loadRulesFromFile(extensionId: String, path: String) async throws -> [DNRRule] {
        // This is a placeholder - you'll need to resolve the path relative to the extension bundle
        // For now, return empty array
        logger.warning("⚠️ loadRulesFromFile not fully implemented yet")
        return []
    }
    
    /// Parse rule from dictionary
    private func parseRule(from dict: [String: Any]) -> DNRRule? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let rule = try? JSONDecoder().decode(DNRRule.self, from: data) else {
            logger.error("❌ Failed to parse rule: \(dict)")
            return nil
        }
        return rule
    }
    
    // MARK: - Cleanup
    
    /// Remove all rules for an extension
    func removeRules(for extensionId: String) async {
        lock.lock()
        staticRules.removeValue(forKey: extensionId)
        dynamicRules.removeValue(forKey: extensionId)
        sessionRules.removeValue(forKey: extensionId)
        compiledRuleLists.removeValue(forKey: extensionId)
        lock.unlock()
        
        // Remove compiled rule list from store
        let identifier = "extension-\(extensionId)-rules"
        try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier)
        
        logger.info("🗑️ Removed all rules for extension \(extensionId)")
    }
}

