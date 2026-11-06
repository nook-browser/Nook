// Licensed under GPL-3.0. See LICENSE.
import Foundation

public enum ArchiveReason: String, Codable, Sendable {
    case closed
    case auto
}

/// A tab (or folder) subtree taken out of a space's tabs section.
public struct ArchiveEntry: Codable, Hashable, Sendable, Identifiable {
    /// The root item's id.
    public var id: UUID
    /// The root first, with the values it had when archived.
    public var items: [Item]
    public var spaceID: UUID
    public var title: String
    public var url: URL?
    /// The host whose favicon the row shows.
    public var host: String?
    public var archivedAt: Date
    public var reason: ArchiveReason

    public init?(closed: ClosedEntry, reason: ArchiveReason, now: Date = Date()) {
        guard case .tabs(let spaceID) = closed.section, let root = closed.items.first else { return nil }
        id = root.id
        items = closed.items
        self.spaceID = spaceID
        title = root.displayTitle
        url = root.url
        host = root.url?.host
        archivedAt = now
        self.reason = reason
    }
}

/// Everything in `archive.json`, newest last.
public struct Archive: Codable, Equatable, Sendable {
    public static let retentionDays = 30
    public static let maxEntries = 1000

    public var entries: [ArchiveEntry] = []

    public init(entries: [ArchiveEntry] = []) { self.entries = entries }

    public mutating func add(_ entry: ArchiveEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        trim(now: entry.archivedAt)
    }

    /// Drops entries past the retention window, then the oldest beyond the cap.
    public mutating func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        entries.removeAll { $0.archivedAt < cutoff }
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    /// Removes entries holding any of `ids`. Returns whether anything went.
    @discardableResult
    public mutating func remove(containing ids: Set<UUID>) -> Bool {
        let count = entries.count
        entries.removeAll { entry in entry.items.contains { ids.contains($0.id) } }
        return entries.count != count
    }
}

extension DeviceState {
    public mutating func stampActive(_ id: UUID, at now: Date) {
        if lastActive == nil { lastActive = [:] }
        lastActive?[id] = now
    }

    /// Top-level tabs in the tabs sections that nobody has opened for `interval`, as trail roots.
    /// A tab with no stamp starts its clock now, so an upgrade never archives anything at once.
    /// A trail with any member in `protected`, or opened within `interval`, stays. Folders and
    /// their contents and the Agent space are left alone.
    public mutating func idleArchiveRoots(in tree: TabTree, olderThan interval: TimeInterval, keeping protected: Set<UUID>, now: Date) -> [UUID] {
        var stamps = lastActive ?? [:]
        let groups = tree.childrenByParent()
        var idle: [UUID] = []
        for space in tree.orderedSpaces where !space.isAgent {
            for root in groups[.tabs(spaceID: space.id)] ?? [] where !root.isFolder {
                var ids: [UUID] = []
                var stack = [root.id]
                while let next = stack.popLast() {
                    ids.append(next)
                    stack.append(contentsOf: (groups[.folder(itemID: next)] ?? []).map(\.id))
                }
                for id in ids where stamps[id] == nil { stamps[id] = now }
                let newest = ids.compactMap { stamps[$0] }.max() ?? now
                if newest <= now.addingTimeInterval(-interval), ids.allSatisfy({ !protected.contains($0) }) {
                    idle.append(root.id)
                }
            }
        }
        if stamps != (lastActive ?? [:]) { lastActive = stamps }
        return idle
    }
}
