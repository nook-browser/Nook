import Foundation

/// Profiles, spaces and items with the rules that keep them a valid tree.
///
/// A value type: every mutation records the prior value of each record it writes and
/// returns that as a `Change`, so undo is `apply(change)`.
public struct TabTree: Codable, Equatable, Sendable {
    public static let maxFolderDepth = 5

    public internal(set) var profiles: [UUID: Profile]
    public internal(set) var spaces: [UUID: Space]
    public internal(set) var items: [UUID: Item]

    public init(profiles: [Profile] = [], spaces: [Space] = [], items: [Item] = []) {
        self.profiles = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.spaces = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.items = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Lookup

    public func profile(_ id: UUID) -> Profile? {
        guard let p = profiles[id], p.deletedAt == nil else { return nil }
        return p
    }

    public func space(_ id: UUID) -> Space? {
        guard let s = spaces[id], s.deletedAt == nil else { return nil }
        return s
    }

    public func item(_ id: UUID) -> Item? {
        guard let i = items[id], i.deletedAt == nil else { return nil }
        return i
    }

    public var orderedProfiles: [Profile] {
        profiles.values.filter { $0.deletedAt == nil }.sorted(by: Self.sortKey)
    }

    public func orderedSpaces(in profileID: UUID) -> [Space] {
        spaces.values.filter { $0.deletedAt == nil && $0.profileID == profileID }.sorted(by: Self.sortKey)
    }

    /// Every live space, grouped by profile order.
    public var orderedSpaces: [Space] {
        orderedProfiles.flatMap { orderedSpaces(in: $0.id) }
    }

    /// Live children of a parent in display order.
    public func children(of parent: Parent) -> [Item] {
        items.values.filter { $0.deletedAt == nil && $0.parent == parent }.sorted(by: Self.sortKey)
    }

    public func favorites(of profileID: UUID) -> [Item] {
        children(of: .favorites(profileID: profileID))
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

    /// Folder ids from the item's parent up to the section, nearest first. nil on a cycle or a
    /// missing folder. Follows tombstoned records so scope is known for deleted items too.
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

    public func spaceID(of id: UUID) -> UUID? {
        switch section(of: id) {
        case .pinned(let s), .tabs(let s): return s
        default: return nil
        }
    }

    /// The profile whose data store an item's page uses.
    public func profileID(of id: UUID) -> UUID? {
        switch section(of: id) {
        case .favorites(let p): return p
        case .pinned(let s), .tabs(let s): return spaces[s]?.profileID
        default: return nil
        }
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

    /// Number of folders an item sits inside.
    func folderDepth(of id: UUID) -> Int { folderChain(of: id)?.folders.count ?? 0 }

    /// Deepest folder nesting inside a folder, counting the folder itself as 1.
    func folderHeight(of id: UUID) -> Int {
        guard let root = item(id), root.isFolder else { return 0 }
        let groups = childrenByParent()
        func height(_ folderID: UUID) -> Int {
            1 + ((groups[.folder(itemID: folderID)] ?? []).filter(\.isFolder).map { height($0.id) }.max() ?? 0)
        }
        return height(id)
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

extension Profile: Orderable {}
extension Space: Orderable {}
extension Item: Orderable {}
