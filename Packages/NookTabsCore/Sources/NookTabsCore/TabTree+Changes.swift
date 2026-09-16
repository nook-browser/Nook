import Foundation

/// Every edit to the tree. Each method validates first and leaves the tree untouched when it
/// throws, and returns the `Change` that undoes it.
extension TabTree {
    // MARK: - Undo

    /// Restores the recorded values and returns the change that redoes this one.
    @discardableResult
    public mutating func apply(_ change: Change) -> Change {
        var redo = Change()
        for (id, value) in change.spaces {
            redo.spaces[id] = .some(spaces[id])
            spaces[id] = value
        }
        for (id, value) in change.items {
            redo.items[id] = .some(items[id])
            items[id] = value
        }
        return redo
    }

    // MARK: - Items

    @discardableResult
    public mutating func createTab(id: UUID = UUID(), url: URL, title: String, in parent: Parent, after: UUID?, now: Date = Date()) throws -> Change {
        try validate(parent: parent, placing: nil, isFolder: false)
        var change = Change()
        let order = placeKey(in: parent, after: after, excluding: id, change: &change, now: now)
        record(&change, item: Item(id: id, parent: parent, order: order, kind: .tab(url: url, pageTitle: title), modifiedAt: now))
        return change
    }

    @discardableResult
    public mutating func createFolder(id: UUID = UUID(), title: String, in parent: Parent, after: UUID?, now: Date = Date()) throws -> Change {
        try validate(parent: parent, placing: nil, isFolder: true)
        var change = Change()
        let order = placeKey(in: parent, after: after, excluding: id, change: &change, now: now)
        record(&change, item: Item(id: id, parent: parent, order: order, kind: .folder, customTitle: title, modifiedAt: now))
        return change
    }

    /// Moves an item (and its subtree) under `parent`, directly after `after` (nil = first).
    ///
    /// `currentURL` is the page a tab currently shows. Moving a tab from the device scope into the
    /// synced scope makes it the home URL; moving out makes it the restore URL.
    @discardableResult
    public mutating func move(_ id: UUID, to parent: Parent, after: UUID?, currentURL: URL? = nil, now: Date = Date()) throws -> Change {
        guard var moving = item(id) else { throw TreeError.missingItem }
        try validate(parent: parent, placing: id, isFolder: moving.isFolder)
        let before = scope(of: id)
        var change = Change()
        moving.order = placeKey(in: parent, after: after, excluding: id, change: &change, now: now)
        moving.parent = parent
        moving.modifiedAt = now
        record(&change, item: moving)
        if let currentURL, case .tab(_, let title) = moving.kind, scope(of: id) != before {
            moving.kind = .tab(url: currentURL, pageTitle: title)
            record(&change, item: moving)
        }
        return change
    }

    @discardableResult
    public mutating func rename(_ id: UUID, customTitle: String?, now: Date = Date()) throws -> Change {
        guard var target = item(id) else { throw TreeError.missingItem }
        let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        target.customTitle = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard target != items[id] else { return Change() }
        target.modifiedAt = now
        var change = Change()
        record(&change, item: target)
        return change
    }

    @discardableResult
    public mutating func setURL(_ id: UUID, _ url: URL, now: Date = Date()) throws -> Change {
        guard var target = item(id) else { throw TreeError.missingItem }
        guard case .tab(let old, let title) = target.kind else { throw TreeError.notATab }
        guard old != url else { return Change() }
        target.kind = .tab(url: url, pageTitle: title)
        target.modifiedAt = now
        var change = Change()
        record(&change, item: target)
        return change
    }

    @discardableResult
    public mutating func setPageTitle(_ id: UUID, _ title: String, now: Date = Date()) throws -> Change {
        guard var target = item(id) else { throw TreeError.missingItem }
        guard case .tab(let url, let old) = target.kind else { throw TreeError.notATab }
        guard old != title else { return Change() }
        target.kind = .tab(url: url, pageTitle: title)
        target.modifiedAt = now
        var change = Change()
        record(&change, item: target)
        return change
    }

    /// Removes an item and its subtree. Synced items become tombstones so a future sync can send
    /// the delete; device items are removed. Returns the undo change and the closed records.
    public mutating func close(_ id: UUID, now: Date = Date()) throws -> (change: Change, closed: ClosedEntry) {
        guard item(id) != nil, let section = section(of: id) else { throw TreeError.missingItem }
        let ids = subtree(of: id)
        let closedItems = ids.compactMap { items[$0] }
        var change = Change()
        for itemID in ids { remove(&change, itemID: itemID, now: now) }
        return (change, ClosedEntry(items: closedItems, section: section, closedAt: now))
    }

