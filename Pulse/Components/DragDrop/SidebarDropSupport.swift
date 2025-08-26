//
//  SidebarDropSupport.swift
//  Pulse
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
        guard count > 0 else { return [20] } // Single boundary for empty areas
        let ordered = (0..<count).compactMap { frames[$0] }
        guard ordered.count == count else { return [20] }

        var boundaries: [CGFloat] = []
        
        // Before first item - extend upward to connect with above sections
        boundaries.append(max(0, ordered[0].minY - 30))
        
        // Between each pair of items  
        for i in 0..<(count - 1) {
            let midpoint = (ordered[i].maxY + ordered[i + 1].minY) / 2
            boundaries.append(midpoint)
        }
        
        // After last item
        boundaries.append(ordered[count - 1].maxY + 4)
        
        return boundaries
    }
}

// MARK: - Drop Delegates (generalized)

struct SidebarSectionDropDelegate: DropDelegate {
    let dragManager: TabDragManager
    let container: TabDragManager.DragContainer
    let boundariesProvider: () -> [CGFloat]
    let onPerform: (DragOperation) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
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
        dragManager.updateDragTarget(container: container, insertionIndex: index, spaceId: spaceId)
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
        guard !boundaries.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, b) in boundaries.enumerated() {
            let d = abs(b - y)
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        return max(0, min(bestIndex, boundaries.count - 1))
    }

    private func performMoveHapticIfNeeded(currentIndex: Int) {
        // Let TabDragManager handle haptics to avoid duplicate calls
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
        dragManager.updateDragTarget(container: container, insertionIndex: index, spaceId: nil)
        return index
    }

    private func insertionIndex(for point: CGPoint) -> Int {
        let bounds = boundariesProvider()
        guard !bounds.isEmpty else { return 0 }
        var best = bounds[0]
        var bestDist = distance(point, to: bounds[0])
        for b in bounds.dropFirst() {
            let d = distance(point, to: b)
            if d < bestDist {
                bestDist = d
                best = b
            }
        }
        return best.index
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
}

// MARK: - Overlay Helpers

struct SidebarSectionInsertionOverlay: View {
    let isActive: Bool
    let index: Int
    let boundaries: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isActive {
                    let y: CGFloat = {
                        if !boundaries.isEmpty, index >= 0, index < boundaries.count {
                            return min(max(boundaries[index], 1.5), proxy.size.height - 1.5)
                        } else {
                            return proxy.size.height / 2
                        }
                    }()
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(height: 10)
                        .position(x: proxy.size.width / 2, y: y)
                        .shadow(color: .black, radius: 2)
                        .animation(.easeInOut(duration: 0.12), value: index)
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

// MARK: - Universal Drop Delegate (finds closest gap everywhere)

struct UniversalDropDelegate: DropDelegate {
    let dragManager: TabDragManager
    let essentialsFramesProvider: () -> [Int: CGRect] 
    let essentialsColumns: () -> Int
    let essentialsWidth: () -> CGFloat
    let spacePinnedFramesProvider: (() -> [Int: CGRect])?
    let regularFramesProvider: (() -> [Int: CGRect])?
    let spaceId: UUID?
    let onPerform: (DragOperation) -> Void
    
    func validateDrop(info: DropInfo) -> Bool { true }
    
    func dropEntered(info: DropInfo) { updateClosestTarget(with: info) }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateClosestTarget(with: info)
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        _ = updateClosestTarget(with: info)
        if let op = dragManager.endDrag(commit: true) {
            onPerform(op)
        }
        return true
    }
    
    private func updateClosestTarget(with info: DropInfo) {
        let point = info.location
        
        var closestDistance = CGFloat.greatestFiniteMagnitude
        var closestContainer = TabDragManager.DragContainer.essentials
        var closestIndex = 0
        var targetSpaceId: UUID? = nil
        
        // Check essentials grid boundaries
        let essentialsFrames = essentialsFramesProvider()
        let essentialsBoundaries = SidebarDropMath.computeGridBoundaries(
            frames: essentialsFrames,
            columns: essentialsColumns(),
            containerWidth: max(essentialsWidth(), 150),
            gridGap: 8
        )
        
        for boundary in essentialsBoundaries {
            let distance = distanceToGridBoundary(point, boundary)
            if distance < closestDistance {
                closestDistance = distance
                closestContainer = .essentials
                closestIndex = boundary.index
                targetSpaceId = nil
            }
        }
        
        // Check space pinned if available
        if let spacePinnedFrames = spacePinnedFramesProvider?(), let sid = spaceId {
            let pinnedBoundaries = SidebarDropMath.computeListBoundaries(frames: spacePinnedFrames)
            for (idx, boundary) in pinnedBoundaries.enumerated() {
                let distance = abs(point.y - boundary)
                if distance < closestDistance {
                    closestDistance = distance
                    closestContainer = .spacePinned(sid)
                    closestIndex = idx
                    targetSpaceId = sid
                }
            }
        }
        
        // Check space regular if available
        if let regularFrames = regularFramesProvider?(), let sid = spaceId {
            let regularBoundaries = SidebarDropMath.computeListBoundaries(frames: regularFrames)
            for (idx, boundary) in regularBoundaries.enumerated() {
                let distance = abs(point.y - boundary)
                if distance < closestDistance {
                    closestDistance = distance
                    closestContainer = .spaceRegular(sid)
                    closestIndex = idx
                    targetSpaceId = sid
                }
            }
        }
        
        // Always update with the closest target found  
        print("🎯 Updating drag target: \(closestContainer) index: \(closestIndex)")
        dragManager.updateDragTarget(
            container: closestContainer,
            insertionIndex: max(0, closestIndex),
            spaceId: targetSpaceId
        )
    }
    
    private func distanceToGridBoundary(_ point: CGPoint, _ boundary: SidebarGridBoundary) -> CGFloat {
        let frame = boundary.frame
        let dx: CGFloat
        let dy: CGFloat
        
        // Calculate distance to boundary frame
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }
        
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }
        
