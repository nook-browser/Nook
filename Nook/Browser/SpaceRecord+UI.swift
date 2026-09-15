//
//  SpaceRecord+UI.swift
//  Nook
//

import AppKit
import NookTabsCore
import SwiftUI

extension SpaceRecord {
    /// The space's accent color, used for its icon, switcher item and folder icons.
    var accentColor: Color { Color(hex: accentHex) }

    var accentNSColor: NSColor { NSColor(hex: accentHex) ?? .controlAccentColor }
}
