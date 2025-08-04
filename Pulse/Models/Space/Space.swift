//
//  Space.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI

@MainActor
@Observable
public class Space: NSObject, Identifiable {
    public let id: UUID
    var name: String
    var icon: String
    var color: NSColor

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.grid.2x2",
        color: NSColor = .controlAccentColor,
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        super.init()
    }
}
