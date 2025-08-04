//
//  SpaceModels.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Foundation
import SwiftData

@Model
final class SpaceEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var index: Int

    init(id: UUID, name: String, icon: String, index: Int) {
        self.id = id
        self.name = name
        self.icon = icon
        self.index = index
    }
}
