//
//  TabDragContainerView.swift
//  Nook
//
//  AppKit-powered drag container for precise tab drag & drop control
//

import AppKit
import SwiftUI

struct TabDragContainerView<Content: View>: NSViewRepresentable {
    let content: Content
    let dragManager: TabDragManager
    let onDragCompleted: (DragOperation) -> Void

    init(dragManager: TabDragManager, onDragCompleted: @escaping (DragOperation) -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.dragManager = dragManager
        self.onDragCompleted = onDragCompleted
    }

    func makeNSView(context _: Context) -> TabDragNSView {
        let dragView = TabDragNSView(dragManager: dragManager)
        dragView.onDragCompleted = onDragCompleted

        // Embed SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        dragView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: dragView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: dragView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: dragView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: dragView.bottomAnchor),
        ])

        return dragView
    }

    func updateNSView(_ nsView: TabDragNSView, context _: Context) {
        // Update the hosting view content if needed
        if let hostingView = nsView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

class TabDragNSView: NSView {
    let dragManager: TabDragManager
    var onDragCompleted: ((DragOperation) -> Void)?

    private var dragTrackingArea: NSTrackingArea?

    init(dragManager: TabDragManager) {
        self.dragManager = dragManager
        super.init(frame: .zero)
        setupDragHandling()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupDragHandling() {
        // Register for drag operations
        registerForDraggedTypes([.string, .fileURL])

        // Setup tracking area for mouse events
        updateTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea = dragTrackingArea {
            removeTrackingArea(trackingArea)
        }

        dragTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = dragTrackingArea {
            addTrackingArea(trackingArea)
        }
    }

    // MARK: - Drag Source

    override func mouseDragged(with event: NSEvent) {
        // This will be handled by individual tab views that call startDrag
        super.mouseDragged(with: event)
    }

    // MARK: - Drag Destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dragManager.isDragging else { return [] }

        let location = convert(sender.draggingLocation, from: nil)
        updateDropTarget(at: location)

        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dragManager.isDragging else { return [] }

        let location = convert(sender.draggingLocation, from: nil)
        updateDropTarget(at: location)

        return .move
    }

    override func draggingExited(_: NSDraggingInfo?) {
        // Clear drop target when drag exits
        Task { @MainActor in
            dragManager.updateDragTarget(container: .none, insertionIndex: -1)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard dragManager.isDragging else { return false }

        let location = convert(sender.draggingLocation, from: nil)
        updateDropTarget(at: location)

        // Commit the drag operation
        Task { @MainActor in
            if let operation = dragManager.endDrag(commit: true) {
                onDragCompleted?(operation)
            }
        }

        return true
    }

    private func updateDropTarget(at location: NSPoint) {
        // The TabDragManager already has all the information we need!
        // The sidebar components (PinnedGrid, SpaceView) are already calling
        // dragManager.updateDragTarget() and dragManager.updateInsertionLine()
        // with the correct values. We just need to let them handle it.

        // This container view doesn't need to calculate frames - the individual
        // UI components know their own geometry and handle insertion line positioning
        Task { @MainActor in
            // Simple fallback - let the specialized components handle precise positioning
            print("🎯 [TabDragContainerView] Drag at \(location) - letting specialized components handle targeting")
        }
    }
}
