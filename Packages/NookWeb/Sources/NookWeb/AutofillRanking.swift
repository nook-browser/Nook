// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  AutofillRanking.swift
//  Nook
//
//  Created by Bain Gurley on 19/09/2026.
//

import Foundation

/// Picks the host the omnibox completes to. Kept free of SwiftData so it can be exercised directly.
public enum AutofillRanking {
    /// Two characters minimum, and nothing that is already a path or a multi-word search.
    public static func isUsable(prefix: String) -> Bool {
        let needle = prefix.lowercased()
        return needle.count >= 2 && !needle.contains(" ") && !needle.contains("/")
    }

    /// Host with the most visits among those starting with `prefix`, most recent breaking a tie.
    /// Visits are summed per host, so a root visited twice outranks one deep page visited twice.
    public static func bestHost(
        in entries: [(url: String, visitCount: Int, lastVisited: Date)],
        prefix: String,
        minVisits: Int
    ) -> String? {
        guard isUsable(prefix: prefix) else { return nil }
        let needle = prefix.lowercased()

        var visits: [String: Int] = [:]
        var recency: [String: Date] = [:]
        for entry in entries {
            guard let host = URL(string: entry.url)?.host?.lowercased() else { continue }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            guard bare.hasPrefix(needle) else { continue }
            visits[bare, default: 0] += max(entry.visitCount, 1)
            if entry.lastVisited > recency[bare] ?? .distantPast { recency[bare] = entry.lastVisited }
        }
        return visits.filter { $0.value >= minVisits }
            .max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return recency[lhs.key] ?? .distantPast < recency[rhs.key] ?? .distantPast
            }?.key
    }
}