        return hypot(dx, dy)
    }
}

// MARK: - Original Space Drop Delegate (kept for compatibility)

struct SpaceUnifiedDropDelegate: DropDelegate {
    let dragManager: TabDragManager
    let spaceId: UUID
    let pinnedFramesProvider: () -> [Int: CGRect]
    let regularFramesProvider: () -> [Int: CGRect]
    let pinnedTopYProvider: () -> CGFloat
    let regularTopYProvider: () -> CGFloat
    let onPerform: (DragOperation) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
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
        let pTop = pinnedTopYProvider()
        let rTop = regularTopYProvider()
        let pinnedFrames = pinnedFramesProvider()
        let regularFrames = regularFramesProvider()

        // Build unified-space boundaries for both sections
        let pinnedBoundariesUnified: [CGFloat] = SidebarDropMath
            .computeListBoundaries(frames: pinnedFrames)
            .map { $0 + pTop }
        let regularBoundariesUnified: [CGFloat] = SidebarDropMath
            .computeListBoundaries(frames: regularFrames)
            .map { $0 + rTop }

        // If both empty, pick section by absolute position relative to their tops
        if pinnedBoundariesUnified.isEmpty && regularBoundariesUnified.isEmpty {
            let choosePinned = y < rTop
            let idx = 0
            dragManager.updateDragTarget(
                container: choosePinned ? .spacePinned(spaceId) : .spaceRegular(spaceId),
                insertionIndex: idx,
                spaceId: spaceId
            )
            return idx
        }

        // Iterate all boundaries and pick the closest one across both sections
        var bestContainer: TabDragManager.DragContainer = .spaceRegular(spaceId)
        var bestIndex: Int = 0
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for (i, b) in pinnedBoundariesUnified.enumerated() {
            let d = abs(b - y)
            if d < bestDistance {
                bestDistance = d
                bestContainer = .spacePinned(spaceId)
                bestIndex = i
            }
        }

        for (i, b) in regularBoundariesUnified.enumerated() {
            let d = abs(b - y)
            if d < bestDistance {
                bestDistance = d
                bestContainer = .spaceRegular(spaceId)
                bestIndex = i
            }
        }

        // Update drag target with winning container/index
        dragManager.updateDragTarget(
            container: bestContainer,
            insertionIndex: max(0, bestIndex),
            spaceId: spaceId
        )
        return bestIndex
    }
}
