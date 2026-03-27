//
//  TabOrganizationPrompt.swift
//  Nook
//
//  Builds structured prompts from tab metadata for LLM-based tab organization.
//  Uses integer indices so the model output maps directly back to tabs.
//

import Foundation

// MARK: - TabInput

/// Pairs a tab with a stable integer index for prompt construction and result mapping.
struct TabInput {
    let index: Int
    let tab: Tab
}

// MARK: - TabOrganizationPrompt

/// Builds system + user prompts that instruct a local LLM to organize browser tabs.
enum TabOrganizationPrompt {

    /// Maximum number of tabs we send in a single prompt to stay within context limits.
    static let maxTabs = 60

    /// A prompt pair suitable for chat-template usage (separate system and user messages).
    struct Prompt {
        let system: String
        let user: String
    }

    // MARK: - Public

    /// Build a prompt pair from the given tabs, space name, and any existing folder names.
    ///
    /// - Parameters:
    ///   - tabs: The tabs to organize, each paired with a stable integer index.
    ///   - spaceName: Name of the space the tabs belong to.
    ///   - existingFolderNames: Names of folders that already exist in this space (used as context).
    /// - Returns: A ``Prompt`` with separate system and user strings.
    @MainActor
    static func build(
        tabs: [TabInput],
        spaceName: String,
        existingFolderNames: [String]
    ) -> Prompt {
        let system = buildSystem()
        let user = buildUser(tabs: tabs, spaceName: spaceName, existingFolderNames: existingFolderNames)
        return Prompt(system: system, user: user)
    }

    // MARK: - Private

    private static func buildSystem() -> String {
        """
        You are a browser tab organizer. You will receive a numbered list of tabs. \
        Respond with ONLY a JSON object, no other text.

        JSON schema:
        {
          "groups": [{"name": "Topic", "tabs": [1, 2, 5]}],
          "renames": [{"tab": 1, "name": "Clean Title"}],
          "sort": [3, 1, 2, 5, 4],
          "duplicates": [{"keep": 1, "close": [3]}]
        }

        GROUPING rules:
        - Group tabs by topic or purpose, NOT by website
        - Group names must be 1-5 words
        - A tab can only be in one group
        - Groups create folders in the tab list. Each group becomes a named folder containing its tabs

        RENAME rules:
        - Only rename tabs with ugly titles (long product names, site prefixes, tracking params)
        - Good rename: "Amazon.com: Anker USB-C Hub 7-in-1 Docking Station - Electronics" -> "Anker USB-C Hub"
        - Do NOT rename tabs that already have clean short titles

        DUPLICATE rules — be very strict:
        - A duplicate is ONLY when two tabs point to the exact same page
        - Same website does NOT mean duplicate. github.com/repo-a and github.com/repo-b are NOT duplicates
        - facebook.com/profile and facebook.com/messages are NOT duplicates
        - Only mark as duplicate if the URLs are identical or nearly identical (e.g. with/without trailing slash)

        SORT rules:
        - Order tabs so related topics are adjacent

        Example input:
        1. "GitHub - anthropics/claude-code" | github.com/anthropics/claude-code
        2. "Amazon.com: Anker USB-C Hub 7-in-1..." | amazon.com/dp/B08X...
        3. "Best USB-C Hubs 2026 - Wirecutter" | nytimes.com/wirecutter/reviews/best-usb-c-hubs
        4. "GitHub - anthropics/claude-code: CLI" | github.com/anthropics/claude-code
        5. "Swift Documentation" | developer.apple.com/documentation/swift

        Example output:
        {"groups":[{"name":"Shopping","tabs":[2,3]},{"name":"Development","tabs":[1,5]}],"renames":[{"tab":2,"name":"Anker USB-C Hub"}],"sort":[1,4,5,2,3],"duplicates":[{"keep":1,"close":[4]}]}
        """
    }

    @MainActor
    private static func buildUser(
        tabs: [TabInput],
        spaceName: String,
        existingFolderNames: [String]
    ) -> String {
        let capped = Array(tabs.prefix(maxTabs))
        let count = capped.count

        // Header line
        var header = "Space \"\(spaceName)\", \(count) unfiled tab\(count == 1 ? "" : "s")"
        if !existingFolderNames.isEmpty {
            let names = existingFolderNames.joined(separator: ", ")
            header += ", \(existingFolderNames.count) existing folder\(existingFolderNames.count == 1 ? "" : "s") (\(names))"
        }
        header += ":"

        // Tab lines
        let lines = capped.map { input in
            let title = input.tab.displayName
            let shortURL = shortenURL(input.tab.url)
            return "\(input.index). \"\(title)\" | \(shortURL)"
        }

        return ([header] + lines).joined(separator: "\n")
    }

    /// Shorten a URL to `host + path prefix` with a max of 60 characters of path to save tokens.
    private static func shortenURL(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path  // e.g. "/dp/B08X1234/ref=..."

        if path.isEmpty || path == "/" {
            return host
        }

        let maxPathLength = 60
        if path.count <= maxPathLength {
            return host + path
        }

        let truncated = String(path.prefix(maxPathLength))
        return host + truncated + "..."
    }
}
