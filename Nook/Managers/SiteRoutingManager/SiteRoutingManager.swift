//
//  SiteRoutingManager.swift
//  Nook
//

import Foundation
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

    /// Old-model entry point still called by `Tab`; removed with `Tab` in task Z.
    func applyRoute(url: URL, from sourceTab: Tab?) -> Bool {
        if sourceTab?.resolveProfile()?.isEphemeral == true { return false }
        return applyRoute(url: url, from: sourceTab.flatMap { browserManager?.tabs.session(for: $0.id) })
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
}