    /// Puts closed records back with their original ids. The root returns to its original parent
    /// when that still accepts it, else the root of its original section, else `fallback`.
    public mutating func reopen(_ entry: ClosedEntry, fallback: Parent, now: Date = Date()) throws -> Change {
        guard let root = entry.items.first else { throw TreeError.missingItem }
        let height = entry.items.contains(where: \.isFolder) ? Self.height(of: root.id, in: entry.items) : 0
        let candidates: [Parent] = [root.parent, entry.section, fallback]
        guard let parent = candidates.first(where: { canPlace(entryRoot: root, height: height, under: $0) }) else {
            throw TreeError.missingParent
        }
        var change = Change()
        for var restored in entry.items {
            if restored.id == root.id {
                restored.parent = parent
                if parent != root.parent || children(of: parent).contains(where: { $0.order == restored.order }) {
                    restored.order = placeKey(in: parent, after: children(of: parent).last?.id, excluding: root.id, change: &change, now: now)
                }
            }
            restored.deletedAt = nil
            restored.modifiedAt = now
            record(&change, item: restored)
        }
        return change
    }

    // MARK: - Spaces

    @discardableResult
    public mutating func createSpace(id: UUID = UUID(), name: String, icon: String, accentHex: String, after: UUID?, now: Date = Date()) -> Change {
        var change = Change()
        let siblings = orderedSpaces
        let order = key(after: after, among: siblings) ?? renumberSpaces(siblings, insertingAfter: after, change: &change, now: now)
        record(&change, space: SpaceRecord(id: id, name: name, icon: icon, accentHex: accentHex, order: order, modifiedAt: now))
        return change
    }

    @discardableResult
    public mutating func updateSpace(_ id: UUID, name: String? = nil, icon: String? = nil, accentHex: String? = nil, now: Date = Date()) throws -> Change {
        guard var target = space(id) else { throw TreeError.missingSpace }
        if let name { target.name = name }
        if let icon { target.icon = icon }
        if let accentHex { target.accentHex = accentHex }
        guard target != spaces[id] else { return Change() }
        target.modifiedAt = now
        var change = Change()
        record(&change, space: target)
        return change
    }

    /// Reorders a space, placing it directly after `after` (nil = first).
    @discardableResult
    public mutating func moveSpace(_ id: UUID, after: UUID?, now: Date = Date()) throws -> Change {
        guard var target = space(id) else { throw TreeError.missingSpace }
        var change = Change()
        let siblings = orderedSpaces.filter { $0.id != id }
        target.order = key(after: after, among: siblings) ?? renumberSpaces(siblings, insertingAfter: after, change: &change, now: now)
        target.modifiedAt = now
        record(&change, space: target)
        return change
    }

    /// Deletes a space and closes everything in it as one closed entry per section root.
    public mutating func deleteSpace(_ id: UUID, now: Date = Date()) throws -> (change: Change, closed: [ClosedEntry]) {
        guard var target = space(id) else { throw TreeError.missingSpace }
        guard orderedSpaces.count > 1 else { throw TreeError.lastSpace }
        var change = Change()
        var closed: [ClosedEntry] = []
        for section in [Parent.favorites(spaceID: id), .pinned(spaceID: id), .tabs(spaceID: id)] {
            for root in children(of: section) {
                let result = try close(root.id, now: now)
                change.merge(result.change)
                closed.append(result.closed)
            }
        }
        target.deletedAt = now
        target.modifiedAt = now
        record(&change, space: target)
        return (change, closed)
    }

    // MARK: - Validation

    /// Throws when `parent` cannot hold the item. `placing` is the id being moved (nil for new).
    func validate(parent: Parent, placing id: UUID?, isFolder: Bool) throws {
        switch parent {
        case .favorites(let spaceID):
            guard space(spaceID) != nil else { throw TreeError.missingSpace }
            if isFolder { throw TreeError.folderInFavorites }
        case .pinned(let spaceID), .tabs(let spaceID):
            guard space(spaceID) != nil else { throw TreeError.missingSpace }
        case .folder(let folderID):
            guard let folder = item(folderID), folder.isFolder else { throw TreeError.missingParent }
            guard let chain = folderChain(of: folderID) else { throw TreeError.cycle }
            if let id, id == folderID || chain.folders.contains(id) { throw TreeError.cycle }
            if case .favorites = chain.section { throw TreeError.folderInFavorites }
            // The new position sits inside the folder plus its ancestors.
            let depth = chain.folders.count + 1
            let height = id.map { folderHeight(of: $0) } ?? (isFolder ? 1 : 0)
            // Folder levels on the deepest path: ancestors, the new parent, and the moved subtree.
            if depth + height > Self.maxFolderDepth { throw TreeError.tooDeep }
        }
    }

