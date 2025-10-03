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
    var name: String {
        didSet { objectWillChange.send() }
    }
    var spaceId: UUID
    var isOpen: Bool = false {
        didSet { objectWillChange.send() }
    }
    var icon: String = "folder" {
        didSet { objectWillChange.send() }
    }
    var index: Int {
        didSet { objectWillChange.send() }
    }
    var color: NSColor {
        didSet { objectWillChange.send() }
    }

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
