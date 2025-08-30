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
    @State private var cachedPinnedEmptyBoundaries: [CGFloat] = [] // empty zone uses explicit frame provider
    @State private var cachedRegularEmptyBoundaries: [CGFloat] = [50.0/3.0]
    // Global frames for pinned and regular sections
    @State private var pinnedSectionGlobalFrame: CGRect = .zero
    @State private var regularSectionGlobalFrame: CGRect = .zero
    
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
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { pinnedSectionGlobalFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                                pinnedSectionGlobalFrame = newFrame
                            }
                    })
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
                            // Provide a GLOBAL frame for the insertion line
                            let section = pinnedSectionGlobalFrame
                            let validWidth = max(section.width, 0)
                            let y = section.minY + 22
                            return CGRect(x: section.minX, y: y, width: validWidth, height: 3)
                        },
                        globalFrameProvider: { pinnedSectionGlobalFrame },
                        onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                    ))
                } else {
                    // Empty pinned section: provide a clear, easy drop target
                    ZStack { Color.clear.frame(height: 1) }
                        .coordinateSpace(name: pinnedSectionSpaceName)
                        .background(GeometryReader { proxy in
                            Color.clear
                                .onAppear { pinnedSectionGlobalFrame = proxy.frame(in: .global) }
                                .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                                    pinnedSectionGlobalFrame = newFrame
                                }
                        })
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
                                    return [] // no boundaries → use frame provider
                                }
                                return cachedPinnedEmptyBoundaries
                            },
                            insertionLineFrameProvider: {
                                // Provide a GLOBAL frame for the insertion line
                                let section = pinnedSectionGlobalFrame
                                let lineHeight: CGFloat = 3
                                let validWidth = max(section.width - 20, 1) // match non-empty margins
                                let yLocal = max((section.height - lineHeight) / 2, 0) // center within tiny area
                                // Return LOCAL coordinates; delegate converts using globalFrameProvider
                                return CGRect(x: 10, y: yLocal, width: validWidth, height: lineHeight)
                            },
                            globalFrameProvider: { pinnedSectionGlobalFrame },
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
                            .background(GeometryReader { proxy in
                                Color.clear
                                    .onAppear { regularSectionGlobalFrame = proxy.frame(in: .global) }
                                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                                        regularSectionGlobalFrame = newFrame
                                    }
                            })
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
                                    // Provide a GLOBAL frame for the insertion line
                                    let section = regularSectionGlobalFrame
                                    let validWidth = max(section.width, 0)
                                    return CGRect(x: section.minX, y: section.minY + 20, width: validWidth, height: 3)
                                },
                                globalFrameProvider: { regularSectionGlobalFrame },
                                onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                            ))
                        } else {
                            // Empty regular section: provide a drop target
                            ZStack { Color.clear.frame(height: 50) }
                                .coordinateSpace(name: regularSectionSpaceName)
                                .background(GeometryReader { proxy in
                                    Color.clear
                                        .onAppear { regularSectionGlobalFrame = proxy.frame(in: .global) }
                                        .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                                            regularSectionGlobalFrame = newFrame
                                        }
                                })
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
                                        // Provide a GLOBAL frame for the insertion line
                                        let section = regularSectionGlobalFrame
                                        let validWidth = max(section.width, 0)
                                        let y = max(50.0/3.0, 0)
                                        return CGRect(x: section.minX, y: section.minY + y, width: validWidth, height: 3)
                                    },
                                    globalFrameProvider: { regularSectionGlobalFrame },
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
    
    // (no global frame preference keys)
    
    
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
