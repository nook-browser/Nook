//
//  NookDropZoneHostView.swift
//  Nook
//
//  Pure SwiftUI wrapper that registers an invisible NSView as NSDraggingDestination.
//  Content renders natively in SwiftUI layout, preserving flexible sizing.
//

import SwiftUI
import AppKit

// MARK: - Drop Zone Coordinator

@MainActor
class NookDropZoneCoordinator: NSObject {
    var zoneID: DropZoneID
    var isVertical: Bool
    let manager: NookDragSessionManager

    init(zoneID: DropZoneID, isVertical: Bool, manager: NookDragSessionManager) {
        self.zoneID = zoneID
        self.isVertical = isVertical
        self.manager = manager
    }
}

// MARK: - NookDropZoneNSView

class NookDropZoneNSView: NSView {
    weak var coordinator: NookDropZoneCoordinator?

    override func layout() {
        super.layout()
        guard let coordinator = coordinator,
              let window = self.window,
              let contentView = window.contentView else { return }

        let frameInWindow = convert(bounds, to: nil)
        let contentHeight = contentView.bounds.height
        let flipped = CGRect(
            x: frameInWindow.origin.x,
            y: contentHeight - frameInWindow.maxY,
            width: frameInWindow.width,
            height: frameInWindow.height
        )
        Task { @MainActor in
            coordinator.manager.zoneFrames[coordinator.zoneID] = flipped
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator = coordinator else { return [] }
        Task { @MainActor in
            coordinator.manager.cursorEnteredZone(coordinator.zoneID)
        }
        updateInsertionIndex(sender)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateInsertionIndex(sender)
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard let coordinator = coordinator else { return }
        Task { @MainActor in
            coordinator.manager.cursorExitedZone(coordinator.zoneID)
        }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator = coordinator else { return false }
        let zoneID = coordinator.zoneID
        let mgr = coordinator.manager

        Task { @MainActor in
            let targetIndex = mgr.insertionIndex[zoneID] ?? (mgr.itemCounts[zoneID] ?? 0)

            if mgr.sourceZone == zoneID {
                mgr.completeReorder()
            } else {
                mgr.completeDrop(targetZone: zoneID, targetIndex: targetIndex)
            }
        }
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

    // MARK: - Helpers

    private func updateInsertionIndex(_ sender: NSDraggingInfo) {
        guard let coordinator = coordinator else { return }
        let localPoint = convert(sender.draggingLocation, from: nil)
        let flippedPoint = CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
        Task { @MainActor in
            coordinator.manager.updateInsertionIndex(
                for: coordinator.zoneID,
                localPoint: flippedPoint,
                isVertical: coordinator.isVertical
            )
        }
    }
}

// MARK: - Invisible Drop Zone Anchor (NSViewRepresentable)

private struct DropZoneAnchor: NSViewRepresentable {
    let zoneID: DropZoneID
    let isVertical: Bool
    let manager: NookDragSessionManager

    func makeNSView(context: Context) -> NookDropZoneNSView {
        let view = NookDropZoneNSView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes([.nookTabItem, .string])
        return view
    }

    func updateNSView(_ nsView: NookDropZoneNSView, context: Context) {
        context.coordinator.zoneID = zoneID
        context.coordinator.isVertical = isVertical
    }

    func makeCoordinator() -> NookDropZoneCoordinator {
        NookDropZoneCoordinator(zoneID: zoneID, isVertical: isVertical, manager: manager)
    }
}

// MARK: - NookDropZoneHostView (Pure SwiftUI)

/// Wraps content with a transparent drop zone anchor. Content renders natively in SwiftUI,
/// preserving flexible sizing, grids, stacks, and all layout behaviour.
struct NookDropZoneHostView<Content: View>: View {
    let zoneID: DropZoneID
    let isVertical: Bool
    let manager: NookDragSessionManager
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                DropZoneAnchor(
                    zoneID: zoneID,
                    isVertical: isVertical,
                    manager: manager
                )
            )
    }
}
