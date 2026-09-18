// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import Foundation

extension TabTree {
    public static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Makes a loaded tree satisfy every rule without dropping live records.
    ///
    /// Tombstones older than `tombstoneLifetime` are purged. An item whose parent is gone, or that
    /// sits in a cycle, moves to the root of its original section when that still exists, else the
    /// first space's tabs section. Folders nested deeper than `maxFolderDepth` are lifted to the
    /// deepest allowed level, and a folder in favorites moves to its space's pinned section.
    /// Returns true when anything changed.
    @discardableResult
    public mutating func repair(now: Date = Date()) -> Bool {
        var changed = false

        let cutoff = now.addingTimeInterval(-Self.tombstoneLifetime)
        for (id, s) in Array(spaces) where (s.deletedAt ?? .distantFuture) < cutoff { spaces[id] = nil; changed = true }
        for (id, i) in Array(items) where (i.deletedAt ?? .distantFuture) < cutoff { items[id] = nil; changed = true }

        guard let firstSpace = orderedSpaces.first else { return changed }
        let fallback = Parent.tabs(spaceID: firstSpace.id)

        // Parents and cycles. Repeat until stable: lifting one item can expose a child's problem.
        var pass = true
        while pass {
            pass = false
            for (id, item) in Array(items) where item.deletedAt == nil {
                guard let target = repairedParent(for: id, fallback: fallback) else { continue }
                if target != item.parent {
                    let order = OrderKey.between(children(of: target).last?.order, nil) ?? item.order
                    items[id]?.parent = target
                    items[id]?.order = order
                    items[id]?.modifiedAt = now
                    pass = true
                    changed = true
                }
            }
        }

        // Depth. Lift the item to the ancestor that keeps it within the limit.
        for (id, item) in Array(items) where item.deletedAt == nil {
            guard let chain = folderChain(of: id) else { continue }
            let allowed = Self.maxFolderDepth - (item.isFolder ? 1 : 0)
            if chain.folders.count > allowed {
                let newParent: Parent = allowed == 0 ? chain.section : .folder(itemID: chain.folders[chain.folders.count - allowed])
                let order = OrderKey.between(children(of: newParent).last?.order, nil) ?? item.order
                items[id]?.parent = newParent
                items[id]?.order = order
                items[id]?.modifiedAt = now
                changed = true
            }
        }
        return changed
    }

    /// The parent an item should have, or nil when it has no live position at all.
    private func repairedParent(for id: UUID, fallback: Parent) -> Parent? {
        guard let item = items[id] else { return nil }
        switch item.parent {
        case .favorites(let spaceID):
            guard space(spaceID) != nil else { return fallback }
            // Favorites hold tabs only; a folder drops into the same space's pinned section.
            return item.isFolder ? .pinned(spaceID: spaceID) : item.parent
        case .pinned(let spaceID), .tabs(let spaceID):
            return space(spaceID) == nil ? fallback : item.parent
        case .folder(let folderID):
            guard let folder = self.item(folderID), folder.isFolder else {
                return lastKnownSection(of: id).flatMap { liveSection($0) } ?? fallback
            }
            if folderChain(of: id) == nil { return fallback }
            return item.parent
        }
    }

    /// Follows the chain through tombstoned records to the section it started in.
    private func lastKnownSection(of id: UUID) -> Parent? {
        var visited: Set<UUID> = [id]
        guard var parent = items[id]?.parent else { return nil }
        while case .folder(let folderID) = parent {
            guard visited.insert(folderID).inserted, let folder = items[folderID] else { return nil }
            parent = folder.parent
        }
        return parent
    }

    private func liveSection(_ section: Parent) -> Parent? {
        guard let spaceID = section.spaceID, space(spaceID) != nil else { return nil }
        return section
    }
}
