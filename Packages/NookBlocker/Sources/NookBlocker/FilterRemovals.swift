// Licensed under GPL-3.0. See LICENSE.
//
//  FilterRemovals.swift
//  Nook
//
//  Lines Nook takes out of every filter list before anything reads it, from
//  `nook-filter-removals.list`. The lists change daily and one bad upstream rule
//  reaches every install; this undoes it without an app update. It can only remove.
//

import Foundation

enum FilterRemovals {
    /// The filters a removals file names: one per line, comments and blank lines aside.
    static func lines(in file: String) -> [String] {
        file.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("!") }
    }

    /// `text` without the lines equal to one of `removals`. A byte search finds whether any
    /// is there first, so a launch pays for the line-by-line pass only when one is.
    static func apply(_ text: String, removing removals: [String]) -> String {
        let present = Set(removals.filter { FilterLineSearch.lines(containing: $0, in: [text]).contains($0) })
        guard !present.isEmpty else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !present.contains($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
    }
}
