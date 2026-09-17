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
