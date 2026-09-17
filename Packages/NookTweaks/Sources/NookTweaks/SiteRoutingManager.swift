//
//  SiteRoutingManager.swift
//  Nook
//

import Foundation
import NookSettings
import OSLog

@MainActor
public final class SiteRoutingManager {
    private let logger = Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")

    private let settings: NookSettingsService
    public weak var host: SiteRoutingHost?

    public init(settings: NookSettingsService) {
        self.settings = settings
    }

    // MARK: - Matching

    public func resolve(url: URL) -> SiteRoutingRule? {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        guard !host.isEmpty else { return nil }

        let rules = settings.siteRoutingRules.filter { $0.isEnabled && $0.domain == host }
        guard !rules.isEmpty else { return nil }

        let path = url.path
        // Most-specific rule wins: longest matching pathPrefix takes priority
        let pathMatches = rules.filter { rule in
            guard let pp = rule.pathPrefix, !pp.isEmpty else { return false }
            return path.hasPrefix(pp)
        }
        if let specific = pathMatches.max(by: { ($0.pathPrefix?.count ?? 0) < ($1.pathPrefix?.count ?? 0) }) {
            return specific
        }
        // Fall back to domain-only rule (no pathPrefix)
        return rules.first(where: { $0.pathPrefix == nil || $0.pathPrefix?.isEmpty == true })
    }

    /// Opens `url` as a new tab in the rule's target space, in the window showing `page`
    /// (or the active window for external URLs). Private windows never route.
    public func applyRoute(url: URL, from page: AnyObject?) -> Bool {
        guard let host, let rule = resolve(url: url) else { return false }
        guard host.route(url: url, toSpace: rule.targetSpaceId, from: page) else { return false }
        logger.info("Route matched: \(url.absoluteString, privacy: .public) → space \(rule.targetSpaceId, privacy: .public)")
        return true
    }

    // MARK: - CRUD

    public func addRule(_ rule: SiteRoutingRule) {
        settings.siteRoutingRules.append(rule)
    }

    public func updateRule(_ rule: SiteRoutingRule) {
        guard let index = settings.siteRoutingRules.firstIndex(where: { $0.id == rule.id }) else { return }
        settings.siteRoutingRules[index] = rule
    }

    public func deleteRule(id: UUID) {
        settings.siteRoutingRules.removeAll(where: { $0.id == id })
    }

    public func rules() -> [SiteRoutingRule] {
        settings.siteRoutingRules
    }

    // MARK: - Migration

    /// Rules used to name a space and a profile. A space that was merged away is no longer live,
    /// and the space that took over its login is the one the old profile id names, so that becomes
    /// the target. Rules pointing nowhere are dropped. Runs once per launch and writes only when
    /// something changed.
    public func dropMergedProfileTargets() {
        guard let host else { return }
        let live = host.liveSpaceIDs()
        var changed = false
        let updated = settings.siteRoutingRules.compactMap { rule -> SiteRoutingRule? in
            guard !live.contains(rule.targetSpaceId) else { return rule }
            guard let heir = rule.legacyProfileId, live.contains(heir) else {
                logger.info("Dropping routing rule for \(rule.domain, privacy: .public): its space is gone")
                changed = true
                return nil
            }
            changed = true
            var moved = rule
            moved.targetSpaceId = heir
            moved.legacyProfileId = nil
            return moved
        }
        guard changed else { return }
        settings.siteRoutingRules = updated
    }
}
