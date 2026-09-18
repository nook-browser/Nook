// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SpaceRecord+UI.swift
//  NookWeb
//

import NookTabsCore
import SwiftUI

extension SpaceRecord {
    /// The space's accent color, used for its icon, switcher item and folder icons.
    public var accentColor: Color { Color(platformColor: accentNSColor) }

    public var accentNSColor: PlatformColor { PlatformColor.fromHex(accentHex) ?? .defaultAccent }
}
