//
//  TabsModel.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import Foundation
import SwiftData

@Model
final class TabEntity {
    @Attribute(.unique) var id: UUID
    var urlString: String
    var name: String
    var isPinned: Bool // Global pinned (essentials)
    var isSpacePinned: Bool = false // Space-level pinned
    var index: Int
    var spaceId: UUID?

    init(
        id: UUID,
        urlString: String,
        name: String,
        isPinned: Bool,
        isSpacePinned: Bool = false,
        index: Int,
        spaceId: UUID?
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.isPinned = isPinned
        self.isSpacePinned = isSpacePinned
        self.index = index
        self.spaceId = spaceId
    }
}

@Model
final class TabsStateEntity {
    var currentTabID: UUID?
    var currentSpaceID: UUID?

    init(currentTabID: UUID?, currentSpaceID: UUID?) {
        self.currentTabID = currentTabID
        self.currentSpaceID = currentSpaceID
    }
}
