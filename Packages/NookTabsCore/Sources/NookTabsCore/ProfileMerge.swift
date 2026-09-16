import Foundation

/// One-shot migration of the format-1 files, which had profiles above spaces, into format 2,
/// where a space is the whole thing.
///
/// Each profile's first space becomes a space carrying the profile's id, so the website data store
/// keyed by that id keeps its cookies and logins. The profile's remaining spaces stay as they are
/// and get their own (empty) data stores. Only the `parent` of an item and the space list change
/// shape, so everything else is copied through as raw JSON and cannot be lost to a field this
/// migration does not know about.
enum ProfileMerge {
    struct Result {
        var structure: Data
        var device: Data?
        /// Old space id -> merged space id, for ids the app stores outside these files.
        var spaceIDs: [UUID: UUID]
    }

    private struct LegacyProfile: Codable {
        let id: UUID
        var name: String
        var icon: String
        var order: OrderKey
        var modifiedAt: Date
        var deletedAt: Date?
    }

    private struct LegacySpace: Codable {
        let id: UUID
        var profileID: UUID
        var name: String
        var icon: String
        var accentHex: String
        var order: OrderKey
        var modifiedAt: Date
        var deletedAt: Date?
    }

    /// nil when structure.json is not a readable format-1 file.
    static func migrate(structure: Data, device: Data?) -> Result? {
        guard var root = (try? JSONSerialization.jsonObject(with: structure)) as? [String: Any],
              let profileJSON = root["profiles"], let spaceJSON = root["spaces"] else { return nil }
        let decoder = JSONDecoder()
        guard let profileData = try? JSONSerialization.data(withJSONObject: profileJSON),
              let spaceData = try? JSONSerialization.data(withJSONObject: spaceJSON),
              let profiles = try? decoder.decode([LegacyProfile].self, from: profileData),
              let spaces = try? decoder.decode([LegacySpace].self, from: spaceData) else { return nil }

        let (merged, spaceIDs) = mergedSpaces(profiles: profiles, spaces: spaces)
        guard merged.contains(where: { $0.deletedAt == nil }),
              let mergedData = try? JSONEncoder().encode(merged),
              let mergedJSON = try? JSONSerialization.jsonObject(with: mergedData) else { return nil }

        root["formatVersion"] = TabStore.formatVersion
        root["profiles"] = nil
        root["spaces"] = mergedJSON
        root["items"] = rewriteItems(root["items"], spaceIDs: spaceIDs)
        guard let structureOut = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return Result(structure: structureOut, device: rewriteDevice(device, spaceIDs: spaceIDs), spaceIDs: spaceIDs)
    }

    // MARK: - Spaces

    /// The merged space list in profile order, and the old-to-new space id map.
    private static func mergedSpaces(profiles: [LegacyProfile], spaces: [LegacySpace]) -> ([SpaceRecord], [UUID: UUID]) {
        let live = spaces.filter { $0.deletedAt == nil }.sorted(by: order)
        var byProfile: [UUID: [LegacySpace]] = [:]
        for space in live { byProfile[space.profileID, default: []].append(space) }

        var merged: [SpaceRecord] = []
        var map: [UUID: UUID] = [:]
        func add(_ id: UUID, _ name: String, _ icon: String, _ accent: String, _ modified: Date, deleted: Date? = nil) {
            // The order is a placeholder; the whole list is renumbered once it is complete.
            merged.append(SpaceRecord(id: id, name: name, icon: icon, accentHex: accent,
                                      order: OrderKey("V"), modifiedAt: modified, deletedAt: deleted))
        }

        for profile in profiles.filter({ $0.deletedAt == nil }).sorted(by: order) {
            let owned = byProfile.removeValue(forKey: profile.id) ?? []
            guard let first = owned.first else {
                // A profile with no space still becomes one, so its favorites have a home.
                add(profile.id, profile.name, "house", defaultAccent, profile.modifiedAt)
                map[profile.id] = profile.id
                continue
            }
            map[first.id] = profile.id
            add(profile.id, first.name, first.icon, first.accentHex, max(first.modifiedAt, profile.modifiedAt))
            for other in owned.dropFirst() {
                map[other.id] = other.id
                add(other.id, other.name, other.icon, other.accentHex, other.modifiedAt)
            }
        }
        // Spaces whose profile was already gone keep their own id and join the end.
        for space in live where map[space.id] == nil {
            map[space.id] = space.id
            add(space.id, space.name, space.icon, space.accentHex, space.modifiedAt)
        }
        // Tombstones are kept so a delete still propagates; repair purges them when they expire.
        for space in spaces where space.deletedAt != nil {
            guard map[space.id] == nil else { continue }
            map[space.id] = space.id
            add(space.id, space.name, space.icon, space.accentHex, space.modifiedAt, deleted: space.deletedAt)
        }

        let keys = OrderKey.sequence(count: max(merged.count, 1))
        for i in merged.indices { merged[i].order = keys[i] }
        return (merged, map)
    }

