//
//  NewDocumentTarget.swift
//  Nook
//
//  Represents where new documents should open.
//

import Foundation

enum NewDocumentTarget: String, CaseIterable, Identifiable {
    case tab
    case window
    case space

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: return "New Tab"
        case .window: return "New Window"
        case .space: return "New Space"
        }
    }
}
