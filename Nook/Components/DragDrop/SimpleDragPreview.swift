//
//  SimpleDragPreview.swift
//  Nook
//
//  Simple working drag & drop preview
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
    import AppKit
#endif

struct SimpleDragPreview: View {
    @State private var essentialTabs = ["GitHub", "Gmail", "Calendar"]
    @State private var spacePinnedTabs = ["Stack Overflow", "Docs"]
    @State private var regularTabs = ["Claude", "OpenAI", "Anthropic", "YouTube", "Netflix"]

    @State private var draggedItem: String?
    @State private var dragSourceSection: DragSection?
    @State private var targetedSection: DragSection?
    @State private var targetedIndex: Int?
    @State private var isDragging: Bool = false
    // Measured row centers per section (for intelligent boundaries)
    // Essentials (pinned) layout metrics
    @State private var essentialCenters: [CGFloat] = []
    @State private var essentialCellFrames: [Int: CGRect] = [:] // local to grid
    @State private var spacePinnedCenters: [CGFloat] = []
    @State private var regularCenters: [CGFloat] = []
    @State private var spacePinnedRowFrames: [Int: CGRect] = [:] // local to section
    @State private var regularRowFrames: [Int: CGRect] = [:] // local to section
    // Container top positions in global space for local conversion
    @State private var essentialTopY: CGFloat = 0
    @State private var spacePinnedTopY: CGFloat = 0
    @State private var regularTopY: CGFloat = 0

    // Simulated width for preview; in the app this will be driven by `BrowserManager.sidebarWidth`.
    @State private var simulatedSidebarWidth: CGFloat = 250
    @Namespace private var reorderNS

    enum DragSection {
        case essential, spacePinned, regular
    }

    // Grid configuration (pinned essentials)
    private var tileSize: CGFloat { 44 }
    private var gridGap: CGFloat { 8 }
    private var gridHPadding: CGFloat { 8 }
    private var gridVPadding: CGFloat { 8 }

