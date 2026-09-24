// Licensed under GPL-3.0. See LICENSE.
import Foundation
import NookTabsCore

/// The rows the server is known to hold, advanced only on acked saves and fetches.
/// Diffing the live tree against this is what drives every upload, so a crash
/// before an ack simply re-emits the same change on the next diff.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public var spaces: [UUID: SpaceRecord] = [:]
    public var items: [UUID: Item] = [:]
    /// Archived CKRecord system fields per record id, for conflict-free resaves.
    public var systemFields: [UUID: Data] = [:]
    /// Device records by device id, own included. Kept here because an
    /// incremental fetch never redelivers an unchanged record.
    public var devices: [UUID: DeviceTabsPayload] = [:]

    public init() {}

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Missing or corrupt file loads empty: the next diff re-uploads everything,
    /// which converges through LWW rather than losing anything.
    public static func load(from url: URL) -> SyncSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: data)
        else { return SyncSnapshot() }
        return snapshot
    }

    /// The favorites or pinned section a row sits under by the server's own
    /// rows, or nil when its folder chain leaves the snapshot. A row whose chain
    /// never resolved was never fully placed on this Mac, so its landing in the
    /// tabs section is the loader's orphan repair and not a move by the user.
    func syncedSection(of id: UUID) -> Parent? {
        var visited: Set<UUID> = [id]
        guard var parent = items[id]?.parent else { return nil }
        while case .folder(let folderID) = parent {
            guard visited.insert(folderID).inserted, let folder = items[folderID] else { return nil }
            parent = folder.parent
        }
        switch parent {
        case .favorites, .pinned: return parent
        case .tabs, .folder: return nil
        }
    }
}

public enum SyncDiff {
    public struct Changes: Equatable, Sendable {
        public var upsertSpaces: [SpaceRecord] = []
        public var upsertItems: [Item] = []
        public var deleteIDs: [UUID] = []

        public init() {}

        public var isEmpty: Bool { upsertSpaces.isEmpty && upsertItems.isEmpty && deleteIDs.isEmpty }
    }

    public static func changes(tree: TabTree, snapshot: SyncSnapshot, now: Date = Date()) -> Changes {
        var out = Changes()

        for space in tree.spaces.values where snapshot.spaces[space.id] != space {
            out.upsertSpaces.append(space)
        }
        for id in snapshot.spaces.keys where tree.spaces[id] == nil {
            out.deleteIDs.append(id)
        }

        // Items the diff considers part of the synced scope right now. An
        // unresolvable section (mid-fetch orphan) counts as synced but uploads
        // nothing until repair settles it.
        var held = Set<UUID>()
        for item in tree.items.values {
            switch tree.section(of: item.id) {
            case .favorites, .pinned:
                held.insert(item.id)
                if snapshot.items[item.id] != item { out.upsertItems.append(item) }
            case nil:
                held.insert(item.id)
            case .tabs, .folder:
                break
            }
        }

        for (id, row) in snapshot.items where !held.contains(id) {
            if tree.items[id] == nil {
                out.deleteIDs.append(id)
            } else if row.deletedAt == nil, case .tabs = tree.section(of: id),
                      snapshot.syncedSection(of: id) != nil {
                var tombstone = row
                tombstone.deletedAt = now
                tombstone.modifiedAt = now
                out.upsertItems.append(tombstone)
            }
        }
        return out
    }
}
