//
//  SettingsUtils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation

enum SettingsTabs: Hashable, CaseIterable {
    case general
    case privacy
    case profiles
    case shortcuts
    case extensions
    case advanced
    
    // Ordered list for horizontal tab bar
    static var ordered: [SettingsTabs] {
        return [.general, .privacy, .profiles, .shortcuts, .extensions, .advanced]
    }
    
    var name: String {
        switch self {
        case .general: return "General"
        case .privacy: return "Privacy"
        case .profiles: return "Profiles"
        case .shortcuts: return "Shortcuts"
        case .extensions: return "Extensions"
        case .advanced: return "Advanced"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "lock.shield"
        case .profiles: return "person.crop.circle"
        case .shortcuts: return "keyboard"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}
