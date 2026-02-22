//
//  TabDragManager.swift
//  Nook
//
//  Drag container types and operation structs used by TabManager.handleDragOperation().
//

import SwiftUI

@MainActor
class TabDragManager: ObservableObject {
    static let shared = TabDragManager()

    enum DragContainer: Equatable {
        case none
        case essentials
        case spacePinned(UUID) // space ID
        case spaceRegular(UUID) // space ID
        case folder(UUID) // folder ID
    }
}

extension Notification.Name {
    static let tabDragDidEnd = Notification.Name("tabDragDidEnd")
    static let tabManagerDidLoadInitialData = Notification.Name("tabManagerDidLoadInitialData")
}

// MARK: - Drag Operation Result
struct DragOperation {
    let tab: Tab
    let fromContainer: TabDragManager.DragContainer
    let fromIndex: Int
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int
    let toSpaceId: UUID?

    var isMovingBetweenContainers: Bool {
        return fromContainer != toContainer
    }

    var isReordering: Bool {
        return fromContainer == toContainer && fromIndex != toIndex
    }
}
