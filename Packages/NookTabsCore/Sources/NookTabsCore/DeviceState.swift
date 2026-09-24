// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// State that belongs to this Mac only and never syncs.
public struct DeviceState: Codable, Equatable, Sendable {
    public static let closedLimit = 50

    public var openFolders: Set<UUID> = []
    /// Live pages of synced tabs (pinned and favorites), by item id.
    public var openPages: [UUID: OpenPage] = [:]
    public var windows: [WindowRecord] = []
    /// Newest last.
    public var closed: [ClosedEntry] = []
    public var firstLaunchCompleted = false

    public init() {}

    public mutating func pushClosed(_ entry: ClosedEntry) {
        closed.append(entry)
        if closed.count > Self.closedLimit { closed.removeFirst(closed.count - Self.closedLimit) }
    }

    /// Drops references to items and spaces that no longer exist.
    public mutating func prune(against tree: TabTree) {
        openFolders = openFolders.filter { tree.item($0)?.isFolder == true || tree.hasChildren($0) }
        openPages = openPages.filter { tree.item($0.key) != nil && tree.scope(of: $0.key) == .synced }
        for i in windows.indices {
            if let spaceID = windows[i].spaceID, tree.space(spaceID) == nil { windows[i].spaceID = nil }
            windows[i].selectedItemBySpace = windows[i].selectedItemBySpace.filter { tree.space($0.key) != nil && tree.item($0.value) != nil }
            if let split = windows[i].split, tree.item(split.leftItemID) == nil || tree.item(split.rightItemID) == nil {
                windows[i].split = nil
            }
        }
    }
}

public struct OpenPage: Codable, Hashable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

public struct WindowRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var spaceID: UUID?
    public var selectedItemBySpace: [UUID: UUID]
    public var split: SplitRecord?
    /// `NSStringFromRect` of the window frame, restored by the app.
    public var frame: String?

    public init(id: UUID = UUID(), spaceID: UUID? = nil, selectedItemBySpace: [UUID: UUID] = [:], split: SplitRecord? = nil, frame: String? = nil) {
        self.id = id
        self.spaceID = spaceID
        self.selectedItemBySpace = selectedItemBySpace
        self.split = split
        self.frame = frame
    }
}

public struct SplitRecord: Codable, Hashable, Sendable {
    public var leftItemID: UUID
    public var rightItemID: UUID
    public var fraction: Double

    public init(leftItemID: UUID, rightItemID: UUID, fraction: Double) {
        self.leftItemID = leftItemID
        self.rightItemID = rightItemID
        self.fraction = fraction
    }
}
