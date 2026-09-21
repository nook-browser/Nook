// Licensed under GPL-3.0. See LICENSE.
//
//  NookDragSourceView.swift
//  Nook
//

import SwiftUI
import AppKit

// MARK: - Drag Source Coordinator (NSDraggingSource)

@MainActor
final class NookDragSourceCoordinator: NSObject, NSDraggingSource {
    var item: NookDragItem
    var icon: Image?
    var zoneID: DropZoneID
    let manager: NookDragSessionManager

    init(item: NookDragItem, icon: Image?, zoneID: DropZoneID, manager: NookDragSessionManager) {
        self.item = item
        self.icon = icon
        self.zoneID = zoneID
        self.manager = manager
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : .copy
    }

    // NSDraggingSource is declared NS_SWIFT_UI_ACTOR, so these run on the main actor
    // statically. Marking them nonisolated and hopping back with assumeIsolated added a
    // dynamic executor check that segfaults after any ObjC exception has unwound a
    // main-actor task (see ExternalMiniWindowManager.items(for:) for the same fix).
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        manager.updateCursorScreenPosition(screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == [] {
            manager.cancelDrag()
        }
    }
}

// MARK: - DragSourceNSView

final class NookDragSourceNSView: NSView {
    var coordinator: NookDragSourceCoordinator?
    private(set) var registrationId: UUID?

    func registerWithManager() {
        guard let coordinator = coordinator else { return }
        let id = UUID()
        registrationId = id
        coordinator.manager.registerDragSource(self, id: id)
    }

    func unregisterFromManager() {
        guard let id = registrationId, let coordinator = coordinator else { return }
        coordinator.manager.unregisterDragSource(id: id)
        registrationId = nil
    }

    func initiateDrag(with event: NSEvent) {
        guard let coordinator = coordinator else { return }

        // Capture screen position from the event for preview window positioning
        let screenPoint: NSPoint
        if let window = self.window {
            screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = NSEvent.mouseLocation
        }

        coordinator.manager.beginDrag(
            item: coordinator.item,
            icon: coordinator.icon,
            from: coordinator.zoneID,
            cursorScreenPoint: screenPoint
        )

        let pasteboardItem = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(coordinator.item) {
            pasteboardItem.setData(data, forType: .nookTabItem)
        }
        pasteboardItem.setString(coordinator.item.tabId.uuidString, forType: .string)

        let transparentImage = NSImage(size: NSSize(width: 1, height: 1))

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(
            NSRect(x: 0, y: 0, width: 1, height: 1),
            contents: transparentImage
        )

        beginDraggingSession(with: [draggingItem], event: event, source: coordinator)
    }
}

// MARK: - Invisible Anchor (NSViewRepresentable)

private struct DragSourceAnchor: NSViewRepresentable {
    let item: NookDragItem
    let icon: Image?
    let zoneID: DropZoneID
    let manager: NookDragSessionManager

    func makeNSView(context: Context) -> NookDragSourceNSView {
        let view = NookDragSourceNSView()
        view.coordinator = context.coordinator
        view.registerWithManager()
        return view
    }

    func updateNSView(_ nsView: NookDragSourceNSView, context: Context) {
        context.coordinator.item = item
        context.coordinator.icon = icon
        context.coordinator.zoneID = zoneID
    }

    static func dismantleNSView(_ nsView: NookDragSourceNSView, coordinator: NookDragSourceCoordinator) {
        nsView.unregisterFromManager()
    }

    func makeCoordinator() -> NookDragSourceCoordinator {
        NookDragSourceCoordinator(item: item, icon: icon, zoneID: zoneID, manager: manager)
    }
}

// MARK: - NookDragSourceView

struct NookDragSourceView<Content: View>: View {
    let item: NookDragItem
    let icon: Image?
    let zoneID: DropZoneID
    let manager: NookDragSessionManager
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                DragSourceAnchor(
                    item: item,
                    icon: icon,
                    zoneID: zoneID,
                    manager: manager
                )
            )
    }
}
