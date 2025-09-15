//
//  SidebarDropSupport.swift
//  Nook
//
//  Shared drop-delegate logic and boundary math adapted from SimpleDragPreview.swift
//  to drive the actual Sidebar (essentials grid, space-pinned list, regular list).
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Grid Boundary Model (Essentials)

enum SidebarGridBoundaryOrientation { case horizontal, vertical }

struct SidebarGridBoundary {
    let index: Int
    let orientation: SidebarGridBoundaryOrientation
    let frame: CGRect // in grid local coordinates
}

// MARK: - Boundary Math (EXACT methodology as in SimpleDragPreview)

struct SidebarDropMath {
    static func computeGridBoundaries(
        frames: [Int: CGRect],
        columns: Int,
        containerWidth: CGFloat,
        gridGap: CGFloat
    ) -> [SidebarGridBoundary] {
        let count = frames.count
        guard count > 0 else { return [] }
        let sorted = (0..<count).compactMap { frames[$0] }
        guard sorted.count == count else { return [] }
        var boundaries: [SidebarGridBoundary] = []

        func rowRange(forRow row: Int) -> Range<Int> {
            let start = row * columns
            let end = min(start + columns, count)
            return start..<end
        }

        func rowOf(index: Int) -> Int { max(0, index / columns) }

        // Precompute per-row vertical span
        let totalRows = Int(ceil(Double(count) / Double(columns)))
        var rowMinY: [CGFloat] = []
        var rowMaxY: [CGFloat] = []
        for r in 0..<totalRows {
            let rr = rowRange(forRow: r)
            let minY = rr.compactMap { frames[$0]?.minY }.min() ?? 0
            let maxY = rr.compactMap { frames[$0]?.maxY }.max() ?? 0
            rowMinY.append(minY)
            rowMaxY.append(maxY)
        }

        for i in 0...count {
            if i == 0 {
                // Before first tile → vertical line at left edge of first column
                if let first = frames[0] {
                    let r = rowOf(index: 0)
                    let x = first.minX - (gridGap / 2)
                    let yMid = (rowMinY[r] + rowMaxY[r]) / 2
                    let h = rowMaxY[r] - rowMinY[r]
                    let f = CGRect(x: x - 1.5, y: yMid - h/2, width: 3, height: h)
                    boundaries.append(SidebarGridBoundary(index: 0, orientation: .vertical, frame: f))
                }
            } else if i == count {
                // After last tile: vertical if row incomplete, else horizontal below last row
                let last = count - 1
                let lastRow = rowOf(index: last)
                let rowStart = rowRange(forRow: lastRow).lowerBound
                let inRowIndex = last - rowStart + 1
                if inRowIndex < columns, let prev = frames[last] {
                    // Vertical at right of last cell in last row
                    let x = prev.maxX + (gridGap / 2)
                    let yMid = (rowMinY[lastRow] + rowMaxY[lastRow]) / 2
                    let h = rowMaxY[lastRow] - rowMinY[lastRow]
                    let f = CGRect(x: x - 1.5, y: yMid - h/2, width: 3, height: h)
                    boundaries.append(SidebarGridBoundary(index: i, orientation: .vertical, frame: f))
                } else {
                    // Horizontal below last row across container width
                    let y = rowMaxY[lastRow] + (gridGap / 2)
                    let f = CGRect(x: 0, y: y - 1.5, width: containerWidth, height: 3)
                    boundaries.append(SidebarGridBoundary(index: i, orientation: .horizontal, frame: f))
                }
            } else if i % columns == 0 {
                // Between rows (horizontal)
                let r = rowOf(index: i)
                let prevRow = max(0, r - 1)
                let y = (rowMaxY[prevRow] + rowMinY[r]) / 2
                let f = CGRect(x: 0, y: y - 1.5, width: containerWidth, height: 3)
                boundaries.append(SidebarGridBoundary(index: i, orientation: .horizontal, frame: f))
            } else {
                // Between columns (vertical) in same row
                if let left = frames[i - 1], let right = frames[i] {
                    let x = (left.maxX + right.minX) / 2
                    // Vertical span is the row height
                    let r = rowOf(index: i)
                    let yMid = (rowMinY[r] + rowMaxY[r]) / 2
                    let h = rowMaxY[r] - rowMinY[r]
                    let f = CGRect(x: x - 1.5, y: yMid - h/2, width: 3, height: h)
                    boundaries.append(SidebarGridBoundary(index: i, orientation: .vertical, frame: f))
                }
            }
        }
        return boundaries
    }

