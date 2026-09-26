// Licensed under GPL-3.0. See LICENSE.
//
//  NookDropZoneHostView.swift
//  Nook
//

import SwiftUI
import AppKit
import NookDesign

// MARK: - Drop Zone Coordinator

@MainActor
class NookDropZoneCoordinator: NSObject {
    var zoneID: DropZoneID
    var layout: DropLayout
    var onDrop: (UUID, DropPosition) -> Void
    var reduceMotion: Bool
    let manager: NookDragSessionManager

    init(zoneID: DropZoneID, layout: DropLayout, manager: NookDragSessionManager, reduceMotion: Bool, onDrop: @escaping (UUID, DropPosition) -> Void) {
        self.zoneID = zoneID
        self.layout = layout
        self.manager = manager
        self.reduceMotion = reduceMotion
        self.onDrop = onDrop
    }
}

// MARK: - NookDropZoneNSView

class NookDropZoneNSView: NSView {
    weak var coordinator: NookDropZoneCoordinator?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator = coordinator, accepts(sender, in: coordinator) else { return [] }
        MainActor.assumeIsolated {
            coordinator.manager.cursorEnteredZone(coordinator.zoneID)
        }
        updatePosition(sender)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator, accepts(sender, in: coordinator) else { return [] }
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
        if case .favorites = coordinator.zoneID, item.isFolder == true { return false }
        let point = flippedPoint(sender)
        let width = bounds.width
        MainActor.assumeIsolated {
            let position = NookDragSessionManager.position(in: coordinator.zoneID, layout: coordinator.layout, point: point, width: width)
            coordinator.manager.hapticFeedback(.generic)
            let targetFrame = screenFrame(for: position, layout: coordinator.layout)
            coordinator.manager.performDrop(
                item: item,
                position: position,
                destinationFrame: targetFrame,
                reduceMotion: coordinator.reduceMotion
            ) {
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

    private func accepts(_ sender: NSDraggingInfo, in coordinator: NookDropZoneCoordinator) -> Bool {
        guard let item = NookDragItem.fromPasteboard(sender.draggingPasteboard) else { return false }
        if case .favorites = coordinator.zoneID, item.isFolder == true { return false }
        return true
    }

    private func updatePosition(_ sender: NSDraggingInfo) {
        guard let coordinator = coordinator else { return }
        let point = flippedPoint(sender)
        let width = bounds.width
        MainActor.assumeIsolated {
            coordinator.manager.updateDropPosition(for: coordinator.zoneID, layout: coordinator.layout, localPoint: point, zoneWidth: width)
        }
    }

    /// Returns the destination's screen-space frame so the independent preview window can settle
    /// into the same row or tile that will be revealed after the model update.
    private func screenFrame(for position: DropPosition, layout: DropLayout) -> CGRect? {
        let localTopLeftFrame: CGRect
        switch layout {
        case .grid(_, let columns):
            let cols = max(1, columns)
            let cellWidth = bounds.width / CGFloat(cols)
            let rowHeight = NookDesign.Size.essentialsTile + NookDesign.Spacing.sm
            let col = position.index % cols
            let row = position.index / cols
            let tile = NookDesign.Size.essentialsTile
            localTopLeftFrame = CGRect(
                x: CGFloat(col) * cellWidth + max(0, (cellWidth - tile) / 2),
                y: CGFloat(row) * rowHeight,
                width: tile,
                height: tile
            )
        case .rows:
            let step = NookDesign.Size.row + NookDesign.Spacing.rowGap
            let y = CGFloat(position.index) * step + (position.placement == .after ? step : 0)
            localTopLeftFrame = CGRect(x: bounds.minX, y: y, width: bounds.width, height: NookDesign.Size.row)
        case .none:
            localTopLeftFrame = bounds
        }

        let localAppKitFrame = CGRect(
            x: localTopLeftFrame.minX,
            y: bounds.height - localTopLeftFrame.maxY,
            width: localTopLeftFrame.width,
            height: localTopLeftFrame.height
        )
        guard let window else { return nil }
        return window.convertToScreen(convert(localAppKitFrame, to: nil))
    }
}

// MARK: - Invisible Drop Zone Anchor (NSViewRepresentable)

private struct DropZoneAnchor: NSViewRepresentable {
    let zoneID: DropZoneID
    let layout: DropLayout
    let manager: NookDragSessionManager
    let onDrop: (UUID, DropPosition) -> Void
    let reduceMotion: Bool

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
        context.coordinator.reduceMotion = reduceMotion
    }

    func makeCoordinator() -> NookDropZoneCoordinator {
        NookDropZoneCoordinator(zoneID: zoneID, layout: layout, manager: manager, reduceMotion: reduceMotion, onDrop: onDrop)
    }
}

// MARK: - NookDropZoneHostView

/// Makes its content a drop target. `onDrop` runs on the main actor with the dragged item id.
struct NookDropZoneHostView<Content: View>: View {
    let zoneID: DropZoneID
    let layout: DropLayout
    let manager: NookDragSessionManager
    let onDrop: (UUID, DropPosition) -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
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
                    onDrop: onDrop,
                    reduceMotion: accessibilityReduceMotion
                )
            )
    }
}
