//
//  SettingsUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation
import SwiftUI

enum SettingsTabs: String, Hashable, CaseIterable {
    case general
    case appearance
    case ai
    case privacy
    case adBlocker
    case youTube
    case socialMedia
    case airTrafficControl
    case profiles
    case shortcuts
    case extensions
    case advanced

    var name: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .ai: return "AI"
        case .privacy: return "Privacy"
        case .adBlocker: return "Ad Blocker"
        case .youTube: return "YouTube"
        case .socialMedia: return "Social Media"
        case .airTrafficControl: return "Air Traffic Control"
        case .profiles: return "Profiles"
        case .shortcuts: return "Shortcuts"
        case .extensions: return "Extensions"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .ai: return "sparkles"
        case .privacy: return "lock.shield"
        case .adBlocker: return "shield.lefthalf.filled"
        case .youTube: return "play.rectangle"
        case .socialMedia: return "photo.on.rectangle"
        case .airTrafficControl: return "arrow.triangle.branch"
        case .profiles: return "person.crop.circle"
        case .shortcuts: return "keyboard"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .ai: return .purple
        case .privacy: return .blue
        case .adBlocker: return .green
        case .youTube: return .red
        case .socialMedia: return .pink
        case .airTrafficControl: return .mint
        case .profiles: return .cyan
        case .shortcuts: return .indigo
        case .extensions: return .teal
        case .advanced: return .secondary
        }
    }

    /// Sidebar groups, separated by visual spacing. A titled group gets a section header.
    static var sidebarGroups: [(title: String?, tabs: [SettingsTabs])] {
        var groups: [(title: String?, tabs: [SettingsTabs])] = [
            (nil, [.general, .appearance]),
            (nil, [.ai]),
            (nil, [.privacy, .adBlocker, .airTrafficControl]),
            (nil, [.profiles, .shortcuts, .extensions]),
            ("Tweaks", [.youTube, .socialMedia]),
        ]
        #if DEBUG
        groups.append((nil, [.advanced]))
        #endif
        return groups
    }
}
