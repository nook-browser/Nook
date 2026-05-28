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
    var folderId: UUID? // Folder membership for tabs within spacepinned area

    // Display name override (user or AI-assigned custom tab name)
    var displayNameOverride: String?

    // Navigation state tracking
    var currentURLString: String? // The actual current page URL (may differ from urlString after navigation)
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    // Pinned tab home URL (the URL the tab resets to)
    var pinnedURLString: String?

    init(
        id: UUID,
        urlString: String,
        name: String,
        isPinned: Bool,
        isSpacePinned: Bool = false,
        index: Int,
        spaceId: UUID?,
        profileId: UUID? = nil,
        folderId: UUID? = nil,
        displayNameOverride: String? = nil,
        currentURLString: String? = nil,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        pinnedURLString: String? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.isPinned = isPinned
        self.isSpacePinned = isSpacePinned
        self.index = index
        self.spaceId = spaceId
        self.profileId = profileId
        self.folderId = folderId
        self.displayNameOverride = displayNameOverride

        // For backward compatibility, if currentURLString is not provided, use urlString
        self.currentURLString = currentURLString ?? urlString
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pinnedURLString = pinnedURLString
    }
}

@Model
final class FolderEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var color: String
    var spaceId: UUID
    var isOpen: Bool
    var index: Int
    var isRegular: Bool

    init(
        id: UUID,
        name: String,
        icon: String,
        color: String,
        spaceId: UUID,
        isOpen: Bool,
        index: Int,
        isRegular: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.spaceId = spaceId
        self.isOpen = isOpen
        self.index = index
        self.isRegular = isRegular
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
