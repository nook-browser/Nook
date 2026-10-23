// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct TabReorderPreviewTests {
    private func rows(depths: [Int] = [0, 0, 0, 0]) -> [Row] {
        let space = UUID()
        return depths.enumerated().map { index, depth in
            Row(item: Item(parent: .tabs(spaceID: space), order: OrderKey("V"),
                           kind: .tab(url: URL(string: "https://example.com/\(index)")!, pageTitle: "\(index)")),
                depth: depth, section: .tabs, hasChildren: index + 1 < depths.count && depths[index + 1] > depth)
        }
    }
    private func offsets(_ preview: TabReorderPreview, _ rows: [Row]) -> [Int] {
        rows.map { preview.rowOffset(for: $0.item.id) }
    }

    @Test func sameSectionUpAndDown() {
        let rows = rows()
        let up = TabReorderPreview(rows: rows, draggedID: rows[2].item.id, destinationBoundary: 0, sourceInThisSection: true, isDestination: true)
        #expect(offsets(up, rows) == [1, 1, 0, 0])
        #expect(up.gapIndex == 0 && up.draggedRowCount == 1)
        #expect(up.containsDraggedRow(id: rows[2].item.id))
        let down = TabReorderPreview(rows: rows, draggedID: rows[0].item.id, destinationBoundary: 3, sourceInThisSection: true, isDestination: true)
        #expect(offsets(down, rows) == [0, -1, -1, 0])
        #expect(down.gapIndex == 2)
    }

    @Test func ownSlotsAndInitialPositionRemainStill() {
        let rows = rows()
        for boundary: Int? in [nil, 1, 2] {
            let preview = TabReorderPreview(rows: rows, draggedID: rows[1].item.id, destinationBoundary: boundary, sourceInThisSection: true, isDestination: true)
            #expect(offsets(preview, rows) == [0, 0, 0, 0])
            #expect(preview.gapIndex == 1)
        }
    }

    @Test func subtreeMovesAsOneBlock() {
        let rows = rows(depths: [0, 0, 1, 2, 0, 0])
        let down = TabReorderPreview(rows: rows, draggedID: rows[1].item.id, destinationBoundary: 6, sourceInThisSection: true, isDestination: true)
        #expect(down.draggedRowCount == 3 && down.gapIndex == 3)
        #expect(offsets(down, rows) == [0, 0, 0, 0, -3, -3])
        #expect(rows.map { down.containsDraggedRow(id: $0.item.id) } == [false, true, true, true, false, false])
        let up = TabReorderPreview(rows: rows, draggedID: rows[1].item.id, destinationBoundary: 0, sourceInThisSection: true, isDestination: true)
        #expect(offsets(up, rows) == [3, 0, 0, 0, 0, 0])
        for boundary in 1...4 {
            let own = TabReorderPreview(rows: rows, draggedID: rows[1].item.id, destinationBoundary: boundary, sourceInThisSection: true, isDestination: true)
            #expect(own.gapIndex == 1)
            #expect(offsets(own, rows) == [0, 0, 0, 0, 0, 0])
        }
    }

    @Test func crossSectionCollapsesSourceAndOpensDestination() {
        let rows = rows(depths: [0, 1, 0, 0])
        let source = TabReorderPreview(rows: rows, draggedID: rows[0].item.id, destinationBoundary: nil, sourceInThisSection: true, isDestination: false)
        #expect(source.gapIndex == nil && source.draggedRowCount == 2)
        #expect(offsets(source, rows) == [0, 0, -2, -2])
        let dest = TabReorderPreview(rows: rows, draggedID: UUID(), destinationBoundary: 2, sourceInThisSection: false, isDestination: true)
        #expect(dest.gapIndex == 2 && dest.draggedRowCount == 1)
        #expect(offsets(dest, rows) == [0, 0, 1, 1])
        #expect(rows.allSatisfy { !dest.containsDraggedRow(id: $0.item.id) })
    }

    @Test func intoFolderCollapsesButSelfAndDescendantsDoNotMove() {
        let rows = rows(depths: [0, 1, 0, 0])
        let valid = TabReorderPreview(rows: rows, draggedID: rows[0].item.id, destinationBoundary: 2, sourceInThisSection: true, isDestination: true, isIntoFolder: true)
        #expect(valid.gapIndex == nil)
        #expect(offsets(valid, rows) == [0, 0, -2, -2])
        for boundary in 0...1 {
            let invalid = TabReorderPreview(rows: rows, draggedID: rows[0].item.id, destinationBoundary: boundary, sourceInThisSection: true, isDestination: true, isIntoFolder: true)
            #expect(invalid.gapIndex == nil)
            #expect(offsets(invalid, rows) == [0, 0, 0, 0])
        }
        let external = TabReorderPreview(rows: rows, draggedID: UUID(), destinationBoundary: 2, sourceInThisSection: false, isDestination: true, isIntoFolder: true)
        #expect(external.gapIndex == nil)
        #expect(offsets(external, rows) == [0, 0, 0, 0])
    }

    @Test func boundariesClampAndMissingRowsAreConservative() {
        let rows = rows()
        let low = TabReorderPreview(rows: rows, draggedID: rows[2].item.id, destinationBoundary: Int.min, sourceInThisSection: true, isDestination: true)
        #expect(low.gapIndex == 0 && offsets(low, rows) == [1, 1, 0, 0])
        let high = TabReorderPreview(rows: rows, draggedID: rows[1].item.id, destinationBoundary: Int.max, sourceInThisSection: true, isDestination: true)
        #expect(high.gapIndex == 3 && offsets(high, rows) == [0, 0, -1, -1])
        let missing = TabReorderPreview(rows: rows, draggedID: UUID(), destinationBoundary: 0, sourceInThisSection: true, isDestination: true)
        #expect(missing.gapIndex == nil && missing.draggedRowCount == 0)
        #expect(offsets(missing, rows) == [0, 0, 0, 0])
        let empty = TabReorderPreview(rows: [], draggedID: UUID(), destinationBoundary: Int.max, sourceInThisSection: false, isDestination: true)
        #expect(empty.gapIndex == 0 && empty.draggedRowCount == 1)
        let idle = TabReorderPreview(rows: rows, draggedID: UUID(), destinationBoundary: nil, sourceInThisSection: false, isDestination: true)
        #expect(idle.gapIndex == nil && offsets(idle, rows) == [0, 0, 0, 0])
        #expect(idle.rowOffset(for: UUID()) == 0)
    }
}
