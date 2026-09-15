//
//  T2PreMergeShims.swift
//  Nook
//
//  Stand-ins for the T1 sidebar API (rebuild/t1-sidebar bee1686) so the T2 branch builds on its
//  own. Every declaration here duplicates a real T1 member: delete this file when T1 and T2 merge.
//

import NookTabsCore
import SwiftUI

extension SpaceView {
    init(spaceID: UUID, isActive: Bool, isSidebarHovered: Binding<Bool>) {
        self.init(
            space: Space(id: spaceID, name: ""), isActive: isActive, isSidebarHovered: isSidebarHovered,
            onActivateTab: { _ in }, onCloseTab: { _ in }, onMuteTab: { _ in })
    }
}

extension DropZoneID {
    static func target(_ parent: Parent) -> DropZoneID {
        switch parent {
        case .pinned(let spaceID): return .spacePinned(spaceID)
        case .tabs(let spaceID): return .spaceRegular(spaceID)
        case .folder(let itemID): return .folder(itemID)
        case .favorites: return .essentials
        }
    }
}

extension NookDropZoneHostView {
    init(zoneID: DropZoneID, manager: NookDragSessionManager, onDrop: @escaping (UUID) -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(zoneID: zoneID, isVertical: true, manager: manager, content: content)
    }
}
