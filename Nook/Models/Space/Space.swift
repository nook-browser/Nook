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
    var activeTabId: UUID?
    var profileId: UUID?

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
