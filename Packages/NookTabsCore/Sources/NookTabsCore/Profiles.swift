// Licensed under GPL-3.0. See LICENSE.
//
//  Profiles.swift
//  NookTabsCore
//
//  A profile is the spaces that share one website data store: logins, cookies and history.
//  It has no record of its own. Its id is the store id and its name rides on its spaces.
//

import Foundation

public struct ProfileSummary: Identifiable, Equatable, Sendable {
    /// The data store id.
    public let id: UUID
    public let name: String
    public let spaceIDs: [UUID]
}

extension TabTree {
    /// Every profile in space order. The Agent space borrows a store and belongs to none.
    public var profiles: [ProfileSummary] {
        var order: [UUID] = []
        var members: [UUID: [SpaceRecord]] = [:]
        for space in orderedSpaces where !space.isAgent {
            let store = space.dataStoreID ?? space.id
            if members[store] == nil { order.append(store) }
            members[store, default: []].append(space)
        }
        return order.map { store in
            let spaces = members[store] ?? []
            // ponytail: each space carries the name; the first set one wins if two disagree after a sync.
            let name = spaces.lazy.compactMap(\.profileName).first ?? spaces.first?.name ?? ""
            return ProfileSummary(id: store, name: name, spaceIDs: spaces.map(\.id))
        }
    }

    public func profile(ofSpace spaceID: UUID) -> ProfileSummary? {
        profiles.first { $0.spaceIDs.contains(spaceID) }
    }

    /// Moves a space into the profile whose store is `storeID`, or into a new profile when nil.
    @discardableResult
    public mutating func setProfile(_ spaceID: UUID, to storeID: UUID?, name: String? = nil, now: Date = Date()) throws -> Change {
        guard var target = space(spaceID), !target.isAgent else { throw TreeError.missingSpace }
        // Never back to nil: the space's own id may still be the store of spaces it left behind.
        target.dataStoreID = storeID ?? UUID()
        target.profileName = storeID == nil ? name : nil
        target.modifiedAt = now
        var change = Change()
        record(&change, space: target)
        return change
    }

    @discardableResult
    public mutating func renameProfile(_ storeID: UUID, to name: String, now: Date = Date()) throws -> Change {
        guard let profile = profiles.first(where: { $0.id == storeID }) else { throw TreeError.missingSpace }
        var change = Change()
        for id in profile.spaceIDs {
            guard var space = space(id), space.profileName != name else { continue }
            space.profileName = name
            space.modifiedAt = now
            record(&change, space: space)
        }
        return change
    }
}
