// Licensed under GPL-3.0. See LICENSE.
//
//  TabOrganizationPlan.swift
//  Nook
//
//  What one organizer run will do. Integers are the 1-based tab numbers from the prompt.
//

import Foundation

// MARK: - Inputs

/// A tab's prompt number, title and URL, captured before inference.
struct TabInput {
    let index: Int
    let itemID: UUID
    let title: String
    let url: URL
}

/// A folder already in the section, offered to the model so a second run files into it.
struct ExistingFolder {
    let id: UUID
    let name: String
    let sampleTitles: [String]
}

// MARK: - TabOrganizationPlan

struct TabOrganizationPlan {

    struct Group {
        let name: String
        /// Set when the tabs go into a folder that already exists.
        let existingFolderID: UUID?
        let tabs: [Int]
    }

    struct Rename {
        let tab: Int
        let name: String
    }

    let groups: [Group]
    let renames: [Rename]
    /// Tabs to close because an earlier tab shows the same page.
    let duplicates: [Int]

    // MARK: - Duplicates

    /// Every tab whose page an earlier tab already shows. No model involved: two tabs are the
    /// same page when host, path, query and fragment match, ignoring scheme, "www." and a trailing slash.
    /// `filed` are the URLs of tabs already in the section's folders; a loose copy of one closes too.
    static func duplicates(in inputs: [TabInput], filed: [URL] = []) -> [Int] {
        var seen = Set(filed.map(pageKey))
        return inputs.filter { !seen.insert(pageKey($0.url)).inserted }.map(\.index)
    }

    private static func pageKey(_ url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(host)\(path)?\(url.query ?? "")#\(url.fragment ?? "")"
    }
}
