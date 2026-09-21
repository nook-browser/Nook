// Licensed under GPL-3.0. See LICENSE.
//
//  NookDropZoneHostView.swift
//  Nook
//

import SwiftUI
import AppKit

// MARK: - Drop Zone Coordinator

@MainActor
class NookDropZoneCoordinator: NSObject {
    var zoneID: DropZoneID
    var layout: DropLayout
    var onDrop: (UUID, DropPosition) -> Void
    let manager: NookDragSessionManager

    init(zoneID: DropZoneID, layout: DropLayout, manager: NookDragSessionManager, onDrop: @escaping (UUID, DropPosition) -> Void) {
        self.zoneID = zoneID
        self.layout = layout
        self.manager = manager
        self.onDrop = onDrop
    }
}

// MARK: - NookDropZoneNSView

class NookDropZoneNSView: NSView {
    weak var coordinator: NookDropZoneCoordinator?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator = coordinator else { return [] }
        MainActor.assumeIsolated {
            coordinator.manager.cursorEnteredZone(coordinator.zoneID)
        }
        updatePosition(sender)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updatePosition(sender)
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard let coordinator = coordinator else { return }
        MainActor.assumeIsolated {
            coordinator.manager.cursorExitedZone(coordinator.zoneID)
        }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator = coordinator,
              let item = NookDragItem.fromPasteboard(sender.draggingPasteboard) else { return false }
        let point = flippedPoint(sender)
        let width = bounds.width
        MainActor.assumeIsolated {
            let position = NookDragSessionManager.position(in: coordinator.zoneID, layout: coordinator.layout, point: point, width: width)
            coordinator.manager.hapticFeedback(.generic)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                coordinator.manager.clearDrag()
                coordinator.onDrop(item.tabId, position)
            }
        }
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

    private func flippedPoint(_ sender: NSDraggingInfo) -> CGPoint {
        let localPoint = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
    }

    private func updatePosition(_ sender: NSDraggingInfo) {
        guard let coordinator = coordinator else { return }
        let point = flippedPoint(sender)
        let width = bounds.width
        MainActor.assumeIsolated {
            coordinator.manager.updateDropPosition(for: coordinator.zoneID, layout: coordinator.layout, localPoint: point, zoneWidth: width)
        }
    }
}

// MARK: - Invisible Drop Zone Anchor (NSViewRepresentable)

private struct DropZoneAnchor: NSViewRepresentable {
    let zoneID: DropZoneID
    let layout: DropLayout
    let manager: NookDragSessionManager
    let onDrop: (UUID, DropPosition) -> Void

    func makeNSView(context: Context) -> NookDropZoneNSView {
        let view = NookDropZoneNSView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes([.nookTabItem, .string])
        return view
    }

    func updateNSView(_ nsView: NookDropZoneNSView, context: Context) {
        context.coordinator.zoneID = zoneID
        context.coordinator.layout = layout
        context.coordinator.onDrop = onDrop
    }

    func makeCoordinator() -> NookDropZoneCoordinator {
        NookDropZoneCoordinator(zoneID: zoneID, layout: layout, manager: manager, onDrop: onDrop)
    }
}

// MARK: - NookDropZoneHostView

/// Makes its content a drop target. `onDrop` runs on the main actor with the dragged item id.
struct NookDropZoneHostView<Content: View>: View {
    let zoneID: DropZoneID
    let layout: DropLayout
    let manager: NookDragSessionManager
    let onDrop: (UUID, DropPosition) -> Void
    @ViewBuilder let content: () -> Content

    init(zoneID: DropZoneID, layout: DropLayout, manager: NookDragSessionManager,
         onDrop: @escaping (UUID, DropPosition) -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.zoneID = zoneID
        self.layout = layout
        self.manager = manager
        self.onDrop = onDrop
        self.content = content
    }

    /// A row-less target such as a space title or switcher item.
    init(zoneID: DropZoneID, manager: NookDragSessionManager,
         onDrop: @escaping (UUID) -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(zoneID: zoneID, layout: .none, manager: manager, onDrop: { id, _ in onDrop(id) }, content: content)
    }

    var body: some View {
        content()
            .background(
                DropZoneAnchor(
                    zoneID: zoneID,
                    layout: layout,
                    manager: manager,
                    onDrop: onDrop
                )
            )
    }
}
