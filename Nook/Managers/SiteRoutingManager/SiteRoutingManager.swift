//
//  SiteRoutingManager.swift
//  Nook
//

import Foundation
import NookSettings
import NookTabsCore
import OSLog

@MainActor
class SiteRoutingManager {
    private let logger = Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")

    weak var settingsService: NookSettingsService?
    weak var browserManager: BrowserManager?

    // MARK: - Matching

    func resolve(url: URL) -> SiteRoutingRule? {
        guard let settingsService else { return nil }
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        guard !host.isEmpty else { return nil }

        let rules = settingsService.siteRoutingRules.filter { $0.isEnabled && $0.domain == host }
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

    /// Opens `url` as a new tab in the rule's target space, in the window showing `session`
    /// (or the active window for external URLs). Private windows never route.
    func applyRoute(url: URL, from session: PageSession?) -> Bool {
        guard let browserManager, session?.isPrivate != true else { return false }
        let tabs = browserManager.tabs
        guard let window = session.flatMap({ tabs.window(for: $0) }) ?? browserManager.windowRegistry?.activeWindow,
              !window.isIncognito,
              let rule = resolve(url: url)
        else { return false }

        guard let target = tabs.space(rule.targetSpaceId) else {
            logger.debug("Route skipped: target space no longer exists for rule \(rule.id)")
            return false
        }
        guard window.spaceID != target.id else { return false }

        logger.info("Route matched: \(url.absoluteString, privacy: .public) → space '\(target.name, privacy: .public)'")

        // Deferred: callers are WebKit policy callbacks. Selecting the new tab shows its space.
        Task { @MainActor in
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: target.id))
        }
        return true
    }

    // MARK: - CRUD

    func addRule(_ rule: SiteRoutingRule) {
        settingsService?.siteRoutingRules.append(rule)
    }

    func updateRule(_ rule: SiteRoutingRule) {
        guard let index = settingsService?.siteRoutingRules.firstIndex(where: { $0.id == rule.id }) else { return }
        settingsService?.siteRoutingRules[index] = rule
    }

    func deleteRule(id: UUID) {
        settingsService?.siteRoutingRules.removeAll(where: { $0.id == id })
    }

    func rules() -> [SiteRoutingRule] {
        settingsService?.siteRoutingRules ?? []
    }

    // MARK: - Migration

    /// Rules used to name a space and a profile. A space that was merged away is no longer live,
    /// and the space that took over its login is the one the old profile id names, so that becomes
    /// the target. Rules pointing nowhere are dropped. Runs once per launch and writes only when
    /// something changed.
    func dropMergedProfileTargets() {
        guard let settingsService, let tabs = browserManager?.tabs else { return }
        let live = Set(tabs.orderedSpaces.map(\.id))
        var changed = false
        let updated = settingsService.siteRoutingRules.compactMap { rule -> SiteRoutingRule? in
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
        settingsService.siteRoutingRules = updated
    }
}
