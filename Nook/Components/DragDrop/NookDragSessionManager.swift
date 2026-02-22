//
//  NookDragSessionManager.swift
//  Nook
//
//

import SwiftUI
import AppKit
import Combine

// MARK: - Pending Drop

struct PendingDrop: Equatable {
    let item: NookDragItem
    let sourceZone: DropZoneID
    let sourceIndex: Int
    let targetZone: DropZoneID
    let targetIndex: Int
}

struct PendingReorder: Equatable {
    let item: NookDragItem
    let zone: DropZoneID
    let fromIndex: Int
    let toIndex: Int
}

// MARK: - Drag Session Manager

@MainActor
final class NookDragSessionManager: ObservableObject {
    static let shared = NookDragSessionManager()

    // --- Active drag state ---
    @Published var draggedItem: NookDragItem?
    @Published var draggedTab: Tab?
    @Published var sourceZone: DropZoneID?
    @Published var sourceIndex: Int?

    // --- Cursor tracking ---
    @Published var activeZone: DropZoneID?
    @Published var isOutsideWindow: Bool = false
    @Published var cursorLocation: CGPoint = .zero // window-flipped coords (top-left origin)
    @Published var cursorScreenLocation: NSPoint = .zero // raw screen coords for preview window

    // --- Insertion index per zone ---
    @Published var insertionIndex: [DropZoneID: Int] = [:]

    // --- Drop payloads ---
    @Published var pendingDrop: PendingDrop?
    @Published var pendingReorder: PendingReorder?

    // --- Geometry caches (set by zone views) ---
    var zoneFrames: [DropZoneID: CGRect] = [:]
    var itemCellSize: [DropZoneID: CGFloat] = [:]
    var itemCellSpacing: [DropZoneID: CGFloat] = [:]
    var itemCounts: [DropZoneID: Int] = [:]
    var gridColumnCount: [DropZoneID: Int] = [:]  // For grid zones (essentials)

    // --- Sidebar geometry (set by sidebar view, screen coordinates) ---
    @Published var sidebarScreenFrame: CGRect = .zero

    @Published var pinnedTabsConfig: PinnedTabsConfiguration = .large

    var isDragging: Bool { draggedItem != nil }

    /// Whether the cursor is within the sidebar bounds (horizontally).
    var isCursorInSidebar: Bool {
        guard sidebarScreenFrame.width > 0 else { return false }
        return cursorScreenLocation.x >= sidebarScreenFrame.minX &&
               cursorScreenLocation.x <= sidebarScreenFrame.maxX
    }

    /// Whether this is a same-zone sidebar reorder (not essentials grid).
    var isSidebarReorder: Bool {
        guard isDragging, let source = sourceZone, activeZone == source else { return false }
        switch source {
        case .spaceRegular, .spacePinned, .folder:
            return true
        case .essentials:
            return false
        }
    }

    // --- Preview window ---
    private var previewWindow: NookDragPreviewWindow?

    private func ensurePreviewWindow() {
        guard previewWindow == nil else { return }
        previewWindow = NookDragPreviewWindow(manager: self)
    }

    // --- Centralized drag source tracking ---
    private struct WeakDragSource {
        weak var view: NookDragSourceNSView?
    }
    private var registeredSources: [UUID: WeakDragSource] = [:]
    private var mouseMonitor: Any?
    private var activeDragSourceId: UUID?
    private var mouseDownPoint: NSPoint?
    private var mouseDownEvent: NSEvent?
    private var dragInitiatedFromMonitor: Bool = false
    private static let dragThreshold: CGFloat = 4

    func registerDragSource(_ view: NookDragSourceNSView, id: UUID) {
        registeredSources[id] = WeakDragSource(view: view)
        ensureEventMonitorActive()
    }

    func unregisterDragSource(id: UUID) {
        registeredSources.removeValue(forKey: id)
        // Clean up dead references
        registeredSources = registeredSources.filter { $0.value.view != nil }
        if registeredSources.isEmpty {
            removeEventMonitor()
        }
    }

