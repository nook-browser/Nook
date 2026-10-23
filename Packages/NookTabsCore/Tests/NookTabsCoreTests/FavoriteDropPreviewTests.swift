// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct FavoriteDropPreviewTests {
    @Test func incomingFavoriteOccupiesItsFinalSlot() {
        for count in 0...8 {
            let ids = (0..<count).map { _ in UUID() }
            let incoming = UUID()
            for boundary in 0...count {
                let preview = FavoriteDropPreview(itemIDs: ids, draggedID: incoming, destinationBoundary: boundary)
                var expected = ids
                expected.insert(incoming, at: boundary)
                #expect(preview.itemIDs == expected)
                #expect(preview.itemIDs.count == count + 1)
                #expect(preview.placeholderID == incoming)
            }
        }
    }

    @Test func reorderMatchesDropAnchorWithoutAnExtraCell() {
        for count in 1...8 {
            let ids = (0..<count).map { _ in UUID() }
            for dragged in ids {
                for boundary in 0...count {
                    // dropOnFavorites moves after the last non-source ID in this prefix.
                    let anchor = ids.prefix(boundary).last { $0 != dragged }
                    var committed = ids.filter { $0 != dragged }
                    let index = anchor.flatMap { committed.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                    committed.insert(dragged, at: index)
                    let preview = FavoriteDropPreview(itemIDs: ids, draggedID: dragged, destinationBoundary: boundary)
                    #expect(preview.itemIDs == committed)
                    #expect(preview.itemIDs.count == count)
                    #expect(Set(preview.itemIDs).count == count)
                }
            }
        }
    }
}
