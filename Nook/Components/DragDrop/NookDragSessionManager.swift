//
//  NookDragSessionManager.swift
//  Nook
//
//

import SwiftUI
import NookDesign
@preconcurrency import AppKit
import Combine
import NookTabsCore
import NookWeb

// MARK: - Drop Position

/// Where a drop would land inside a zone.
struct DropPosition: Equatable {
    enum Placement: Equatable { case before, after, into }
    let zone: DropZoneID
    /// Row or tile index. For rows, `before`/`after`/`into` refer to the row at `index`;
    /// `index == rows.count` with `.before` means below every row.
    let index: Int
    let placement: Placement
}

/// How a zone lays out its items, so a pointer position maps to a `DropPosition`.
enum DropLayout {
    /// A target without rows.
    case none
    /// Uniform sidebar rows: `Size.row` tall, `Spacing.rowGap` apart.
    case rows([Row])
    /// The favorites grid.
    case grid(count: Int, columns: Int)
}

extension Notification.Name {
    static let tabDragDidEnd = Notification.Name("tabDragDidEnd")
}

// MARK: - Drag Session Manager

@MainActor
final class NookDragSessionManager: ObservableObject {
    static let shared = NookDragSessionManager()

    @Published var draggedItem: NookDragItem?
    /// Favicon shown by the drag preview.
    @Published var draggedIcon: Image?
    @Published var sourceZone: DropZoneID?

    @Published var activeZone: DropZoneID?
    var isOutsideWindow: Bool = false
    var cursorLocation: CGPoint = .zero // window-flipped coords (top-left origin)
    var cursorScreenLocation: NSPoint = .zero // raw screen coords for preview window

    /// Non-@Published subject for high-frequency cursor updates.
    /// Only consumed by NookDragPreviewWindow — avoids triggering objectWillChange on every mouse move.
    let cursorScreenLocationSubject = PassthroughSubject<NSPoint, Never>()

    @Published var dropPosition: DropPosition?
    /// Folder levels the current drop lands inside: 0 at a section root, 1 inside a folder.
    @Published var dropDepth = 0

    @Published var sidebarScreenFrame: CGRect = .zero

    var isDragging: Bool { draggedItem != nil }

    var isCursorInSidebar: Bool {
        guard sidebarScreenFrame.width > 0 else { return false }
        return cursorScreenLocation.x >= sidebarScreenFrame.minX &&
               cursorScreenLocation.x <= sidebarScreenFrame.maxX
    }

    private var previewWindow: NookDragPreviewWindow?

    private func ensurePreviewWindow() {
        guard previewWindow == nil else { return }
        previewWindow = NookDragPreviewWindow(manager: self)
    }

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

    nonisolated private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
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

    func beginDrag(item: NookDragItem, icon: Image?, from zone: DropZoneID, cursorScreenPoint: NSPoint) {
        ensurePreviewWindow()

        // Set cursor position BEFORE draggedItem so the preview window
        // positions correctly before orderFront is called by the Combine subscriber
        _updateCursorScreenPosition(cursorScreenPoint)

        draggedItem = item
        draggedIcon = icon
        sourceZone = zone
        activeZone = zone
        isOutsideWindow = false
        dropPosition = nil
        dropDepth = 0
    }

    nonisolated func updateCursorScreenPosition(_ screenPoint: NSPoint) {
        MainActor.assumeIsolated {
            self._updateCursorScreenPosition(screenPoint)
        }
    }

    private func _updateCursorScreenPosition(_ screenPoint: NSPoint) {
        cursorScreenLocation = screenPoint
        cursorScreenLocationSubject.send(screenPoint)

        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NookDragPreviewWindow) }),
              let contentView = window.contentView else { return }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
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

    func cursorEnteredZone(_ zone: DropZoneID) {
        guard isDragging else { return }
        if activeZone != zone {
            activeZone = zone
            isOutsideWindow = false
            hapticFeedback(.alignment)
        }
    }

    func cursorExitedZone(_ zone: DropZoneID) {
        guard isDragging, activeZone == zone else { return }
        activeZone = nil
        if dropPosition?.zone == zone {
            dropPosition = nil
            dropDepth = 0
        }
    }

    func updateDropPosition(for zone: DropZoneID, layout: DropLayout, localPoint: CGPoint, zoneWidth: CGFloat) {
        guard isDragging else { return }
        let position = Self.position(in: zone, layout: layout, point: localPoint, width: zoneWidth)
        if position != dropPosition {
            dropPosition = position
            dropDepth = Self.depth(of: position, layout: layout)
            hapticFeedback(.alignment)
        }
    }

    /// Maps a point (top-left origin, zone-local) to a drop position.
    static func position(in zone: DropZoneID, layout: DropLayout, point: CGPoint, width: CGFloat) -> DropPosition {
        switch layout {
        case .none:
            return DropPosition(zone: zone, index: 0, placement: .before)
        case .grid(let count, let columns):
            let cols = max(1, columns)
            let rowHeight = NookDesign.Size.essentialsTile + NookDesign.Spacing.sm
            let colWidth = max(1, width / CGFloat(cols))
            let col = min(max(0, Int((point.x / colWidth).rounded())), cols)
            let row = max(0, Int(point.y / rowHeight))
            return DropPosition(zone: zone, index: min(max(0, row * cols + col), count), placement: .before)
        case .rows(let rows):
            let step = NookDesign.Size.row + NookDesign.Spacing.rowGap
            guard !rows.isEmpty, point.y < CGFloat(rows.count) * step else {
                return DropPosition(zone: zone, index: rows.count, placement: .before)
            }
            let index = max(0, Int(point.y / step))
            let fraction = (point.y - CGFloat(index) * step) / NookDesign.Size.row
            let placement: DropPosition.Placement
            if rows[index].item.isFolder {
                placement = fraction < 1.0 / 3 ? .before : (fraction > 2.0 / 3 ? .after : .into)
            } else {
                placement = fraction < 0.5 ? .before : .after
            }
            return DropPosition(zone: zone, index: index, placement: placement)
        }
    }

    /// The level a drop lands at, matching `TabsController.drop(_:at:section:rows:)`: into a
    /// folder is one below it; before a row is that row's level; after an open folder's header is
    /// its first child's level; the end of a section is its root.
    static func depth(of position: DropPosition, layout: DropLayout) -> Int {
        guard case .rows(let rows) = layout, position.index < rows.count else { return 0 }
        let row = rows[position.index]
        switch position.placement {
        case .into: return row.depth + 1
        case .before: return row.depth
        case .after:
            let next = position.index + 1
            return next < rows.count && rows[next].depth > row.depth ? rows[next].depth : row.depth
        }
    }

    // MARK: - Drop

    func cancelDrag() {
        clearDrag()
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    func clearDrag() {
        draggedItem = nil
        draggedIcon = nil
        sourceZone = nil
        activeZone = nil
        isOutsideWindow = false
        dropPosition = nil
        dropDepth = 0
    }

    // MARK: - Haptics

    func hapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

}
