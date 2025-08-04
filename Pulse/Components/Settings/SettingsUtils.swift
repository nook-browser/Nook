//
//  SettingsUtils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation

enum SettingsTabs {
    case general
    case spaces
    case profiles
    case shortcuts
    case advanced
    
    var name: String {
        switch self {
        case .general: return "General"
        case .spaces: return "Spaces"
        case .profiles: return "Profiles"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        }
    }
}