    private func essentialColumnCount(for width: CGFloat, item: CGFloat, gap: CGFloat) -> Int {
        // Clamp between 1–4 columns. Rough heuristic for preview testing.
        let usable = max(width - (gridHPadding * 2), item)
        let cols = Int(floor((usable + gap) / (item + gap)))
        return min(max(cols, 1), 4)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("🧛 Simple Drag Test")
                .font(.title2)
                .fontWeight(.bold)

            // Essential Tabs (Pinned) as a responsive grid
            VStack(alignment: .leading, spacing: 8) {
                Text("Essential Tabs")
                    .font(.headline)
                    .foregroundColor(.secondary)

                // Responsive grid sized by sidebar width and item size
                let cols = essentialColumnCount(for: simulatedSidebarWidth, item: tileSize, gap: gridGap)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileSize), spacing: gridGap, alignment: .center), count: cols), alignment: .leading, spacing: gridGap) {
                    ForEach(essentialTabs.indices, id: \.self) { tabIndex in
                        let tab = essentialTabs[tabIndex]
                        TabSquareView(name: tab, isDragged: draggedItem == tab)
                            .frame(width: tileSize, height: tileSize)
                            .matchedGeometryEffect(id: "ess_\(tab)", in: reorderNS)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .onDrag {
                                #if DEBUG
                                    print("🚀 Starting drag: \(tab) from Essential")
                                #endif
                                targetedSection = nil
                                targetedIndex = nil
                                draggedItem = tab
                                dragSourceSection = .essential
                                isDragging = true
                                return NSItemProvider(object: tab as NSString)
                            }
                            .background(GeometryReader { proxy in
                                // Measure cell center and frame in local grid space
                                let local = proxy.frame(in: .named("EssentialGridSpace"))
                                Color.clear.preference(key: EssentialRowCentersKey.self, value: [tabIndex: local.midY])
                                    .preference(key: EssentialCellFramesKey.self, value: [tabIndex: local])
                            })
                    }
                }
                .padding(.horizontal, gridHPadding)
                .padding(.vertical, gridVPadding)
                .coordinateSpace(name: "EssentialGridSpace")
                .onPreferenceChange(EssentialRowCentersKey.self) { dict in
                    // Back-compat for any logic still using row centers
                    essentialCenters = (0 ..< essentialTabs.count).compactMap { dict[$0] }
                }
                .onPreferenceChange(EssentialCellFramesKey.self) { frames in
                    essentialCellFrames = frames
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: EssentialContainerTopKey.self, value: proxy.frame(in: .global).minY)
                })
                .onPreferenceChange(EssentialContainerTopKey.self) { top in
                    essentialTopY = top
                }
                // Grid-specific drop handling
                .overlay(gridDropTargetOverlay(columns: cols))
                .onDrop(of: [.text], delegate: GridBoundedDropDelegate(
                    targetedSection: $targetedSection,
                    targetedIndex: $targetedIndex,
                    isDragging: $isDragging,
                    section: .essential,
                    boundariesProvider: { computeGridBoundaries(frames: essentialCellFrames, columns: cols, containerWidth: estimatedGridWidth(from: essentialCellFrames)) },
                    onPerform: { index in
                        handleDrop(providers: [], to: .essential, atIndex: index)
                    }
                ))
                // No explicit visible label zone; the section itself supports
                // dropping at end via its computed boundaries.
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            Divider()

            // Space Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Development Space")
                    .font(.headline)

                // Space Pinned
                if !spacePinnedTabs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pinned in Space")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(spacing: 2) {
                            ForEach(spacePinnedTabs.indices, id: \.self) { tabIndex in
                                let tab = spacePinnedTabs[tabIndex]

                                TabRowView(name: tab, isDragged: draggedItem == tab)
                                    .matchedGeometryEffect(id: "sp_\(tab)", in: reorderNS)
                                    .onDrag {
                                        #if DEBUG
                                            print("🚀 Starting drag: \(tab) from Space Pinned")
                                        #endif
                                        targetedSection = nil
                                        targetedIndex = nil
                                        draggedItem = tab
                                        dragSourceSection = .spacePinned
                                        isDragging = true
                                        return NSItemProvider(object: tab as NSString)
                                    }
                                    .background(GeometryReader { proxy in
                                        let local = proxy.frame(in: .named("SpacePinnedSection"))
                                        Color.clear
                                            .preference(key: SpacePinnedRowCentersKey.self, value: [tabIndex: proxy.frame(in: .global).midY])
                                            .preference(key: SpacePinnedRowFramesKey.self, value: [tabIndex: local])
                                    })

                                // connected drop handled by section drop delegate
                            }
                        }
                        .coordinateSpace(name: "SpacePinnedSection")
                        .onPreferenceChange(SpacePinnedRowCentersKey.self) { dict in
                            spacePinnedCenters = (0 ..< spacePinnedTabs.count).compactMap { dict[$0] }
                        }
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: SpacePinnedContainerTopKey.self, value: proxy.frame(in: .global).minY)
                        })
                        .onPreferenceChange(SpacePinnedContainerTopKey.self) { top in
                            spacePinnedTopY = top
                        }
                        .onPreferenceChange(SpacePinnedRowFramesKey.self) { frames in
                            spacePinnedRowFrames = frames
                        }
                        .overlay(dropTargetOverlay(
                            section: .spacePinned,
                            boundaries: computeListBoundaries(frames: spacePinnedRowFrames)
                        ))
                        .onDrop(of: [.text], delegate: SectionBoundedDropDelegate(
                            targetedSection: $targetedSection,
                            targetedIndex: $targetedIndex,
                            isDragging: $isDragging,
                            section: .spacePinned,
                            boundariesProvider: { computeListBoundaries(frames: spacePinnedRowFrames) },
                            onPerform: { index in
                                handleDrop(providers: [], to: .spacePinned, atIndex: index)
                            }
                        ))
                    }

                    Divider()
                        .padding(.vertical, 4)
                }

                // Regular Tabs
                VStack(alignment: .leading, spacing: 4) {
                    Text("Regular Tabs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 2) {
                        ForEach(regularTabs.indices, id: \.self) { tabIndex in
                            let tab = regularTabs[tabIndex]

                            TabRowView(name: tab, isDragged: draggedItem == tab)
                                .matchedGeometryEffect(id: "reg_\(tab)", in: reorderNS)
                                .onDrag {
                                    #if DEBUG
                                        print("🚀 Starting drag: \(tab) from Regular")
                                    #endif
                                    targetedSection = nil
                                    targetedIndex = nil
                                    draggedItem = tab
                                    dragSourceSection = .regular
                                    isDragging = true
                                    return NSItemProvider(object: tab as NSString)
                                }
                                .background(GeometryReader { proxy in
                                    let local = proxy.frame(in: .named("RegularSection"))
                                    Color.clear
                                        .preference(key: RegularRowCentersKey.self, value: [tabIndex: proxy.frame(in: .global).midY])
                                        .preference(key: RegularRowFramesKey.self, value: [tabIndex: local])
                                })

                            // connected drop handled by section drop delegate
                        }
                    }
                    .coordinateSpace(name: "RegularSection")
                    .onPreferenceChange(RegularRowCentersKey.self) { dict in
                        regularCenters = (0 ..< regularTabs.count).compactMap { dict[$0] }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RegularContainerTopKey.self, value: proxy.frame(in: .global).minY)
                    })
                    .onPreferenceChange(RegularContainerTopKey.self) { top in
                        regularTopY = top
                    }
                    .onPreferenceChange(RegularRowFramesKey.self) { frames in
                        regularRowFrames = frames
                    }
                    // No explicit visible label zone; the section itself supports
                    // dropping at the start via its computed boundaries.
                    .overlay(dropTargetOverlay(
                        section: .regular,
                        boundaries: computeListBoundaries(frames: regularRowFrames)
                    ))
                    .onDrop(of: [.text], delegate: SectionBoundedDropDelegate(
                        targetedSection: $targetedSection,
                        targetedIndex: $targetedIndex,
                        isDragging: $isDragging,
                        section: .regular,
                        boundariesProvider: { computeListBoundaries(frames: regularRowFrames) },
                        onPerform: { index in
                            handleDrop(providers: [], to: .regular, atIndex: index)
                        }
                    ))
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)

            Spacer()

            // Debug Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Debug Info:")
                    .fontWeight(.bold)
                Text("Dragging: \(draggedItem ?? "None")")
                Text("From: \(dragSourceSection?.description ?? "None")")
                Text("Targeted: \(targetedSection?.description ?? "None")")
                Text("Index: \(targetedIndex?.description ?? "None")")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        // Simulate the dynamic sidebar width in this preview-only view
        .frame(width: simulatedSidebarWidth, height: 700)
        .background(alignment: .top) {
            VStack(spacing: 6) {
                Text("Sidebar Width: \(Int(simulatedSidebarWidth))px")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $simulatedSidebarWidth, in: 180 ... 360)
                    .padding(.horizontal)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Connected drop overlay (midpoint boundaries)

    private func dropTargetOverlay(section: DragSection, boundaries: [CGFloat]) -> some View {
        GeometryReader { proxy in
            ZStack {
                if isDragging, targetedSection == section, let idx = targetedIndex, !boundaries.isEmpty {
                    let clamped = min(max(idx, 0), boundaries.count - 1)
                    let y = min(max(boundaries[clamped], 1.5), proxy.size.height - 1.5)
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: 3)
                        .position(x: proxy.size.width / 2, y: y)
                        .animation(.easeInOut(duration: 0.12), value: targetedIndex)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // Grid overlay: highlight nearest cell when targeting essentials
    private func gridDropTargetOverlay(columns: Int) -> some View {
        GeometryReader { proxy in
            ZStack {
                if isDragging, targetedSection == .essential, let idx = targetedIndex {
                    let bounds = computeGridBoundaries(frames: essentialCellFrames, columns: columns, containerWidth: proxy.size.width)
                    if let b = bounds.first(where: { $0.index == idx }) {
                        switch b.orientation {
                        case .horizontal:
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: b.frame.width, height: 3)
                                .position(x: b.frame.midX, y: b.frame.midY)
                                .animation(.easeInOut(duration: 0.12), value: targetedIndex)
                        case .vertical:
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 3, height: b.frame.height)
                                .position(x: b.frame.midX, y: b.frame.midY)
                                .animation(.easeInOut(duration: 0.12), value: targetedIndex)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // Compute grid boundaries (index 0...N) as oriented line segments within grid container
    private func computeGridBoundaries(frames: [Int: CGRect], columns: Int, containerWidth: CGFloat) -> [GridBoundary] {
        let count = frames.count
        guard count > 0 else { return [] }
        let sorted = (0 ..< count).compactMap { frames[$0] }
        guard sorted.count == count else { return [] }
        var boundaries: [GridBoundary] = []

        func rowRange(forRow row: Int) -> Range<Int> {
            let start = row * columns
            let end = min(start + columns, count)
            return start ..< end
        }

        func rowOf(index: Int) -> Int { max(0, index / columns) }

        // Precompute per-row vertical span
        let totalRows = Int(ceil(Double(count) / Double(columns)))
        var rowMinY: [CGFloat] = []
        var rowMaxY: [CGFloat] = []
        for r in 0 ..< totalRows {
            let rr = rowRange(forRow: r)
            let minY = rr.compactMap { frames[$0]?.minY }.min() ?? 0
            let maxY = rr.compactMap { frames[$0]?.maxY }.max() ?? 0
            rowMinY.append(minY)
            rowMaxY.append(maxY)
        }

        for i in 0 ... count {
            if i == 0 {
                // Before first tile → vertical line at left edge of first column
                if let first = frames[0] {
                    let r = rowOf(index: 0)
                    let x = first.minX - (gridGap / 2)
                    let yMid = (rowMinY[r] + rowMaxY[r]) / 2
                    let h = rowMaxY[r] - rowMinY[r]
                    let f = CGRect(x: x - 1.5, y: yMid - h / 2, width: 3, height: h)
                    boundaries.append(GridBoundary(index: 0, orientation: .vertical, frame: f))
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
                    let f = CGRect(x: x - 1.5, y: yMid - h / 2, width: 3, height: h)
                    boundaries.append(GridBoundary(index: i, orientation: .vertical, frame: f))
                } else {
                    // Horizontal below last row across container width
                    let y = rowMaxY[lastRow] + (gridGap / 2)
                    let f = CGRect(x: 0, y: y - 1.5, width: containerWidth, height: 3)
                    boundaries.append(GridBoundary(index: i, orientation: .horizontal, frame: f))
                }
            } else if i % columns == 0 {
                // Between rows (horizontal)
                let r = rowOf(index: i)
                // Safe guard for r-1
                let prevRow = max(0, r - 1)
                let y = (rowMaxY[prevRow] + rowMinY[r]) / 2
                let f = CGRect(x: 0, y: y - 1.5, width: containerWidth, height: 3)
                boundaries.append(GridBoundary(index: i, orientation: .horizontal, frame: f))
            } else {
                // Between columns (vertical) in same row
                if let left = frames[i - 1], let right = frames[i] {
                    let x = (left.maxX + right.minX) / 2
                    // Vertical span is the row height
                    let r = rowOf(index: i)
                    let yMid = (rowMinY[r] + rowMaxY[r]) / 2
                    let h = rowMaxY[r] - rowMinY[r]
                    let f = CGRect(x: x - 1.5, y: yMid - h / 2, width: 3, height: h)
                    boundaries.append(GridBoundary(index: i, orientation: .vertical, frame: f))
                }
            }
        }
        return boundaries
    }

    // Estimate grid width for delegate distance math when we don't have GeometryProxy
    private func estimatedGridWidth(from frames: [Int: CGRect]) -> CGFloat {
        let minX = frames.values.map { $0.minX }.min() ?? 0
        let maxX = frames.values.map { $0.maxX }.max() ?? 0
        return max(0, maxX - minX)
    }

    // Compute inter-tab boundary positions by bisecting adjacent tab centers.
    private func computeBoundaries(centers: [CGFloat], prevTrailing: CGFloat?, nextLeading: CGFloat?) -> [CGFloat] {
        guard !centers.isEmpty else { return [] }
        var boundaries: [CGFloat] = []
        // First boundary
        if let prev = prevTrailing {
            boundaries.append((prev + centers[0]) / 2)
        } else if centers.count >= 2 {
            boundaries.append(centers[0] - (centers[1] - centers[0]) / 2)
        } else {
            boundaries.append(centers[0] - 16) // fallback
        }
        // Middles
        if centers.count >= 2 {
            for i in 0 ..< (centers.count - 1) {
                boundaries.append((centers[i] + centers[i + 1]) / 2)
            }
        }
        // Last boundary
        if let next = nextLeading, let last = centers.last {
            boundaries.append((last + next) / 2)
        } else if centers.count >= 2, let last = centers.last {
            let prev = centers[centers.count - 2]
            boundaries.append(last + (last - prev) / 2)
        } else if let last = centers.last {
            boundaries.append(last + 16) // fallback
        }
        return boundaries
    }

    // Compute boundaries for vertical lists from measured row frames (in local space)
    private func computeListBoundaries(frames: [Int: CGRect]) -> [CGFloat] {
        let count = frames.count
        guard count > 0 else { return [] }
        let ordered = (0 ..< count).compactMap { frames[$0] }
        guard ordered.count == count else { return [] }

        var boundaries: [CGFloat] = []
        // First boundary: a bit above first row
        if count >= 2 {
            let first = ordered[0]
            let second = ordered[1]
            let approxGap = (second.midY - first.midY)
            boundaries.append(first.minY - max(4, approxGap * 0.5))
        } else {
            boundaries.append((ordered[0].minY + ordered[0].midY) / 2)
        }
        // Middles between each consecutive row
        if count >= 2 {
            for i in 0 ..< (count - 1) {
                let y = (ordered[i].maxY + ordered[i + 1].minY) / 2
                boundaries.append(y)
            }
        }
        // Last boundary: a bit below last row
        if count >= 2 {
            let last = ordered[count - 1]
            let prev = ordered[count - 2]
            let approxGap = (last.midY - prev.midY)
            boundaries.append(last.maxY + max(4, approxGap * 0.5))
        } else {
            boundaries.append((ordered[0].maxY + ordered[0].midY) / 2)
        }
        return boundaries
    }

    private func handleDrop(providers _: [NSItemProvider], to section: DragSection, atIndex: Int) -> Bool {
        #if DEBUG
            print("🎯 Drop attempted - Item: \(draggedItem ?? "nil"), From: \(dragSourceSection?.description ?? "nil"), To: \(section.description) at index \(atIndex)")
        #endif

        guard let draggedItem = draggedItem,
              let dragSourceSection = dragSourceSection
        else {
            #if DEBUG
                print("❌ Drop failed - missing drag state")
            #endif
            resetDragState()
            return false
        }

        #if DEBUG
            print("✅ Moving \(draggedItem) from \(dragSourceSection.description) to \(section.description) at index \(atIndex)")
        #endif

        // Perform move immediately with tighter spring for crisper reorder
        withAnimation(.spring(response: 0.20, dampingFraction: 0.90, blendDuration: 0.1)) {
            // Remove from source first
            switch dragSourceSection {
            case .essential:
                essentialTabs.removeAll { $0 == draggedItem }
            case .spacePinned:
                spacePinnedTabs.removeAll { $0 == draggedItem }
            case .regular:
                regularTabs.removeAll { $0 == draggedItem }
            }

            // Insert at destination with proper index
            switch section {
            case .essential:
                let clampedIndex = min(max(atIndex, 0), essentialTabs.count)
                essentialTabs.insert(draggedItem, at: clampedIndex)
            case .spacePinned:
                let clampedIndex = min(max(atIndex, 0), spacePinnedTabs.count)
                spacePinnedTabs.insert(draggedItem, at: clampedIndex)
            case .regular:
                let clampedIndex = min(max(atIndex, 0), regularTabs.count)
                regularTabs.insert(draggedItem, at: clampedIndex)
            }
        }

        resetDragState()
        return true
    }

    private func resetDragState() {
        #if DEBUG
            print("🔄 Resetting drag state")
        #endif
        draggedItem = nil
        dragSourceSection = nil
        targetedSection = nil
        targetedIndex = nil
    }
}

struct TabSquareView: View {
    let name: String
    let isDragged: Bool

    var body: some View {
        Button(action: {
            #if DEBUG
                print("Activated: \(name)")
            #endif
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(String(name.prefix(2)))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isDragged ? 0.5 : 1.0)
        .scaleEffect(isDragged ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragged)
    }
}

struct TabRowView: View {
    let name: String
    let isDragged: Bool
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            #if DEBUG
                print("Activated: \(name)")
            #endif
        }) {
            HStack(spacing: 8) {
                Text(String(name.prefix(1)))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)

                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if isHovering {
                    Button(action: {
                        #if DEBUG
                            print("Close \(name)")
                        #endif
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(3)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isDragged ? 0.5 : 1.0)
        .scaleEffect(isDragged ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragged)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Row center PreferenceKeys

private struct EssentialRowCentersKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Cell frames for essentials grid (local coordinates within grid container)
private struct EssentialCellFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SpacePinnedRowCentersKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Local row frames (Space Pinned)
private struct SpacePinnedRowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct RegularRowCentersKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Local row frames (Regular)
private struct RegularRowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Drop Delegate

struct SectionBoundedDropDelegate: DropDelegate {
    @Binding var targetedSection: SimpleDragPreview.DragSection?
    @Binding var targetedIndex: Int?
    @Binding var isDragging: Bool
    let section: SimpleDragPreview.DragSection
    let boundariesProvider: () -> [CGFloat]
    let onPerform: (Int) -> Bool

    func validateDrop(info _: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        updateTarget(with: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(with: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let y = info.location.y
        let idx = insertionIndex(forY: y)
        let result = onPerform(idx)
        withAnimation(.easeOut(duration: 0.12)) {
            targetedSection = nil
            targetedIndex = nil
        }
        // Safety: ensure highlight clears even if parent state lags
        DispatchQueue.main.async {
            targetedSection = nil
            targetedIndex = nil
        }
        // Drag session ended
        DispatchQueue.main.async { isDragging = false }
        return result
    }

    func dropExited(info _: DropInfo) {
        // Intentionally keep current highlight while dragging across gaps/sections.
        // We only clear on successful drop.
    }

    private func updateTarget(with info: DropInfo) {
        targetedSection = section
        let newIndex = insertionIndex(forY: info.location.y)
        if targetedIndex != newIndex {
            targetedIndex = newIndex
            performMoveHaptic()
        } else {
            targetedIndex = newIndex
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
        return bestIndex
    }
}

// MARK: - Grid Drop Delegate (Essentials)

// Grid boundary model for essentials grid
enum GridBoundaryOrientation { case horizontal, vertical }
struct GridBoundary {
    let index: Int
    let orientation: GridBoundaryOrientation
    let frame: CGRect // in grid local coords
}

struct GridBoundedDropDelegate: DropDelegate {
    @Binding var targetedSection: SimpleDragPreview.DragSection?
    @Binding var targetedIndex: Int?
    @Binding var isDragging: Bool
    let section: SimpleDragPreview.DragSection
    let boundariesProvider: () -> [GridBoundary]
    let onPerform: (Int) -> Bool

    func validateDrop(info _: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { updateTarget(with: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(with: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let idx = insertionIndex(for: info.location)
        let result = onPerform(idx)
        withAnimation(.easeOut(duration: 0.12)) {
            targetedSection = nil
            targetedIndex = nil
        }
        DispatchQueue.main.async {
            targetedSection = nil
            targetedIndex = nil
        }
        DispatchQueue.main.async { isDragging = false }
        return result
    }

    func dropExited(info _: DropInfo) {
        // Keep highlight persistent during drag across sections.
    }

    private func updateTarget(with info: DropInfo) {
        targetedSection = section
        let newIndex = insertionIndex(for: info.location)
        if targetedIndex != newIndex {
            targetedIndex = newIndex
            performMoveHaptic()
        } else {
            targetedIndex = newIndex
        }
    }

    private func insertionIndex(for point: CGPoint) -> Int {
        // Choose nearest boundary (line) by orthogonal distance to line segment
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

    private func distance(_ p: CGPoint, to b: GridBoundary) -> CGFloat {
        switch b.orientation {
        case .horizontal:
            let y = b.frame.midY
            // Horizontal segment extents in X
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

// MARK: - Haptics

@inline(__always)
private func performMoveHaptic() {
    #if canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    #endif
}

// (Removed explicit labeled cross-category zones; boundaries already handle
// bottom-of-essentials and top-of-regular as distinct targets.)

// MARK: - Container top PreferenceKeys

private struct EssentialContainerTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SpacePinnedContainerTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct RegularContainerTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension SimpleDragPreview.DragSection {
    var description: String {
        switch self {
        case .essential: return "Essential"
        case .spacePinned: return "Space Pinned"
        case .regular: return "Regular"
        }
    }
}

#Preview {
    SimpleDragPreview()
}
