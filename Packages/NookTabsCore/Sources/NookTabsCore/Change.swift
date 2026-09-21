// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// The records a change touched, with their values before it. nil means the record did not exist.
/// Applying a `Change` restores those values and returns the change that redoes it.
public struct Change: Codable, Equatable, Sendable {
    public var spaces: [UUID: SpaceRecord?] = [:]
    public var items: [UUID: Item?] = [:]

    public init() {}

    public var isEmpty: Bool { spaces.isEmpty && items.isEmpty }

    /// Ids of every item this change touches.
    public var itemIDs: Set<UUID> { Set(items.keys) }

    /// Keeps the earliest recorded value when two changes are combined in order.
    public mutating func merge(_ later: Change) {
        spaces.merge(later.spaces) { first, _ in first }
        items.merge(later.items) { first, _ in first }
    }
}