    private static let defaultAccent = "#7C7C7C"

    private static func order(_ a: LegacyProfile, _ b: LegacyProfile) -> Bool {
        a.order == b.order ? a.id.uuidString < b.id.uuidString : a.order < b.order
    }

    private static func order(_ a: LegacySpace, _ b: LegacySpace) -> Bool {
        a.order == b.order ? a.id.uuidString < b.id.uuidString : a.order < b.order
    }

    // MARK: - Parents

    /// `.favorites(profileID:)` becomes `.favorites(spaceID:)` on the space that took the profile's
    /// id; pinned and tabs sections follow their space to its merged id.
    private static func rewriteParent(_ value: Any?, spaceIDs: [UUID: UUID]) -> Any? {
        guard var parent = value as? [String: Any] else { return value }
        if let favorites = parent["favorites"] as? [String: Any], let profileID = favorites["profileID"] {
            parent["favorites"] = ["spaceID": profileID]
            return parent
        }
        for key in ["pinned", "tabs"] {
            guard var section = parent[key] as? [String: Any],
                  let raw = section["spaceID"] as? String, let old = UUID(uuidString: raw) else { continue }
            section["spaceID"] = (spaceIDs[old] ?? old).uuidString
            parent[key] = section
            return parent
        }
        return parent
    }

    private static func rewriteItems(_ value: Any?, spaceIDs: [UUID: UUID]) -> Any {
        guard let items = value as? [[String: Any]] else { return value ?? [] }
        return items.map { item -> [String: Any] in
            var copy = item
            copy["parent"] = rewriteParent(item["parent"], spaceIDs: spaceIDs)
            return copy
        }
    }

    // MARK: - Device state

    private static func rewriteDevice(_ data: Data?, spaceIDs: [UUID: UUID]) -> Data? {
        guard let data, var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return data }
        root["formatVersion"] = TabStore.formatVersion
        root["items"] = rewriteItems(root["items"], spaceIDs: spaceIDs)
        if var state = root["state"] as? [String: Any] {
            if let windows = state["windows"] as? [[String: Any]] {
                state["windows"] = windows.map { window -> [String: Any] in
                    var copy = window
                    if let raw = window["spaceID"] as? String, let old = UUID(uuidString: raw) {
                        copy["spaceID"] = (spaceIDs[old] ?? old).uuidString
                    }
                    // A [UUID: UUID] encodes as a flat array of alternating keys and values.
                    if let pairs = window["selectedItemBySpace"] as? [String] {
                        copy["selectedItemBySpace"] = pairs.enumerated().map { index, value in
                            guard index.isMultiple(of: 2), let old = UUID(uuidString: value) else { return value }
                            return (spaceIDs[old] ?? old).uuidString
                        }
                    }
                    return copy
                }
            }
            if let closed = state["closed"] as? [[String: Any]] {
                state["closed"] = closed.map { entry -> [String: Any] in
                    var copy = entry
                    copy["section"] = rewriteParent(entry["section"], spaceIDs: spaceIDs)
                    copy["items"] = rewriteItems(entry["items"], spaceIDs: spaceIDs)
                    return copy
                }
            }
            root["state"] = state
        }
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }
}
