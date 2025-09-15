//
//  SimpleDnD.swift
//  Nook
//
//  Lightweight Ora-style drag & drop for the sidebar.
//  Uses NSItemProvider with Tab UUIDs and simple DropDelegates
//  to reorder/move tabs by calling TabManager directly.
//

import SwiftUI
import AppKit

// MARK: - Target Section

enum SidebarTargetSection: Equatable {
    case essentials
    case spacePinned(UUID)    // spaceId
    case spaceRegular(UUID)   // spaceId
}

// MARK: - Helpers

private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
}

@MainActor
private func containerFor(tab: Tab, tabManager: TabManager) -> (TabDragManager.DragContainer, Int, UUID?) {
    if tab.spaceId == nil {
        // Essentials (global pinned)
        return (.essentials, tab.index, nil)
    } else if let sid = tab.spaceId {
        // Distinguish space-pinned vs regular by membership
        let pinned = tabManager.spacePinnedTabs(for: sid)
        if pinned.contains(where: { $0.id == tab.id }) {
            return (.spacePinned(sid), tab.index, sid)
        } else {
            return (.spaceRegular(sid), tab.index, sid)
        }
    }
    return (.none, -1, nil)
}

private func targetContainer(from section: SidebarTargetSection) -> (TabDragManager.DragContainer, UUID?) {
    switch section {
    case .essentials:
        return (.essentials, nil)
    case .spacePinned(let sid):
        return (.spacePinned(sid), sid)
    case .spaceRegular(let sid):
        return (.spaceRegular(sid), sid)
    }
}

// MARK: - Item Drop Delegate (reorder relative to an item)

@MainActor
struct SidebarTabDropDelegateSimple: DropDelegate {
    let item: Tab                          // target tab (to)
    @Binding var draggedItem: UUID?
    let targetSection: SidebarTargetSection
    let tabManager: TabManager

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let string = object as? String,
                let uuid = UUID(uuidString: string)
            else { return }

            DispatchQueue.main.async {
                let all = tabManager.allTabs()
                guard let from = all.first(where: { $0.id == uuid }) else { return }
                guard from.id != self.item.id else { return }

                let (fromContainer, fromIndex, _) = containerFor(tab: from, tabManager: tabManager)
                let (toContainer, toSpace) = targetContainer(from: self.targetSection)
                let toIndex = self.item.index

                let op = DragOperation(
                    tab: from,
                    fromContainer: fromContainer,
                    fromIndex: max(fromIndex, 0),
                    toContainer: toContainer,
                    toIndex: max(toIndex, 0),
                    toSpaceId: toSpace
                )
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tabManager.handleDragOperation(op)
                }
                self.draggedItem = uuid
                haptic(.alignment)
            }
        }
    }

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        draggedItem = nil
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        return true
    }
}

// MARK: - Section Drop Delegate (drop into section/empty area)

@MainActor
struct SidebarSectionDropDelegateSimple: DropDelegate {
    let itemsCount: () -> Int               // current count to append at end
    @Binding var draggedItem: UUID?
    let targetSection: SidebarTargetSection
    let tabManager: TabManager

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let string = object as? String,
                let uuid = UUID(uuidString: string)
            else { return }

            DispatchQueue.main.async {
                let all = tabManager.allTabs()
                guard let from = all.first(where: { $0.id == uuid }) else { return }

                let (fromContainer, fromIndex, _) = containerFor(tab: from, tabManager: tabManager)
                let (toContainer, toSpace) = targetContainer(from: self.targetSection)
                let toIndex = max(0, self.itemsCount())

                let op = DragOperation(
                    tab: from,
                    fromContainer: fromContainer,
                    fromIndex: max(fromIndex, 0),
                    toContainer: toContainer,
                    toIndex: toIndex,
                    toSpaceId: toSpace
                )
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tabManager.handleDragOperation(op)
                }
                self.draggedItem = uuid
                haptic(.alignment)
            }
        }
    }

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        draggedItem = nil
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        return true
    }
}

// MARK: - Drag Provider helper

extension View {
    func onTabDrag(_ id: UUID, draggedItem: Binding<UUID?>) -> some View {
        onDrag {
            draggedItem.wrappedValue = id
            return NSItemProvider(object: id.uuidString as NSString)
        }
    }
}
