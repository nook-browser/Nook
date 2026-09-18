// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SponsorBlockCategory.swift
//  NookSettings
//
//  The persisted half of SponsorBlock: which categories exist and how each one
//  is skipped. Segments and API responses are runtime and live in the app.
//

import Foundation

// MARK: - Category

public enum SponsorBlockCategory: String, Codable, CaseIterable, Identifiable {
    case sponsor
    case selfpromo
    case exclusive_access
    case interaction
    case intro
    case outro
    case preview
    case filler
    case music_offtopic
    case poi_highlight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sponsor: return "Sponsor"
        case .selfpromo: return "Self-Promotion"
        case .exclusive_access: return "Exclusive Access"
        case .interaction: return "Interaction Reminder"
        case .intro: return "Intermission/Intro"
        case .outro: return "Endcards/Credits"
        case .preview: return "Preview/Recap"
        case .filler: return "Filler"
        case .music_offtopic: return "Non-Music Section"
        case .poi_highlight: return "Highlight"
        }
    }

    public var description: String {
        switch self {
        case .sponsor: return "Paid promotion, paid referral, or direct advertisement"
        case .selfpromo: return "Promoting a product or service that is directly related to the creator"
        case .exclusive_access: return "Showcasing a product or service in exchange for access"
        case .interaction: return "Asking for likes, subscriptions, or comments"
        case .intro: return "Intermission or intro animation"
        case .outro: return "Endcards, credits, or outro"
        case .preview: return "Preview of upcoming content or recap of previous episodes"
        case .filler: return "Tangential scenes that are not directly related to the main topic"
        case .music_offtopic: return "Non-music sections in music videos"
        case .poi_highlight: return "The most important point of the video"
        }
    }

    /// Hex color matching SponsorBlock's official category colors
    public var color: String {
        switch self {
        case .sponsor: return "#00D400"
        case .selfpromo: return "#FFFF00"
        case .exclusive_access: return "#008A5C"
        case .interaction: return "#CC00FF"
        case .intro: return "#00FFFF"
        case .outro: return "#0202ED"
        case .preview: return "#008FD6"
        case .filler: return "#7300FF"
        case .music_offtopic: return "#FF9900"
        case .poi_highlight: return "#FF1684"
        }
    }
}

// MARK: - Skip Option (per-category behavior)

public enum SponsorBlockSkipOption: String, Codable, CaseIterable, Identifiable {
    case autoSkip = "auto"
    case manualSkip = "manual"
    case disabled = "disabled"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoSkip: return "Auto Skip"
        case .manualSkip: return "Show Skip Button"
        case .disabled: return "Off"
        }
    }
}

extension SponsorBlockCategory {
    /// Default skip option per category, matching SponsorBlock's defaults.
    public var defaultSkipOption: SponsorBlockSkipOption {
        switch self {
        case .sponsor: return .autoSkip
        case .poi_highlight: return .manualSkip
        default: return .disabled
        }
    }

    /// Builds the full default options dictionary.
    public static var defaultCategoryOptions: [String: String] {
        var options: [String: String] = [:]
        for category in Self.allCases {
            options[category.rawValue] = category.defaultSkipOption.rawValue
        }
        return options
    }
}
