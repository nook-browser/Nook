// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionSets.swift
//  NookSettings
//
//  Which extension set each profile runs. A set is one extension controller with its own
//  installs and data; a profile is a data store id. Profiles with no entry use the default set.
//

import Foundation

public struct ExtensionSetChoice: Equatable, Sendable {
    public let set: UUID
    /// Member profile ids, in the order the caller listed profiles.
    public let members: [UUID]
}

public struct ExtensionSets: Codable, Equatable, Sendable {
    /// Profile id to set id, for profiles outside the default set.
    public var membership: [UUID: UUID] = [:]
    /// Profile id to the sets it was the last member of, oldest first. Separate brings back the
    /// newest, and none is deleted before its profile is.
    public var dormant: [UUID: [UUID]] = [:]

    public init() {}

    public func setID(forProfile profile: UUID, defaultSet: UUID) -> UUID {
        membership[profile] ?? defaultSet
    }

    /// Sets with at least one member among `profiles`, ordered by their first member.
    public func choices(profiles: [UUID], defaultSet: UUID) -> [ExtensionSetChoice] {
        var order: [UUID] = []
        var members: [UUID: [UUID]] = [:]
        for profile in profiles {
            let set = setID(forProfile: profile, defaultSet: defaultSet)
            if members[set] == nil { order.append(set) }
            members[set, default: []].append(profile)
        }
        return order.map { ExtensionSetChoice(set: $0, members: members[$0]!) }
    }

    /// Moves `profile` into `set`. `profiles` is every profile there is: the default set's members
    /// are the ones with no entry. Returns sets nothing refers to any more, whose data can go.
    @discardableResult
    public mutating func sync(_ profile: UUID, with set: UUID, profiles: [UUID], defaultSet: UUID) -> [UUID] {
        let before = referenced
        leave(profile, profiles: profiles, defaultSet: defaultSet)
        if set != defaultSet { membership[profile] = set }
        return garbage(before, defaultSet: defaultSet)
    }

    /// Gives `profile` a set of its own: its current one if it is already alone in it, else the
    /// one it last left, else a new one. Returns the set id and the sets that became garbage.
    /// A profile alone in the default set still moves out: Separate starts with no extensions.
    public mutating func separate(_ profile: UUID, profiles: [UUID], defaultSet: UUID) -> (set: UUID, garbage: [UUID]) {
        let current = setID(forProfile: profile, defaultSet: defaultSet)
        if current != defaultSet, !isUsed(current, besides: profile, profiles: profiles, defaultSet: defaultSet) {
            return (current, [])
        }
        let before = referenced
        let restored = dormant[profile]?.last { set in
            !isUsed(set, besides: profile, profiles: profiles, defaultSet: defaultSet)
        }
        leave(profile, profiles: profiles, defaultSet: defaultSet)
        let set = restored ?? UUID()
        forget(set, of: profile)
        if set != defaultSet { membership[profile] = set }
        return (set, garbage(before, defaultSet: defaultSet))
    }

    /// Forgets a deleted profile. Returns the sets whose data can go.
    public mutating func profileDeleted(_ profile: UUID, defaultSet: UUID) -> [UUID] {
        let before = referenced
        membership[profile] = nil
        dormant[profile] = nil
        return garbage(before, defaultSet: defaultSet)
    }

    private var referenced: Set<UUID> { Set(membership.values).union(dormant.values.joined()) }

    private mutating func forget(_ set: UUID, of profile: UUID) {
        dormant[profile]?.removeAll { $0 == set }
        if dormant[profile]?.isEmpty == true { dormant[profile] = nil }
    }

    private func garbage(_ before: Set<UUID>, defaultSet: UUID) -> [UUID] {
        before.subtracting(referenced).subtracting([defaultSet]).sorted { $0.uuidString < $1.uuidString }
    }

    private func isUsed(_ set: UUID, besides profile: UUID, profiles: [UUID], defaultSet: UUID) -> Bool {
        set == defaultSet
            ? profiles.contains { $0 != profile && membership[$0] == nil }
            : membership.contains { $0.key != profile && $0.value == set }
    }

    /// Takes `profile` out of its set; a set it leaves empty, the default included, joins its
    /// dormant sets, so the extensions it walked away from can come back.
    private mutating func leave(_ profile: UUID, profiles: [UUID], defaultSet: UUID) {
        let current = setID(forProfile: profile, defaultSet: defaultSet)
        membership[profile] = nil
        guard !isUsed(current, besides: profile, profiles: profiles, defaultSet: defaultSet) else { return }
        forget(current, of: profile)
        dormant[profile, default: []].append(current)
    }
}
