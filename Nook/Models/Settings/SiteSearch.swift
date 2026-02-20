//
//  SiteSearch.swift
//  Nook
//
//  Site search (Tab-to-Search) data model and matching logic
//

import SwiftUI

struct SiteSearchEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var domain: String
    var searchURLTemplate: String
    var colorHex: String

    var color: Color {
        Color(hex: colorHex)
    }

    init(id: UUID = UUID(), name: String, domain: String, searchURLTemplate: String, colorHex: String) {
        self.id = id
        self.name = name
        self.domain = domain
        self.searchURLTemplate = searchURLTemplate
        self.colorHex = colorHex
    }

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        var template = searchURLTemplate
        if !template.hasPrefix("http://") && !template.hasPrefix("https://") {
            template = "https://" + template
        }
        let urlString = template.replacingOccurrences(of: "{query}", with: encoded)
        return URL(string: urlString)
    }

    func matches(prefix: String) -> Bool {
        let lower = prefix.lowercased()
        return name.lowercased().hasPrefix(lower) || domain.lowercased().hasPrefix(lower)
    }

    // MARK: - Defaults

    static let defaultSites: [SiteSearchEntry] = [
        SiteSearchEntry(
            name: "YouTube", domain: "youtube.com",
            searchURLTemplate: "https://www.youtube.com/results?search_query={query}",
            colorHex: "#E62617"
        ),
        SiteSearchEntry(
            name: "GitHub", domain: "github.com",
            searchURLTemplate: "https://github.com/search?q={query}",
            colorHex: "#8B4DD9"
        ),
        SiteSearchEntry(
            name: "Reddit", domain: "reddit.com",
            searchURLTemplate: "https://www.reddit.com/search/?q={query}",
            colorHex: "#FF7300"
        ),
        SiteSearchEntry(
            name: "X", domain: "x.com",
            searchURLTemplate: "https://x.com/search?q={query}",
            colorHex: "#666666"
        ),
        SiteSearchEntry(
            name: "Wikipedia", domain: "wikipedia.org",
            searchURLTemplate: "https://en.wikipedia.org/w/index.php?search={query}",
            colorHex: "#737373"
        ),
        SiteSearchEntry(
            name: "Amazon", domain: "amazon.com",
            searchURLTemplate: "https://www.amazon.com/s?k={query}",
            colorHex: "#FF8C00"
        ),
        SiteSearchEntry(
            name: "Twitch", domain: "twitch.tv",
            searchURLTemplate: "https://www.twitch.tv/search?term={query}",
            colorHex: "#9146EB"
        ),
        SiteSearchEntry(
            name: "Spotify", domain: "open.spotify.com",
            searchURLTemplate: "https://open.spotify.com/search/{query}",
            colorHex: "#1DB954"
        ),
        SiteSearchEntry(
            name: "Stack Overflow", domain: "stackoverflow.com",
            searchURLTemplate: "https://stackoverflow.com/search?q={query}",
            colorHex: "#F28C0D"
        ),
        SiteSearchEntry(
            name: "Perplexity", domain: "perplexity.ai",
            searchURLTemplate: "https://www.perplexity.ai/search?q={query}",
            colorHex: "#20B8CD"
        ),
        SiteSearchEntry(
            name: "ChatGPT", domain: "chatgpt.com",
            searchURLTemplate: "https://chatgpt.com/?q={query}",
            colorHex: "#10A37F"
        ),
        SiteSearchEntry(
            name: "Claude", domain: "claude.ai",
            searchURLTemplate: "https://claude.ai/new?q={query}",
            colorHex: "#D97757"
        ),
        SiteSearchEntry(
            name: "Gemini", domain: "gemini.google.com",
            searchURLTemplate: "https://gemini.google.com/app?q={query}",
            colorHex: "#8E75B2"
        ),
        SiteSearchEntry(
            name: "Grok", domain: "grok.com",
            searchURLTemplate: "https://grok.com/?q={query}",
            colorHex: "#000000"
        ),
    ]

    static func match(for text: String, in sites: [SiteSearchEntry]) -> SiteSearchEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return sites.first { $0.matches(prefix: trimmed) }
    }
}

