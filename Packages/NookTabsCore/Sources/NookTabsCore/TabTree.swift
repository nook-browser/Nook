// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// Spaces and items with the rules that keep them a valid tree.
///
/// A value type: every mutation records the prior value of each record it writes and
/// returns that as a `Change`, so undo is `apply(change)`.
public struct TabTree: Codable, Equatable, Sendable {
    public static let maxFolderDepth = 5

    public internal(set) var spaces: [UUID: SpaceRecord]
    public internal(set) var items: [UUID: Item]

    public init(spaces: [SpaceRecord] = [], items: [Item] = []) {
        self.spaces = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.items = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Lookup

    public func space(_ id: UUID) -> SpaceRecord? {
        guard let s = spaces[id], s.deletedAt == nil else { return nil }
        return s
    }

    public func item(_ id: UUID) -> Item? {
        guard let i = items[id], i.deletedAt == nil else { return nil }
        return i
    }

    public var orderedSpaces: [SpaceRecord] {
        spaces.values.filter { $0.deletedAt == nil }.sorted(by: Self.sortKey)
    }

    /// Live children of a parent in display order.
    public func children(of parent: Parent) -> [Item] {
        items.values.filter { $0.deletedAt == nil && $0.parent == parent }.sorted(by: Self.sortKey)
    }

    public func favorites(of spaceID: UUID) -> [Item] {
        children(of: .favorites(spaceID: spaceID))
    }

    /// Live items grouped by parent, each group in display order. One pass for whole-tree reads.
    public func childrenByParent() -> [Parent: [Item]] {
        var groups: [Parent: [Item]] = [:]
        for item in items.values where item.deletedAt == nil {
            groups[item.parent, default: []].append(item)
        }
        for key in groups.keys { groups[key]!.sort(by: Self.sortKey) }
        return groups
    }

    // MARK: - Ancestry

    /// Ids of the folders and parent tabs from the item's parent up to the section, nearest first.
    /// nil on a cycle or a missing parent. Follows tombstoned records so scope is known for deleted
    /// items too.
    func folderChain(of id: UUID) -> (folders: [UUID], section: Parent)? {
        var folders: [UUID] = []
        var visited: Set<UUID> = [id]
        guard var parent = items[id]?.parent else { return nil }
        while case .folder(let folderID) = parent {
            guard visited.insert(folderID).inserted, let folder = items[folderID] else { return nil }
            folders.append(folderID)
            parent = folder.parent
        }
        return (folders, parent)
    }

    /// The section an item ultimately belongs to.
    public func section(of id: UUID) -> Parent? { folderChain(of: id)?.section }

    public func scope(of id: UUID) -> Scope {
        switch section(of: id) {
        case .favorites, .pinned: return .synced
        case .tabs, .folder, nil: return .device
        }
    }

    /// The space whose data store an item's page uses.
    public func spaceID(of id: UUID) -> UUID? {
        section(of: id)?.spaceID
    }

    /// Live ids of the item and everything under it, parents before children.
    public func subtree(of id: UUID) -> [UUID] {
        guard item(id) != nil else { return [] }
        let groups = childrenByParent()
        var out: [UUID] = []
        var stack = [id]
        while let next = stack.popLast() {
            out.append(next)
            stack.append(contentsOf: (groups[.folder(itemID: next)] ?? []).reversed().map(\.id))
        }
        return out
    }

    /// Number of folders and parent tabs an item sits inside.
    func folderDepth(of id: UUID) -> Int { folderChain(of: id)?.folders.count ?? 0 }

    /// Deepest nesting inside an item, counting the item itself as 1 when it is a folder or a tab
    /// with children (a trail), else 0.
    func folderHeight(of id: UUID) -> Int {
        guard item(id) != nil else { return 0 }
        return Self.nestingHeight(of: id, isFolder: { self.items[$0]?.isFolder == true }, children: childrenByParent())
    }

    static func nestingHeight(of id: UUID, isFolder: (UUID) -> Bool, children: [Parent: [Item]]) -> Int {
        let kids = children[.folder(itemID: id)] ?? []
        guard isFolder(id) || !kids.isEmpty else { return 0 }
        return 1 + (kids.map { nestingHeight(of: $0.id, isFolder: isFolder, children: children) }.max() ?? 0)
    }

    /// Whether `hostID` can take a child: a folder anywhere but favorites, or a tab in the Tabs
    /// section taking a tab (a trail). Pinned tabs and favorites never hold children.
    func accepts(child isFolder: Bool, under hostID: UUID) -> Bool {
        guard let host = item(hostID), let chain = folderChain(of: hostID) else { return false }
        if host.isFolder {
            if case .favorites = chain.section { return false }
            return true
        }
        guard !isFolder, case .tabs = chain.section else { return false }
        return true
    }

    /// Whether a new tab can go under tab `hostID` as the start or end of a trail: the host is a
    /// tab in the Tabs section and the child stays within `maxFolderDepth`.
    public func canTakeChild(_ hostID: UUID) -> Bool {
        guard item(hostID)?.isFolder == false else { return false }
        return (try? validate(parent: .folder(itemID: hostID), placing: nil, isFolder: false)) != nil
    }

    /// A live tab with children.
    public func hasChildren(_ id: UUID) -> Bool {
        items.values.contains { $0.deletedAt == nil && $0.parent == .folder(itemID: id) }
    }

    // MARK: - Ordering

    static func sortKey<T: Orderable>(_ a: T, _ b: T) -> Bool {
        a.order == b.order ? a.id.uuidString < b.id.uuidString : a.order < b.order
    }
}

protocol Orderable {
    var id: UUID { get }
    var order: OrderKey { get }
}

extension SpaceRecord: Orderable {}
extension Item: Orderable {}