    static func estimatedGridWidth(from frames: [Int: CGRect]) -> CGFloat {
        let minX = frames.values.map { $0.minX }.min() ?? 0
        let maxX = frames.values.map { $0.maxX }.max() ?? 0
        return max(0, maxX - minX)
    }

    static func computeListBoundaries(frames: [Int: CGRect]) -> [CGFloat] {
        let count = frames.count
        guard count > 0 else { return [] }
        let ordered = (0..<count).compactMap { frames[$0] }
        guard ordered.count == count else { return [] }

        var boundaries: [CGFloat] = []
        
        // Before first item
        boundaries.append(ordered[0].minY)
        
        // Between each pair of items - simple midpoints
        for i in 0..<(count - 1) {
            let midpoint = (ordered[i].maxY + ordered[i + 1].minY) / 2
            boundaries.append(midpoint)
        }
        
        // After last item
        boundaries.append(ordered[count - 1].maxY)
        
        return boundaries
    }
}

// MARK: - Drop Delegates (generalized)

struct SidebarSectionDropDelegate: DropDelegate {
    let dragManager: TabDragManager
    let container: TabDragManager.DragContainer
    let boundariesProvider: () -> [CGFloat]
    let insertionLineFrameProvider: (() -> CGRect)?
    // Optional global container frame provider for converting local frames to global
    let globalFrameProvider: (() -> CGRect)?
    let onPerform: (DragOperation) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        print("🎯 [SidebarSectionDropDelegate] Drop entered: container=\(container), location=\(info.location)")
        updateTarget(with: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(with: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        _ = updateTarget(with: info)
        if let op = dragManager.endDrag(commit: true) {
            onPerform(op)
        }
        return true
    }

    @discardableResult
    private func updateTarget(with info: DropInfo) -> Int {
        let y = info.location.y
        let index = insertionIndex(forY: y)
        let boundaries = boundariesProvider()
        
        // Enhanced state validation - ensure insertionIndex is always valid for current container
        guard index >= 0 else {
            return 0
        }
        
        // Handle insertion line coordination between global and local overlays
        if boundaries.isEmpty {
            // Empty zone: use global insertion line via frame provider
            if let frameProvider = insertionLineFrameProvider {
                let frame = frameProvider()
                print("📐 [SidebarSectionDropDelegate] Empty zone frame (raw): \(frame)")
                // If a global container frame is provided, convert local to global by offsetting
                if let containerFrame = globalFrameProvider?() {
                    let converted = CGRect(
                        x: containerFrame.minX + frame.minX,
                        y: containerFrame.minY + frame.minY,
                        width: frame.width,
                        height: frame.height
                    )
                    print("📐 [SidebarSectionDropDelegate] Empty zone frame (global): \(converted)")
                    dragManager.updateInsertionLine(frame: converted)
                } else {
                    dragManager.updateInsertionLine(frame: frame)
                }
            } else {
                print("⚠️ [SidebarSectionDropDelegate] No frame provider for empty zone")
                dragManager.updateInsertionLine(frame: .zero)
            }
        } else {
            // Non-empty zone: calculate insertion line frame based on boundaries
            print("📐 [SidebarSectionDropDelegate] Non-empty boundaries: \(boundaries.count) items")
            
            // Calculate the frame for the insertion line at the target index
            let targetY = (index < boundaries.count) ? boundaries[index] : (boundaries.last ?? 0)
            let lineHeight: CGFloat = 3

            if let containerFrame = globalFrameProvider?() {
                // Convert local boundary Y into global coordinates using container frame
                let insertionFrame = CGRect(
                    x: containerFrame.minX + 10,
                    y: containerFrame.minY + targetY - lineHeight/2,
                    width: max(containerFrame.width - 20, 1),
                    height: lineHeight
                )
                print("📐 [SidebarSectionDropDelegate] Calculated insertion frame (global): \(insertionFrame)")
                dragManager.updateInsertionLine(frame: insertionFrame)
            } else {
                let containerWidth: CGFloat = 200 // Fallback sidebar width
                let insertionFrame = CGRect(
                    x: 10,
                    y: targetY - lineHeight/2,
                    width: containerWidth - 20,
                    height: lineHeight
                )
                print("📐 [SidebarSectionDropDelegate] Calculated insertion frame (local): \(insertionFrame)")
                dragManager.updateInsertionLine(frame: insertionFrame)
            }
        }
        
        // Add state consistency checks before updating drag target
        if validateDragManagerState(for: container, index: index) {
            dragManager.updateDragTarget(container: container, insertionIndex: index, spaceId: spaceId)
        }
        
        performMoveHapticIfNeeded(currentIndex: index)
        return index
    }

    private var spaceId: UUID? {
        switch container {
        case .spacePinned(let sid): return sid
        case .spaceRegular(let sid): return sid
        default: return nil
        }
    }

    private func insertionIndex(forY y: CGFloat) -> Int {
        let boundaries = boundariesProvider()
        
        // Enhanced empty zone handling - ensure we never return invalid indices
        guard !boundaries.isEmpty else { 
            return 0 
        }
        
        // Add bounds checking for Y coordinates
        guard y.isFinite && !y.isNaN else {
            return 0
        }
        
        // Simple Y-coordinate comparison against midpoints
        for (i, boundary) in boundaries.enumerated() {
            if y <= boundary {
                return max(0, i) // Ensure index is never negative
            }
        }
        
        // Enhanced fallback - ensure we never return invalid indices
        let maxIndex = boundaries.count - 1
        return max(0, maxIndex)
    }

    private func performMoveHapticIfNeeded(currentIndex: Int) {
        // Let TabDragManager handle haptics to avoid duplicate calls
    }
    
    // MARK: - State validation helpers
    
    private func validateDragManagerState(for container: TabDragManager.DragContainer, index: Int) -> Bool {
        // Ensure the drag manager's current state is consistent with the delegate's container
        guard dragManager.isDragging else { return false }
        
        // Add checks that prevent invalid state transitions
        if index < 0 { return false }
        
        // Validate that insertion indices are appropriate for the current container content
        switch container {
        case .none:
            return false
        case .essentials, .spacePinned, .spaceRegular:
            // Basic validation - more sophisticated checks could be added
            return true
        }
    }
}

struct SidebarGridDropDelegate: DropDelegate {
    let dragManager: TabDragManager
    let container: TabDragManager.DragContainer = .essentials
    let boundariesProvider: () -> [SidebarGridBoundary]
    let onPerform: (DragOperation) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { updateTarget(with: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(with: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        _ = updateTarget(with: info)
        if let op = dragManager.endDrag(commit: true) {
            onPerform(op)
        }
        return true
    }

    @discardableResult
    private func updateTarget(with info: DropInfo) -> Int {
        let index = insertionIndex(for: info.location)
        
        // Add state consistency checks for grid delegate
        guard validateGridDragManagerState(for: index) else {
            return index
        }
        
        dragManager.updateDragTarget(container: container, insertionIndex: index, spaceId: nil)
        
        // Calculate and set insertion line frame for grid
        let bounds = boundariesProvider()
        if !bounds.isEmpty, let boundary = bounds.first(where: { $0.index == index }) {
            print("📐 [SidebarGridDropDelegate] Grid insertion frame: \(boundary.frame)")
            dragManager.updateInsertionLine(frame: boundary.frame)
        } else {
            print("📐 [SidebarGridDropDelegate] No boundary found for index \(index)")
            dragManager.updateInsertionLine(frame: .zero)
        }
        
        return index
    }

    private func insertionIndex(for point: CGPoint) -> Int {
        let bounds = boundariesProvider()
        guard !bounds.isEmpty else { return 0 }
        
        // Add validation for point coordinates
        guard point.x.isFinite && point.y.isFinite && !point.x.isNaN && !point.y.isNaN else {
            return 0
        }
        
        var best = bounds[0]
        var bestDist = distance(point, to: bounds[0])
        for b in bounds.dropFirst() {
            let d = distance(point, to: b)
            if d < bestDist {
                bestDist = d
                best = b
            }
        }
        
        // Ensure returned index is valid
        return max(0, best.index)
    }

    private func distance(_ p: CGPoint, to b: SidebarGridBoundary) -> CGFloat {
        switch b.orientation {
        case .horizontal:
            let y = b.frame.midY
            let dx: CGFloat
            if p.x < b.frame.minX { dx = b.frame.minX - p.x }
            else if p.x > b.frame.maxX { dx = p.x - b.frame.maxX }
            else { dx = 0 }
            let dy = abs(p.y - y)
            return hypot(dx, dy)
        case .vertical:
            let x = b.frame.midX
            let dy: CGFloat
            if p.y < b.frame.minY { dy = b.frame.minY - p.y }
            else if p.y > b.frame.maxY { dy = p.y - b.frame.maxY }
            else { dy = 0 }
            let dx = abs(p.x - x)
            return hypot(dx, dy)
        }
    }
    
    // MARK: - State validation helpers
    
    private func validateGridDragManagerState(for index: Int) -> Bool {
        // Ensure the drag manager's current state is consistent with the grid delegate
        guard dragManager.isDragging else { return false }
        
        // Validate that insertion indices are appropriate for grid container
        guard index >= 0 else { return false }
        
        return true
    }
}

// MARK: - Overlay Helpers

struct SidebarSectionInsertionOverlay: View {
    let isActive: Bool
    let index: Int
    let boundaries: [CGFloat]

    var body: some View {
        let _ = print("🟦 [SidebarSectionInsertionOverlay] isActive=\(isActive), index=\(index), boundaries.count=\(boundaries.count)")
        return GeometryReader { proxy in
            ZStack {
                if isActive {
                    let _ = print("🟦 [SidebarSectionInsertionOverlay] Showing blue line at index \(index)")
                    let y: CGFloat = {
                        if !boundaries.isEmpty, index >= 0, index < boundaries.count {
                            return min(max(boundaries[index], 1.5), proxy.size.height - 1.5)
                        } else {
                            // Enhanced empty zone fallback - position at top third rather than center
                            return max(proxy.size.height / 3, 1.5)
                        }
                    }()
                    
                    let _ = print("🟦 [SidebarSectionInsertionOverlay] Blue line y-position: \(y)")
                    
                    // Enhanced styling for better visibility
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.9),
                                    Color.blue,
                                    Color.blue.opacity(0.9)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width, height: 4)
                        .position(x: proxy.size.width / 2, y: y)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .animation(.easeInOut(duration: 0.15), value: index)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(999) // High z-index to appear above content
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SidebarGridInsertionOverlay: View {
    let isActive: Bool
    let index: Int
    let boundaries: [SidebarGridBoundary]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isActive {
                    if let b = boundaries.first(where: { $0.index == index }) {
                        switch b.orientation {
                        case .horizontal:
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: b.frame.width, height: 10)
                                .position(x: b.frame.midX, y: b.frame.midY)
                                .shadow(color: .black, radius: 2)
                                .animation(.easeInOut(duration: 0.12), value: index)
                        case .vertical:
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 10, height: b.frame.height)
                                .position(x: b.frame.midX, y: b.frame.midY)
                                .shadow(color: .black, radius: 2)
                                .animation(.easeInOut(duration: 0.12), value: index)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Haptics helper (kept for parity)
@inline(__always)
private func performMoveHaptic() {
#if canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
#endif
}
