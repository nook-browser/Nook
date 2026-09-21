// Licensed under GPL-3.0. See LICENSE.
//
//  AutofillRanking.swift
//  Nook
//
//  Created by Bain Gurley on 19/09/2026.
//

import Foundation

/// What the autofill index keeps per host: visits summed across every page of that host.
public struct HostStat: Equatable, Sendable {
    public var visits: Int
    public var lastVisited: Date

    public init(visits: Int, lastVisited: Date) {
        self.visits = visits
        self.lastVisited = lastVisited
    }
}

/// Picks the host the omnibox completes to. Kept free of SwiftData so it can be exercised directly.
public enum AutofillRanking {
    /// Two characters minimum, and nothing that is already a path or a multi-word search.
    public static func isUsable(prefix: String) -> Bool {
        let needle = prefix.lowercased()
        return needle.count >= 2 && !needle.contains(" ") && !needle.contains("/")
    }

    /// Bare host of a stored URL, lowercased with `www.` dropped. Nil when there is no host.
    public static func host(for url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Folds one page's visits into the index. Also how a fresh visit reaches an already built one.
    public static func add(url: String, visits: Int, at date: Date, to hosts: inout [String: HostStat]) {
        guard let host = host(for: url) else { return }
        var stat = hosts[host] ?? HostStat(visits: 0, lastVisited: .distantPast)
        stat.visits += max(visits, 1)
        stat.lastVisited = max(stat.lastVisited, date)
        hosts[host] = stat
    }

    public static func aggregate(_ entries: [(url: String, visitCount: Int, lastVisited: Date)]) -> [String: HostStat] {
        var hosts: [String: HostStat] = [:]
        for entry in entries {
            add(url: entry.url, visits: entry.visitCount, at: entry.lastVisited, to: &hosts)
        }
        return hosts
    }

    /// Host with the most visits among those starting with `prefix`, most recent breaking a tie.
    /// Visits are summed per host, so a root visited twice outranks one deep page visited twice.
    public static func bestHost(in hosts: [String: HostStat], prefix: String, minVisits: Int) -> String? {
        guard isUsable(prefix: prefix) else { return nil }
        let needle = prefix.lowercased()
        return hosts.lazy
            .filter { $0.key.hasPrefix(needle) && $0.value.visits >= minVisits }
            .max { lhs, rhs in
                if lhs.value.visits != rhs.value.visits { return lhs.value.visits < rhs.value.visits }
                return lhs.value.lastVisited < rhs.value.lastVisited
            }?.key
    }
}
