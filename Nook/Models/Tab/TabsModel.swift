//
//  TabsModel.swift
//  Nook
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
    // Profile association for global pinned tabs (essentials). Optional for migration compatibility.
    var profileId: UUID?

    init(
        id: UUID,
        urlString: String,
        name: String,
        isPinned: Bool,
        isSpacePinned: Bool = false,
        index: Int,
        spaceId: UUID?,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.isPinned = isPinned
        self.isSpacePinned = isSpacePinned
        self.index = index
        self.spaceId = spaceId
        self.profileId = profileId
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
