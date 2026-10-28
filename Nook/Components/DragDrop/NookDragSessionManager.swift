// Licensed under GPL-3.0. See LICENSE.
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
import NookUI

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
    /// Uniform sidebar rows: `Tab.stride` tall, including card margins.
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
    @Published var draggedTheme: SpaceTheme?
    @Published var draggedAccent: Color = .gray
    @Published var draggedColorScheme: ColorScheme = .light
    var sourceRowFrame: CGRect = .zero
    var grabOffset: CGPoint = .zero
    private weak var sourceWindow: NSWindow?
    @Published private(set) var isFinishingDrag = false
    private var dragGeneration = UUID()
    private var lastHapticPosition: DropPosition?
    private var lastHapticDepth = 0

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

    // Layout changes must not invalidate every tab’s drag observer during resizing.
    // Keep the geometry current; only an active tab drag needs a published update.
    var sidebarScreenFrame: CGRect = .zero {
        didSet {
            if isDragging && oldValue != sidebarScreenFrame { objectWillChange.send() }
        }
    }

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
    /// Views drawn over the tab list that own their clicks, such as the sidebar video.
    private let dragBarriers = NSHashTable<NSView>.weakObjects()

    func addDragBarrier(_ view: NSView) { dragBarriers.add(view) }

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

            if dragBarriers.allObjects.contains(where: { barrier in
                barrier.window === event.window && !barrier.isHiddenOrHasHiddenAncestor
                    && barrier.bounds.contains(barrier.convert(event.locationInWindow, from: nil))
            }) { return event }

            for (id, source) in registeredSources {
                guard let view = source.view, let window = view.window, event.window == window else { continue }
                let localPoint = view.convert(event.locationInWindow, from: nil)
                // A hidden row, such as one on another space's page, keeps its frame.
                if !view.isHiddenOrHasHiddenAncestor, view.bounds.contains(localPoint) {
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
            source.initiateDrag(with: event, mouseDownEvent: mouseDownEvent)
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

    func beginDrag(item: NookDragItem, icon: Image?, from zone: DropZoneID, cursorScreenPoint: NSPoint, grabScreenPoint: NSPoint, sourceFrame: CGRect, window: NSWindow?, theme: SpaceTheme?, accent: Color, colorScheme: ColorScheme) {
        ensurePreviewWindow()

        // Set cursor position BEFORE draggedItem so the preview window
        // positions correctly before orderFront is called by the Combine subscriber
        sourceWindow = window
        _updateCursorScreenPosition(cursorScreenPoint)
        sourceRowFrame = sourceFrame
        grabOffset = CGPoint(x: grabScreenPoint.x - sourceFrame.minX, y: grabScreenPoint.y - sourceFrame.midY)
        draggedTheme = theme
        draggedAccent = accent
        draggedColorScheme = colorScheme
        isFinishingDrag = false
        dragGeneration = UUID()
        draggedItem = item
        draggedIcon = icon
        sourceZone = zone
        activeZone = zone
        isOutsideWindow = false
        dropPosition = nil
        dropDepth = 0
        lastHapticPosition = nil
        lastHapticDepth = 0
    }

    nonisolated func updateCursorScreenPosition(_ screenPoint: NSPoint) {
        MainActor.assumeIsolated {
            self._updateCursorScreenPosition(screenPoint)
        }
    }

    private func _updateCursorScreenPosition(_ screenPoint: NSPoint) {
        guard !isFinishingDrag else { return }
        cursorScreenLocation = screenPoint

        guard let window = sourceWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NookDragPreviewWindow) }),
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
        // Compute state first; the preview must use the current outside/inside state.
        cursorScreenLocationSubject.send(screenPoint)
    }

    func cursorEnteredZone(_ zone: DropZoneID) {
        guard isDragging else { return }
        if activeZone != zone {
            activeZone = zone
            isOutsideWindow = false
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
            let depth = Self.depth(of: position, layout: layout)
            // “After A” and “before B” are the same insertion slot. Only tick
            // when the destination changes, not when its row representation does.
            let changedDestination = lastHapticPosition.map { previous in
                previous.zone != position.zone || lastHapticDepth != depth ||
                (previous.placement == .into) != (position.placement == .into) ||
                previous.index + (previous.placement == .after ? 1 : 0) !=
                    position.index + (position.placement == .after ? 1 : 0)
            } ?? false
            lastHapticPosition = position
            lastHapticDepth = depth
            dropPosition = position
            dropDepth = depth
            if changedDestination { hapticFeedback(.alignment) }
        }
    }

    /// Maps a point (top-left origin, zone-local) to a drop position.
    static func position(in zone: DropZoneID, layout: DropLayout, point: CGPoint, width: CGFloat) -> DropPosition {
        switch layout {
        case .none:
            return DropPosition(zone: zone, index: 0, placement: .before)
        case .grid(let count, let columns):
            let cols = max(1, columns)
            let rowHeight = NookDesign.Size.favoriteTile + NookDesign.Spacing.favoriteGap
            let colWidth = max(1, (width + NookDesign.Spacing.favoriteGap) / CGFloat(cols))
            let col = min(max(0, Int((point.x / colWidth).rounded())), cols)
            let row = max(0, Int(point.y / rowHeight))
            return DropPosition(zone: zone, index: min(max(0, row * cols + col), count), placement: .before)
        case .rows(let rows):
            let step = NookDesign.Tab.stride
            guard !rows.isEmpty, point.y < CGFloat(rows.count) * step else {
                return DropPosition(zone: zone, index: rows.count, placement: .before)
            }
            let index = max(0, Int(point.y / step))
            let fraction = (point.y - CGFloat(index) * step) / NookDesign.Tab.stride
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

    func finishDrag(at position: DropPosition, layout: DropLayout, zoneScreenFrame: CGRect, commit: @escaping () -> Void) {
        guard isDragging, !isFinishingDrag else { return }
        isFinishingDrag = true
        var target: CGRect?
        // Crossing sections can remove a header/separator and shift the destination.
        // Only animate against stable same-section coordinates; other drops commit directly.
        if sourceZone == position.zone, case .rows(let rows) = layout, position.placement != .into {
            let boundary = position.index + (position.placement == .after ? 1 : 0)
            let plan = TabReorderPreview(rows: rows, draggedID: draggedItem!.tabId,
                destinationBoundary: boundary, sourceInThisSection: sourceZone == position.zone,
                isDestination: true)
            if let gap = plan.gapIndex {
                target = CGRect(x: zoneScreenFrame.minX + CGFloat(dropDepth) * NookDesign.Spacing.folderIndent,
                    y: zoneScreenFrame.maxY - CGFloat(gap + 1) * NookDesign.Tab.stride + NookDesign.Tab.verticalInset,
                    width: max(1, zoneScreenFrame.width - CGFloat(dropDepth) * NookDesign.Spacing.folderIndent),
                    height: NookDesign.Tab.height)
            }
        }
        let generation = dragGeneration
        let complete = { [weak self] in
            guard let self, self.isFinishingDrag, self.dragGeneration == generation else { return }
            // The floating card has already landed. Commit atomically so the original
            // does not flash back at its source and animate to the destination a second time.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.clearDrag()
                commit()
            }
        }
        if let target, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let previewWindow {
            previewWindow.land(on: target, completion: complete)
        } else {
            complete()
        }
    }

    /// External consumers can accept a copy without passing through our drop anchors.
    /// Internal drops keep the preview alive only until their landing animation finishes.
    func nativeDragEnded() {
        guard isDragging, !isFinishingDrag else { return }
        cancelDrag()
    }

    func cancelDrag() {
        clearDrag()
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    func clearDrag() {
        isFinishingDrag = false
        sourceWindow = nil
        sourceRowFrame = .zero
        grabOffset = .zero
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
