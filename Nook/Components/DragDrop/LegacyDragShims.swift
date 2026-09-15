//
//  LegacyDragShims.swift
//  Nook
//
//  Types the old tab model still compiles against: `TabManager.handleDragOperation` and the
//  pre-migration `SpaceTitle` drop handler. Nothing in the new sidebar sets or reads them.
//  Delete in task Z together with TabManager.
//

import SwiftUI

enum TabDragManager {
    enum DragContainer: Equatable {
        case none
        case essentials
        case spacePinned(UUID) // space ID
        case spaceRegular(UUID) // space ID
        case folder(UUID) // folder ID
    }
}

extension Notification.Name {
    static let tabManagerDidLoadInitialData = Notification.Name("tabManagerDidLoadInitialData")
}

struct DragOperation {
    let tab: Tab
    let fromContainer: TabDragManager.DragContainer
    let fromIndex: Int
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int
    let toSpaceId: UUID?
}

/// Never produced. Kept so the old `SpaceTitle` drop handler compiles until T2 merges.
struct PendingDrop: Equatable {
    let item: NookDragItem
    let targetZone: DropZoneID
}

extension DropZoneID {
    /// Old zone name for a space's pinned section.
    static func spacePinned(_ spaceID: UUID) -> DropZoneID { .section(.pinned(spaceID: spaceID)) }
}

extension NookDragSessionManager {
    var pendingDrop: PendingDrop? {
        get { nil }
        set {}
    }

    func makeDragOperation(from drop: PendingDrop, tab: Tab) -> DragOperation {
        DragOperation(tab: tab, fromContainer: .none, fromIndex: 0, toContainer: .none, toIndex: 0, toSpaceId: nil)
    }
}
