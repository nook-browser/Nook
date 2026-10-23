// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// The exact grid order after a drop. The dragged ID represents one placeholder,
/// never both an invisible source tile and an additional destination tile.
public struct FavoriteDropPreview {
    public let itemIDs: [UUID]
    public let placeholderID: UUID

    public init(itemIDs: [UUID], draggedID: UUID, destinationBoundary: Int) {
        let boundary = max(0, min(itemIDs.count, destinationBoundary))
        let insertion = itemIDs.prefix(boundary).filter { $0 != draggedID }.count
        var result = itemIDs.filter { $0 != draggedID }
        result.insert(draggedID, at: insertion)
        self.itemIDs = result
        self.placeholderID = draggedID
    }
}
