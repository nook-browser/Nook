//
//  SettingsUtils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation

enum SettingsTabs {
    case general
    case privacy
    case spaces
    case profiles
    case shortcuts
    case extensions
    case advanced
    
    var name: String {
        switch self {
        case .general: return "General"
        case .privacy: return "Privacy"
        case .spaces: return "Spaces"
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
        case .spaces: return "folder"
        case .profiles: return "person.circle"
        case .shortcuts: return "keyboard"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}
