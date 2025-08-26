//
//  TabDragContainerView.swift
//  Pulse
//
//  AppKit-powered drag container for precise tab drag & drop control
//

import SwiftUI
import AppKit

struct TabDragContainerView<Content: View>: NSViewRepresentable {
    let content: Content
    let dragManager: TabDragManager
    let onDragCompleted: (DragOperation) -> Void
    
    init(dragManager: TabDragManager, onDragCompleted: @escaping (DragOperation) -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.dragManager = dragManager
        self.onDragCompleted = onDragCompleted
    }
    
    func makeNSView(context: Context) -> TabDragNSView {
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
            hostingView.bottomAnchor.constraint(equalTo: dragView.bottomAnchor)
        ])
        
        return dragView
    }
    
    func updateNSView(_ nsView: TabDragNSView, context: Context) {
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
    
    required init?(coder: NSCoder) {
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
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
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
        // This method will be enhanced to calculate insertion points
        // based on the location and the current view hierarchy
        
        // For now, we'll implement basic logic that will be expanded
        Task { @MainActor in
            let (container, index, spaceId) = calculateDropTarget(at: location)
            dragManager.updateDragTarget(container: container, insertionIndex: index, spaceId: spaceId)
            
            // Update insertion line position
            if let insertionFrame = calculateInsertionLineFrame(at: location, index: index) {
                dragManager.updateInsertionLine(frame: insertionFrame)
            }
        }
    }
    
    private func calculateDropTarget(at location: NSPoint) -> (TabDragManager.DragContainer, Int, UUID?) {
        // This is where we'll implement the logic to determine:
        // 1. Which container (essentials, space pinned, space regular) we're over
        // 2. What index position we should insert at
        // 3. Which space ID (if applicable)
        
        // For now, return placeholder values
        // This will be enhanced when we integrate with the actual UI components
        return (.none, -1, nil)
    }
    
    private func calculateInsertionLineFrame(at location: NSPoint, index: Int) -> CGRect? {
        // Calculate where the insertion line should appear
        // This will be enhanced with actual geometry calculations
        return nil
    }
}