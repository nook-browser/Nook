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
    case sponsorBlock
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
        case .sponsorBlock: return "SponsorBlock"
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
        case .sponsorBlock: return "forward.end.alt"
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
        case .sponsorBlock: return .orange
        case .airTrafficControl: return .mint
        case .profiles: return .cyan
        case .shortcuts: return .indigo
        case .extensions: return .teal
        case .advanced: return .secondary
        }
    }

    /// Sidebar groups, separated by visual spacing. Each inner array is one group.
    static var sidebarGroups: [[SettingsTabs]] {
        var groups: [[SettingsTabs]] = [
            [.general, .appearance],
            [.ai],
            [.privacy, .adBlocker, .sponsorBlock, .airTrafficControl],
            [.profiles, .shortcuts, .extensions],
        ]
        #if DEBUG
        groups.append([.advanced])
        #endif
        return groups
    }
}