    // MARK: - Helpers

    private mutating func record(_ change: inout Change, item: Item) {
        if change.items[item.id] == nil { change.items[item.id] = .some(items[item.id]) }
        items[item.id] = item
    }

    private mutating func record(_ change: inout Change, space: SpaceRecord) {
        if change.spaces[space.id] == nil { change.spaces[space.id] = .some(spaces[space.id]) }
        spaces[space.id] = space
    }

    private mutating func remove(_ change: inout Change, itemID: UUID, now: Date) {
        guard var target = items[itemID] else { return }
        if change.items[itemID] == nil { change.items[itemID] = .some(target) }
        if scope(of: itemID) == .synced {
            target.deletedAt = now
            target.modifiedAt = now
            items[itemID] = target
        } else {
            items[itemID] = nil
        }
    }

    /// A key for a new position after `after` among `parent`'s children. Renumbers the siblings
    /// (recorded in `change`) when no key fits between the neighbors.
    private mutating func placeKey(in parent: Parent, after: UUID?, excluding id: UUID, change: inout Change, now: Date) -> OrderKey {
        let siblings = children(of: parent).filter { $0.id != id }
        let index = after.flatMap { a in siblings.firstIndex(where: { $0.id == a }) }.map { $0 + 1 } ?? 0
        let lower = index > 0 ? siblings[index - 1].order : nil
        let upper = index < siblings.count ? siblings[index].order : nil
        if let key = OrderKey.between(lower, upper) { return key }
        let keys = OrderKey.sequence(count: siblings.count + 1)
        var k = 0
        for (i, sibling) in siblings.enumerated() {
            if i == index { k += 1 }
            var renumbered = sibling
            renumbered.order = keys[k]
            renumbered.modifiedAt = now
            record(&change, item: renumbered)
            k += 1
        }
        return keys[index]
    }

    private func key(after: UUID?, among siblings: [SpaceRecord]) -> OrderKey? {
        let index = after.flatMap { a in siblings.firstIndex(where: { $0.id == a }) }.map { $0 + 1 } ?? 0
        let lower = index > 0 ? siblings[index - 1].order : nil
        let upper = index < siblings.count ? siblings[index].order : nil
        return OrderKey.between(lower, upper)
    }

    private mutating func renumberSpaces(_ siblings: [SpaceRecord], insertingAfter after: UUID?, change: inout Change, now: Date) -> OrderKey {
        let index = after.flatMap { a in siblings.firstIndex(where: { $0.id == a }) }.map { $0 + 1 } ?? 0
        let keys = OrderKey.sequence(count: siblings.count + 1)
        var k = 0
        for (i, sibling) in siblings.enumerated() {
            if i == index { k += 1 }
            var renumbered = sibling
            renumbered.order = keys[k]
            renumbered.modifiedAt = now
            record(&change, space: renumbered)
            k += 1
        }
        return keys[index]
    }

    private func canPlace(entryRoot root: Item, height: Int, under parent: Parent) -> Bool {
        switch parent {
        case .favorites(let s): return !root.isFolder && space(s) != nil
        case .pinned(let s), .tabs(let s): return space(s) != nil
        case .folder(let f):
            guard let folder = item(f), folder.isFolder, let chain = folderChain(of: f) else { return false }
            if case .favorites = chain.section { return false }
            return chain.folders.count + 1 + height <= Self.maxFolderDepth
        }
    }

    static func height(of rootID: UUID, in records: [Item]) -> Int {
        let byParent = Dictionary(grouping: records, by: \.parent)
        func height(_ id: UUID) -> Int {
            1 + ((byParent[.folder(itemID: id)] ?? []).filter(\.isFolder).map { height($0.id) }.max() ?? 0)
        }
        return records.first(where: { $0.id == rootID })?.isFolder == true ? height(rootID) : 0
    }
}

/// A closed subtree, root first, with the values it had when closed.
public struct ClosedEntry: Codable, Hashable, Sendable {
    public var items: [Item]
    /// The section the root was in when closed.
    public var section: Parent
    public var closedAt: Date
    /// Set when only the page of a pinned tab or favorite closed and the item stayed. Reopening
    /// brings that page back; `items` holds the record in case the item is deleted later.
    public var endedPage: OpenPage?

    public init(items: [Item], section: Parent, closedAt: Date, endedPage: OpenPage? = nil) {
        self.items = items
        self.section = section
        self.closedAt = closedAt
        self.endedPage = endedPage
    }
}
