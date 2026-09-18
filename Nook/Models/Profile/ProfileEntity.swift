// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ProfileEntity.swift
//  Nook
//
//  SwiftData model for persisting Profiles.
//

import Foundation
import SwiftData

@Model
final class ProfileEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var index: Int

    init(
        id: UUID = UUID(),
        name: String = "Default Profile",
        icon: String = "person.crop.circle",
        index: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.index = index
    }
}

