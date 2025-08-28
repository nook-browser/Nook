//
//  SpaceView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SpaceView: View {
    let space: Space
    let isActive: Bool
    let width: CGFloat
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager
    @State private var spacePinnedFrames: [Int: CGRect] = [:]
    @State private var regularFrames: [Int: CGRect] = [:]
    @State private var cachedSpacePinnedBoundaries: [CGFloat] = []
    @State private var cachedRegularBoundaries: [CGFloat] = []
    @State private var cachedPinnedEmptyBoundaries: [CGFloat] = [20] // top third of 60
    @State private var cachedRegularEmptyBoundaries: [CGFloat] = [50.0/3.0]
    
    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    
    // Get tabs directly from TabManager to ensure proper observation
    private var tabs: [Tab] {
        browserManager.tabManager.tabs(in: space)
    }
    
    private var spacePinnedTabs: [Tab] {
        browserManager.tabManager.spacePinnedTabs(for: space.id)
    }
    
    // Enhanced named coordinate spaces with unique identifiers to prevent conflicts
    private var pinnedSectionSpaceName: String { 
        "SpacePinnedSection-\(space.id.uuidString)" 
    }
    private var regularSectionSpaceName: String { 
        "RegularSection-\(space.id.uuidString)" 
    }
    
    var body: some View {
        return VStack(spacing: 8) {
            SpaceTittle(space: space)
            
            if !spacePinnedTabs.isEmpty || !tabs.isEmpty {
                SpaceSeparator()
            }
            
            // Unified container around Pinned + New Tab + Regular to bridge gaps in drag updates
            VStack(spacing: 0) {
                // Space-level pinned tabs FIRST (below space title, above New Tab)
                if !spacePinnedTabs.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(spacePinnedTabs.enumerated()), id: \.element.id) { index, tab in
                            SpaceTab(
                                tab: tab,
                                action: { onActivateTab(tab) },
                                onClose: { onCloseTab(tab) },
                                onMute: { onMuteTab(tab) }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .contextMenu {
                                Button { browserManager.tabManager.unpinTabFromSpace(tab) } label: { Label("Unpin from Space", systemImage: "pin.slash") }
                                Button { onPinTab(tab) } label: { Label("Pin Globally", systemImage: "pin.circle") }
                                Divider()
                                Button { onCloseTab(tab) } label: { Label("Close tab", systemImage: "xmark") }
                            }
                            .draggableTab(
                                tab: tab,
                                container: .spacePinned(space.id),
                                index: index,
                                dragManager: dragManager ?? TabDragManager.shared
                            )
                            .background(GeometryReader { proxy in
                                let local = proxy.frame(in: .named(pinnedSectionSpaceName))
                                Color.clear.preference(key: SpacePinnedRowFramesKey.self, value: [index: local])
                            })
                        }
                    }
                    .coordinateSpace(name: pinnedSectionSpaceName)
                    .onPreferenceChange(SpacePinnedRowFramesKey.self) { frames in
                        spacePinnedFrames = frames
                        // Add validation that cached boundaries are properly updated
                        let newBoundaries = SidebarDropMath.computeListBoundaries(frames: frames)
                        if !newBoundaries.isEmpty {
                            cachedSpacePinnedBoundaries = newBoundaries
                        } else {
                            // Maintain empty boundary fallback if computation fails
                            cachedSpacePinnedBoundaries = []
                        }
                    }
                    .overlay(
                        SpacePinnedInsertionOverlay(spaceId: space.id, boundaries: cachedSpacePinnedBoundaries)
                    )
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: SidebarSectionDropDelegate(
                        dragManager: (dragManager ?? TabDragManager.shared),
                        container: .spacePinned(space.id),
                        boundariesProvider: { 
                            // Add validation that boundariesProvider returns consistent data
                            guard !cachedSpacePinnedBoundaries.isEmpty else {
                                return cachedPinnedEmptyBoundaries
                            }
                            return cachedSpacePinnedBoundaries
                        },
                        insertionLineFrameProvider: {
                            // Ensure insertionLineFrameProvider handles edge cases properly
                            let validWidth = max(width, 0)
                            return CGRect(x: 0, y: 22, width: validWidth, height: 3)
                        },
                        onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                    ))
                } else {
                    // Empty pinned section: provide a clear, easy drop target
                    ZStack { Color.clear.frame(height: 60) }
                        .coordinateSpace(name: pinnedSectionSpaceName)
                        .overlay(
                            SpacePinnedInsertionOverlay(spaceId: space.id, boundaries: cachedPinnedEmptyBoundaries)
                        )
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], delegate: SidebarSectionDropDelegate(
                            dragManager: (dragManager ?? TabDragManager.shared),
                            container: .spacePinned(space.id),
                            boundariesProvider: { 
                                // Ensure empty boundary fallbacks are properly maintained
                                guard !cachedPinnedEmptyBoundaries.isEmpty else {
                                    return [20] // fallback boundary
                                }
                                return cachedPinnedEmptyBoundaries 
                            },
                            insertionLineFrameProvider: {
                                // Add error handling for edge cases
                                let validWidth = max(width, 0)
                                let validY = max(60.0/3.0, 0)
                                return CGRect(x: 0, y: validY, width: validWidth, height: 3)
                            },
                            onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                        ))
                }
                
                NewTabButton()
                
                ScrollView {
                    VStack(spacing: 2) {
                        
                        // Regular tabs
                        if !tabs.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                    SpaceTab(
                                        tab: tab,
                                        action: { onActivateTab(tab) },
                                        onClose: { onCloseTab(tab) },
                                        onMute: { onMuteTab(tab) }
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .contextMenu {
                                        Button {
                                            onMoveTabUp(tab)
                                        } label: {
                                            Label("Move Up", systemImage: "arrow.up")
                                        }
                                        .disabled(isFirstTab(tab))
                                        
                                        Button {
                                            onMoveTabDown(tab)
                                        } label: {
                                            Label("Move Down", systemImage: "arrow.down")
                                        }
                                        .disabled(isLastTab(tab))
                                        
                                        Divider()
                                        
                                        Button {
                                            browserManager.tabManager.pinTabToSpace(tab, spaceId: space.id)
                                        } label: {
                                            Label("Pin to Space", systemImage: "pin")
                                        }
                                        
                                        Button {
                                            onPinTab(tab)
                                        } label: {
                                            Label("Pin Globally", systemImage: "pin.circle")
                                        }
                                        
                                        Button {
                                            onCloseTab(tab)
                                        } label: {
                                            Label("Close tab", systemImage: "xmark")
                                        }
                                    }
                                    .draggableTab(
                                        tab: tab,
                                        container: .spaceRegular(space.id),
                                        index: index,
                                        dragManager: dragManager ?? TabDragManager.shared
                                    )
                                    .background(GeometryReader { proxy in
                                        let local = proxy.frame(in: .named(regularSectionSpaceName))
                                        Color.clear.preference(key: RegularRowFramesKey.self, value: [index: local])
                                    })
                                }
                            }
                            .coordinateSpace(name: regularSectionSpaceName)
                            .onPreferenceChange(RegularRowFramesKey.self) { frames in
                                regularFrames = frames
                                // Ensure boundary updates are consistent with frame changes
                                let newBoundaries = SidebarDropMath.computeListBoundaries(frames: frames)
                                if !newBoundaries.isEmpty {
                                    cachedRegularBoundaries = newBoundaries
                                } else {
                                    // Add error handling for cases where boundary computation fails
                                    cachedRegularBoundaries = []
                                }
                            }
                            .overlay(
                                SpaceRegularInsertionOverlay(spaceId: space.id, boundaries: cachedRegularBoundaries)
                            )
                            .padding(.top, 8)
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], delegate: SidebarSectionDropDelegate(
                                dragManager: (dragManager ?? TabDragManager.shared),
                                container: .spaceRegular(space.id),
                                boundariesProvider: { 
                                    // Add validation that boundary updates are consistent with frame changes
                                    guard !cachedRegularBoundaries.isEmpty else {
                                        return cachedRegularEmptyBoundaries
                                    }
                                    return cachedRegularBoundaries
                                },
                                insertionLineFrameProvider: {
                                    // Ensure coordinate space transformations don't fail
                                    let validWidth = max(width, 0)
                                    return CGRect(x: 0, y: 20, width: validWidth, height: 3)
                                },
                                onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                            ))
                        } else {
                            // Empty regular section: provide a drop target
                            ZStack { Color.clear.frame(height: 50) }
                                .coordinateSpace(name: regularSectionSpaceName)
                                .overlay(
                                    SpaceRegularInsertionOverlay(spaceId: space.id, boundaries: cachedRegularEmptyBoundaries)
                                )
                                .padding(.top, 8)
                                .contentShape(Rectangle())
                                .onDrop(of: [.text], delegate: SidebarSectionDropDelegate(
                                    dragManager: (dragManager ?? TabDragManager.shared),
                                    container: .spaceRegular(space.id),
                                    boundariesProvider: { 
                                        // Add error handling for cases where boundary computation fails
                                        guard !cachedRegularEmptyBoundaries.isEmpty else {
                                            return [50.0/3.0] // fallback boundary
                                        }
                                        return cachedRegularEmptyBoundaries 
                                    },
                                    insertionLineFrameProvider: {
                                        // Improve error handling when coordinate space transformations fail
                                        let validWidth = max(width, 0)
                                        let validY = max(50.0/3.0, 0)
                                        return CGRect(x: 0, y: validY, width: validWidth, height: 3)
                                    },
                                    onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                                ))
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: tabs.count)
                }
                .contentShape(Rectangle())
                Spacer()
            }
            .frame(width: width)
            .contentShape(Rectangle())
            .backgroundDraggable()
            .scrollTargetLayout()
        }
        
        func isFirstTab(_ tab: Tab) -> Bool {
            return tabs.first?.id == tab.id
        }
        
        func isLastTab(_ tab: Tab) -> Bool {
            return tabs.last?.id == tab.id
        }
    }
    
    // MARK: - Local State & Keys
    
    private struct SpacePinnedRowFramesKey: PreferenceKey {
        static var defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
    
    private struct RegularRowFramesKey: PreferenceKey {
        static var defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
    
    
    struct SpacePinnedInsertionOverlay: View {
        let spaceId: UUID
        let boundaries: [CGFloat]
        @Environment(\.tabDragManager) private var dragManager
        
        var body: some View {
            let dm = dragManager ?? TabDragManager.shared
            let isActive = dm.isDragging && dm.dropTarget == .spacePinned(spaceId)
            let _ = print("🔵 [SpacePinnedInsertionOverlay] spaceId=\(spaceId), isActive=\(isActive), isDragging=\(dm.isDragging), target=\(dm.dropTarget), index=\(dm.insertionIndex)")
            return SidebarSectionInsertionOverlay(
                isActive: isActive,
                index: max(dm.insertionIndex, 0),
                boundaries: boundaries
            )
        }
    }
    
    struct SpaceRegularInsertionOverlay: View {
        let spaceId: UUID
        let boundaries: [CGFloat]
        @Environment(\.tabDragManager) private var dragManager
        
        var body: some View {
            let dm = dragManager ?? TabDragManager.shared
            let isActive = dm.isDragging && dm.dropTarget == .spaceRegular(spaceId)
            let _ = print("🔵 [SpaceRegularInsertionOverlay] spaceId=\(spaceId), isActive=\(isActive), isDragging=\(dm.isDragging), target=\(dm.dropTarget), index=\(dm.insertionIndex)")
            return SidebarSectionInsertionOverlay(
                isActive: isActive,
                index: max(dm.insertionIndex, 0),
                boundaries: boundaries
            )
        }
    }
}
