//
//  SettingsValueTypes.swift
//  NookSettings
//
//  Value types NookSettingsService stores, lifted out of the app so the
//  settings package stays Foundation-only.
//

import Foundation

// MARK: - Search Provider

public enum SearchProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case google
    case duckDuckGo
    case bing
    case brave
    case yahoo
    case perplexity
    case unduck
    case ecosia
    case kagi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave"
        case .yahoo: return "Yahoo"
        case .perplexity: return "Perplexity"
        case .unduck: return "Unduck"
        case .ecosia: return "Ecosia"
        case .kagi: return "Kagi"
        }
    }

    public var host: String {
        switch self {
        case .google: return "www.google.com"
        case .duckDuckGo: return "duckduckgo.com"
        case .bing: return "www.bing.com"
        case .brave: return "search.brave.com"
        case .yahoo: return "search.yahoo.com"
        case .perplexity: return "www.perplexity.ai"
        case .unduck: return "duckduckgo.com"
        case .ecosia: return "www.ecosia.org"
        case .kagi: return "kagi.com"
        }
    }

    public var queryTemplate: String {
        switch self {
        case .google:
            return "https://www.google.com/search?q=%@"
        case .duckDuckGo:
            return "https://duckduckgo.com/?q=%@"
        case .bing:
            return "https://www.bing.com/search?q=%@"
        case .brave:
            return "https://search.brave.com/search?q=%@"
        case .yahoo:
            return "https://search.yahoo.com/search?p=%@"
        case .perplexity:
            return "https://www.perplexity.ai/search?q=%@"
        case .unduck:
            return "https://unduck.link?q=%@"
        case .ecosia:
            return "https://www.ecosia.org/search?q=%@"
        case .kagi:
            return "https://kagi.com/search?q=%@"
        }
    }
}

// MARK: - Sidebar Position

public enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    public var icon: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        }
    }
}

// MARK: - YouTube Home Sections

/// Home feed shelves the user can hide. Shelf types are computed in YouTube's JS, not reflected
/// as attributes, so each one is matched by what it contains (see `YouTubeTweaks`).
public enum YouTubeHomeSection: String, CaseIterable, Identifiable {
    case posts
    case playables
    case otherShelves
    case surveys
    case filterChips

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .posts: return "Posts"
        case .playables: return "Playables"
        case .otherShelves: return "News and topic shelves"
        case .surveys: return "Surveys and banners"
        case .filterChips: return "Topic filter bar"
        }
    }
}
