//
//  TabFolder.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import Foundation
import SwiftUI
import Combine

@MainActor
public class TabFolder: NSObject, Identifiable, ObservableObject {
    public let id: UUID
    @Published var name: String
    var spaceId: UUID
    @Published var isOpen: Bool = false
    @Published var icon: String = "folder"
    @Published var index: Int
    @Published var color: NSColor

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
