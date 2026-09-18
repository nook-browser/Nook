//
//  LegacyTabImport.swift
//  Nook
//
//  Builds the first tab tree from a 1.0.x SwiftData store so a user arriving from an old bundle
//  id keeps their spaces, folders and tabs, not only their cookies. Profiles map as ProfileMerge
//  maps them: a profile's first space takes the profile's id so its data store follows it.
//

import Foundation
import SwiftData
import NookTabsCore

enum LegacyTabImport {
    static func tree(from context: ModelContext, now: Date = Date()) -> TabTree? {
        let spaces = (try? context.fetch(FetchDescriptor<SpaceEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        guard !spaces.isEmpty else { return nil }
        let profiles = (try? context.fetch(FetchDescriptor<ProfileEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        let folders = (try? context.fetch(FetchDescriptor<FolderEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        let tabs = (try? context.fetch(FetchDescriptor<TabEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []

        var tree = TabTree()
        var spaceID: [UUID: UUID] = [:]            // old space id -> id in the tree
        var firstSpace: [UUID: UUID] = [:]         // profile id -> its first space in the tree
        let fallbackProfile = profiles.first?.id

        for space in spaces {
            let profile = space.profileId ?? fallbackProfile
            var id = space.id
            if let profile, firstSpace[profile] == nil {
                id = profile
                firstSpace[profile] = id
            }
            spaceID[space.id] = id
            tree.createSpace(id: id, name: space.name, icon: space.icon,
                             accentHex: SpaceGradient.decode(space.gradientData).primaryColorHex,
                             after: tree.orderedSpaces.last?.id, now: now)
        }

        var folderIDs = Set<UUID>()
        for folder in folders {
            guard let space = spaceID[folder.spaceId] else { continue }
            let parent: Parent = folder.isRegular ? .tabs(spaceID: space) : .pinned(spaceID: space)
            if (try? tree.createFolder(id: folder.id, title: folder.name, in: parent,
                                       after: tree.children(of: parent).last?.id, now: now)) != nil {
                folderIDs.insert(folder.id)
            }
        }

        for tab in tabs {
            let parent: Parent
            if let folder = tab.folderId, folderIDs.contains(folder) {
                parent = .folder(itemID: folder)
            } else if tab.isPinned {
                guard let space = (tab.profileId ?? fallbackProfile).flatMap({ firstSpace[$0] })
                        ?? tree.orderedSpaces.first?.id else { continue }
                parent = .favorites(spaceID: space)
            } else if let space = tab.spaceId.flatMap({ spaceID[$0] }) {
                parent = tab.isSpacePinned ? .pinned(spaceID: space) : .tabs(spaceID: space)
            } else {
                continue
            }
            let synced = tab.isPinned || tab.isSpacePinned
            let urlString = synced ? (tab.pinnedURLString ?? tab.urlString) : (tab.currentURLString ?? tab.urlString)
            guard let url = URL(string: urlString) else { continue }
            guard (try? tree.createTab(id: tab.id, url: url, title: tab.name, in: parent,
                                       after: tree.children(of: parent).last?.id, now: now)) != nil else { continue }
            if let custom = tab.displayNameOverride, !custom.isEmpty {
                _ = try? tree.rename(tab.id, customTitle: custom, now: now)
            }
        }
        return tree.items.isEmpty ? nil : tree
    }
}