    private func ensureEventMonitorActive() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleMonitoredEvent(event)
        }
    }

    private func removeEventMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Returns nil to consume the event, or the event to pass it through.
    nonisolated private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        // All work must happen on MainActor since we access @MainActor state
        // But event monitors are synchronous — we need to check state inline.
        // Since NookDragSessionManager is @MainActor and this is called from the main thread
        // event monitor (which runs on main thread), we can use MainActor.assumeIsolated.
        return MainActor.assumeIsolated {
            handleMonitoredEventOnMain(event)
        }
    }

    private func handleMonitoredEventOnMain(_ event: NSEvent) -> NSEvent? {
        // Don't interfere if we're already in a drag session
        if isDragging { return event }

        switch event.type {
        case .leftMouseDown:
            // Check if mouseDown is within any registered drag source
            activeDragSourceId = nil
            mouseDownPoint = nil
            mouseDownEvent = nil
            dragInitiatedFromMonitor = false

            for (id, source) in registeredSources {
                guard let view = source.view, let window = view.window, event.window == window else { continue }
                let localPoint = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(localPoint) {
                    activeDragSourceId = id
                    mouseDownPoint = event.locationInWindow
                    mouseDownEvent = event
                    break
                }
            }
            return event // Always pass through mouseDown (SwiftUI buttons need it)

        case .leftMouseDragged:
            guard let sourceId = activeDragSourceId,
                  let startPoint = mouseDownPoint,
                  !dragInitiatedFromMonitor,
                  let source = registeredSources[sourceId]?.view else {
                return event
            }

            let current = event.locationInWindow
            let distance = hypot(current.x - startPoint.x, current.y - startPoint.y)

            guard distance >= Self.dragThreshold else { return event }

            dragInitiatedFromMonitor = true
            // Initiate the AppKit drag session on the source view
            source.initiateDrag(with: event)
            return nil // Consume this mouseDragged event

        case .leftMouseUp:
            activeDragSourceId = nil
            mouseDownPoint = nil
            mouseDownEvent = nil
            dragInitiatedFromMonitor = false
            return event

        default:
            return event
        }
    }

    // MARK: - Drag Lifecycle

    func beginDrag(item: NookDragItem, tab: Tab, from zone: DropZoneID, at index: Int) {
        print("🚀 [DragSession] beginDrag: \(item.title) from \(zone) at \(index)")
        ensurePreviewWindow()
        draggedItem = item
        draggedTab = tab
        sourceZone = zone
        sourceIndex = index
        activeZone = zone
        isOutsideWindow = false
        pendingDrop = nil
        pendingReorder = nil
        insertionIndex = [:]
        hapticFeedback(.alignment)
    }

    /// Called continuously by the drag source's draggingSession(_:movedTo:).
    nonisolated func updateCursorScreenPosition(_ screenPoint: NSPoint) {
        Task { @MainActor in
            self._updateCursorScreenPosition(screenPoint)
        }
    }

    private func _updateCursorScreenPosition(_ screenPoint: NSPoint) {
        cursorScreenLocation = screenPoint

        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NookDragPreviewWindow) }),
              let contentView = window.contentView else { return }

        // Screen -> window
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        // Window (bottom-left origin) -> flipped (top-left origin, matching SwiftUI)
        let flipped = CGPoint(x: windowPoint.x, y: contentView.bounds.height - windowPoint.y)
        cursorLocation = flipped

        // Outside window detection
        let inWindow = window.frame.contains(screenPoint)
        if isOutsideWindow != !inWindow {
            isOutsideWindow = !inWindow
            if isOutsideWindow {
                activeZone = nil
            }
            hapticFeedback(.levelChange)
        }
    }

    /// Called by drop zone delegates on draggingEntered.
    func cursorEnteredZone(_ zone: DropZoneID) {
        guard isDragging else { return }
        if activeZone != zone {
            activeZone = zone
            isOutsideWindow = false
            hapticFeedback(.alignment)
        }
    }

    /// Called by drop zone delegates on draggingExited.
    func cursorExitedZone(_ zone: DropZoneID) {
        guard isDragging, activeZone == zone else { return }
        activeZone = nil
        insertionIndex[zone] = nil
    }

    /// Called by drop zone delegates on draggingUpdated.
    func updateInsertionIndex(for zone: DropZoneID, localPoint: CGPoint, isVertical: Bool) {
        guard isDragging else { return }

        let cellSize = itemCellSize[zone] ?? 36
        let spacing = itemCellSpacing[zone] ?? 2
        let count = itemCounts[zone] ?? 0

        var idx: Int

        if let cols = gridColumnCount[zone], cols > 0 {
            // Grid layout (essentials): compute row + column from 2D position
            // Use actual zone width divided by column count for column width
            let zoneWidth = zoneFrames[zone]?.width ?? CGFloat(cols) * (cellSize + spacing)
            let colWidth = zoneWidth / CGFloat(cols)
            let rowHeight = cellSize + spacing
            let col = min(max(0, Int(localPoint.x / colWidth)), cols - 1)
            let row = max(0, Int(localPoint.y / rowHeight))
            idx = row * cols + col
        } else {
            // Linear layout (vertical or horizontal)
            let offset = isVertical ? localPoint.y : localPoint.x
            let step = cellSize + spacing
            if step > 0 {
                idx = Int(round(offset / step))
            } else {
                idx = 0
            }
        }

        // Clamp
        if sourceZone == zone {
            idx = max(0, min(idx, count - 1))
        } else {
            idx = max(0, min(idx, count))
        }

        let oldIdx = insertionIndex[zone]
        if oldIdx != idx {
            insertionIndex[zone] = idx
            hapticFeedback(.alignment)
        }
    }

    // MARK: - Drop

    func completeDrop(targetZone: DropZoneID, targetIndex: Int) {
        guard let item = draggedItem, let source = sourceZone else {
            print("🔴 [DragSession] completeDrop: no draggedItem or sourceZone")
            return
        }

        print("🟢 [DragSession] completeDrop: source=\(source) target=\(targetZone) index=\(targetIndex)")

        if source != targetZone {
            pendingDrop = PendingDrop(
                item: item,
                sourceZone: source,
                sourceIndex: sourceIndex ?? 0,
                targetZone: targetZone,
                targetIndex: targetIndex
            )
            print("🟢 [DragSession] pendingDrop SET: \(pendingDrop!)")
        } else {
            print("🟡 [DragSession] completeDrop: same zone, ignoring (should be reorder)")
        }
        hapticFeedback(.generic)
        clearDrag()
    }

    func completeReorder() {
        print("🟡 [DragSession] completeReorder: zone=\(String(describing: sourceZone)) from=\(String(describing: sourceIndex)) to=\(String(describing: sourceZone.flatMap { insertionIndex[$0] }))")
        if let item = draggedItem,
           let zone = sourceZone,
           let from = sourceIndex,
           let to = insertionIndex[zone],
           from != to {
            pendingReorder = PendingReorder(item: item, zone: zone, fromIndex: from, toIndex: to)
            print("🟢 [DragSession] pendingReorder SET: from=\(from) to=\(to)")
        } else {
            print("🟡 [DragSession] completeReorder: no change or missing data")
        }
        hapticFeedback(.generic)
        clearDrag()
    }

    func cancelDrag() {
        clearDrag()
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    private func clearDrag() {
        draggedItem = nil
        draggedTab = nil
        sourceZone = nil
        sourceIndex = nil
        activeZone = nil
        isOutsideWindow = false
        insertionIndex = [:]
    }

    // MARK: - Haptics

    func hapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Live Reorder Offsets

    /// Returns the Y-offset (vertical zones) or X-offset (horizontal zones) for a tab at `index` during same-zone reorder.
    func reorderOffset(for zone: DropZoneID, at index: Int) -> CGFloat {
        // Only shift when same-zone reorder is happening
        guard isDragging, sourceZone == zone, activeZone == zone else { return 0 }
        guard let from = sourceIndex, let to = insertionIndex[zone] else { return 0 }
        guard from != to else { return 0 }

        let cellSize = itemCellSize[zone] ?? 36
        let spacing = itemCellSpacing[zone] ?? 2
        let step = cellSize + spacing

        // The dragged item is at `from`, it should visually move to `to`.
        // All items between from and to need to shift by one step in the opposite direction.
        if from < to {
            // Dragging down: items from+1 to `to` shift up
            if index > from && index <= to {
                return -step
            }
        } else {
            // Dragging up: items `to` to from-1 shift down
            if index >= to && index < from {
                return step
            }
        }
        return 0
    }

    // MARK: - Bridge to TabManager

    /// Convert a PendingDrop into a DragOperation for TabManager
    func makeDragOperation(from drop: PendingDrop, tab: Tab) -> DragOperation {
        DragOperation(
            tab: tab,
            fromContainer: drop.sourceZone.asDragContainer,
            fromIndex: drop.sourceIndex,
            toContainer: drop.targetZone.asDragContainer,
            toIndex: drop.targetIndex,
            toSpaceId: drop.targetZone.spaceId
        )
    }

    /// Convert a PendingReorder into a DragOperation for TabManager
    func makeDragOperation(from reorder: PendingReorder, tab: Tab) -> DragOperation {
        DragOperation(
            tab: tab,
            fromContainer: reorder.zone.asDragContainer,
            fromIndex: reorder.fromIndex,
            toContainer: reorder.zone.asDragContainer,
            toIndex: reorder.toIndex,
            toSpaceId: reorder.zone.spaceId
        )
    }
}
