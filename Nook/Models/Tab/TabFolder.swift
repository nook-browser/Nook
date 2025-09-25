//
//  TabFolder.swift
//  Nook
//
//  Created by Claude on 2025-09-24.
//

import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
public class TabFolder: NSObject, Identifiable, ObservableObject {
    public let id: UUID
    var name: String
    var spaceId: UUID
    var isOpen: Bool = false
    var icon: String = "folder"
    var index: Int
    var color: NSColor

    init(
        id: UUID = UUID(),
        name: String,
        spaceId: UUID,
        icon: String = "folder",
        color: NSColor = .controlAccentColor,
        index: Int = 0
    ) {
        self.id = id
        self.name = name
        self.spaceId = spaceId
        self.icon = icon
        self.color = color
        self.index = index
        super.init()
    }
}