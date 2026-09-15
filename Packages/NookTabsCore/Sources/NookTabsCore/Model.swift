import Foundation

public struct ProfileRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var order: OrderKey
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, icon: String, order: OrderKey, modifiedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.order = order
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

public struct SpaceRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var profileID: UUID
    public var name: String
    public var icon: String
    public var accentHex: String
    public var order: OrderKey
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), profileID: UUID, name: String, icon: String, accentHex: String, order: OrderKey, modifiedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.icon = icon
        self.accentHex = accentHex
        self.order = order
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

/// Where an item sits. Sections (favorites, pinned, tabs) are parent values with no record.
public enum Parent: Codable, Hashable, Sendable {
    case favorites(profileID: UUID)
    case pinned(spaceID: UUID)
    case tabs(spaceID: UUID)
    case folder(itemID: UUID)

    public var isSection: Bool {
        if case .folder = self { return false }
        return true
    }
}

public enum ItemKind: Codable, Hashable, Sendable {
    /// `url` is the home URL in the synced scope and the last committed URL in the device scope.
    case tab(url: URL, pageTitle: String)
    case folder
}

public struct Item: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var parent: Parent
    public var order: OrderKey
    public var kind: ItemKind
    public var customTitle: String?
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(id: UUID = UUID(), parent: Parent, order: OrderKey, kind: ItemKind, customTitle: String? = nil, modifiedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id
        self.parent = parent
        self.order = order
        self.kind = kind
        self.customTitle = customTitle
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    public var url: URL? {
        if case .tab(let url, _) = kind { return url }
        return nil
    }

    public var pageTitle: String? {
        if case .tab(_, let title) = kind { return title }
        return nil
    }

    /// Custom title when set, else the page title (tabs) or empty (folders).
    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return pageTitle ?? ""
    }
}

/// Synced items travel with the profile's data; device items stay on this Mac.
public enum Scope: Hashable, Sendable {
    case synced
    case device
}

/// The two sidebar sections of a space.
public enum SidebarSection: String, Codable, Hashable, Sendable {
    case pinned
    case tabs

    public func parent(in spaceID: UUID) -> Parent {
        switch self {
        case .pinned: return .pinned(spaceID: spaceID)
        case .tabs: return .tabs(spaceID: spaceID)
        }
    }
}

public struct Row: Hashable, Sendable, Identifiable {
    public let item: Item
    /// Number of folders the item sits inside.
    public let depth: Int
    public let section: SidebarSection
    public var id: UUID { item.id }
}

public enum TreeError: Error, Equatable, Sendable {
    case missingItem
    case missingParent
    case missingSpace
    case missingProfile
    case cycle
    case tooDeep
    case folderInFavorites
    case notATab
    case lastSpace
    case lastProfile
}
