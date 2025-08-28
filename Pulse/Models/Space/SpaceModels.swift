//
//  SpaceModels.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import Foundation
import SwiftData
import SwiftUI

// Stores Space persistence, including gradient configuration

@Model
final class SpaceEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var index: Int
    var gradientData: Data = SpaceGradient.default.encoded ?? Data()

    init(id: UUID, name: String, icon: String, index: Int, gradientData: Data = SpaceGradient.default.encoded ?? Data()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.index = index
        self.gradientData = gradientData
    }
}
