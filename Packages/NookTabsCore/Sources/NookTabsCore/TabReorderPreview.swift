// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// A visual-only reorder plan. Offsets and the gap are measured in row strides; the source
/// array remains unchanged until a drop commits the real tree mutation.
public struct TabReorderPreview {
    private var offsets: [UUID: Int] = [:]
    private var draggedRows: Set<UUID> = []
    public private(set) var gapIndex: Int?
    public private(set) var draggedRowCount: Int = 0

    public func rowOffset(for id: UUID) -> Int { offsets[id] ?? 0 }
    public func containsDraggedRow(id: UUID) -> Bool { draggedRows.contains(id) }

    public init(rows: [Row], draggedID: UUID, destinationBoundary: Int?, sourceInThisSection: Bool, isDestination: Bool, isIntoFolder: Bool = false) {
        let boundary = destinationBoundary.map { max(0, min(rows.count, $0)) }
        if sourceInThisSection {
            // A stale drag must not move unrelated rows.
            guard let start = rows.firstIndex(where: { $0.item.id == draggedID }) else { return }
            var end = start + 1
            while end < rows.count, rows[end].depth > rows[start].depth { end += 1 }
            draggedRows = Set(rows[start..<end].map { $0.item.id })
            draggedRowCount = end - start

            if isDestination, isIntoFolder, let boundary, (start..<end).contains(boundary) {
                // A folder cannot contain itself or any of its ancestors.
                return
            }
            if !isDestination || isIntoFolder {
                for row in rows[end...] { offsets[row.item.id] = -draggedRowCount }
                return
            }
            guard let boundary else {
                gapIndex = start
                return
            }
            if (start...end).contains(boundary) {
                gapIndex = start
            } else if boundary < start {
                gapIndex = boundary
                for row in rows[boundary..<start] { offsets[row.item.id] = draggedRowCount }
            } else {
                gapIndex = boundary - draggedRowCount
                for row in rows[end..<boundary] { offsets[row.item.id] = -draggedRowCount }
            }
        } else {
            // The receiving section only previews the top-level dragged row. Its descendants
            // remain with the source tree until the actual drop is resolved.
            guard isDestination, !isIntoFolder, let boundary,
                  !rows.contains(where: { $0.item.id == draggedID }) else { return }
            draggedRowCount = 1
            gapIndex = boundary
            for row in rows[boundary...] { offsets[row.item.id] = 1 }
        }
    }
}
