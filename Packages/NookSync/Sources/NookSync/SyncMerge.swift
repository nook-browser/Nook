// Licensed under GPL-3.0. See LICENSE.
import Foundation
import NookTabsCore

/// One fetched batch of remote rows, already mapped out of CKRecords.
public struct RemoteBatch: Equatable, Sendable {
    public var spaces: [SpaceRecord]
    public var items: [Item]
    /// Record ids the server deleted (30-day purges). Only tombstoned or absent
    /// local rows honor these; a live local row re-uploads instead.
    public var deletions: [UUID]

    public init(spaces: [SpaceRecord], items: [Item], deletions: [UUID]) {
        self.spaces = spaces
        self.items = items
        self.deletions = deletions
    }

    public var isEmpty: Bool { spaces.isEmpty && items.isEmpty && deletions.isEmpty }
}

/// Per-record last-writer-wins. Never repairs: CKSyncEngine delivers fetches in
/// partial batches, and repairing between them would eject a child whose folder
/// has not arrived yet into the device scope, which the next diff would then
/// tombstone remotely. The caller runs `repair` once at fetch-cycle end.
public enum SyncMerge {
    public static func merge(_ remote: RemoteBatch, into tree: TabTree) -> (tree: TabTree, changed: Bool) {
        var spaces = tree.spaces
        var items = tree.items

        for incoming in remote.spaces {
            if let local = spaces[incoming.id], local.modifiedAt > incoming.modifiedAt { continue }
            spaces[incoming.id] = incoming
        }

        for incoming in remote.items {
            // An id the local device holds in its tabs section left the synced scope
            // here; nothing remote moves it back (the scope-exit tombstone wins later).
            if items[incoming.id] != nil, case .tabs = tree.section(of: incoming.id) { continue }
            if let local = items[incoming.id], local.modifiedAt > incoming.modifiedAt { continue }
            items[incoming.id] = incoming
        }

        for id in remote.deletions {
            if let s = spaces[id], s.deletedAt != nil { spaces[id] = nil }
            if let i = items[id], i.deletedAt != nil { items[id] = nil }
        }

        let changed = spaces != tree.spaces || items != tree.items
        return (TabTree(spaces: Array(spaces.values), items: Array(items.values)), changed)
    }
}
