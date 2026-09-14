//
//  Space.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI
 
// Gradient configuration for spaces
// See: SpaceGradient.swift

@MainActor
@Observable
public class Space: NSObject, Identifiable {
    public let id: UUID
    var name: String
    var icon: String
    var color: NSColor
    var gradient: SpaceGradient

    /// Hex of the space's accent color (the gradient's primary node).
    var accentHex: String { gradient.primaryColorHex }

    /// The space's accent color, used for its icon and switcher item.
    var accentColor: Color { gradient.primaryColor }

    var activeTabId: UUID?
    var profileId: UUID?
    
    /// Whether this space belongs to an ephemeral/incognito profile
    var isEphemeral: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.grid.2x2",
        color: NSColor = .controlAccentColor,
        gradient: SpaceGradient = .default,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.gradient = gradient
        self.activeTabId = nil
        self.profileId = profileId
        super.init()
    }
}
