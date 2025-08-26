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
    @State private var pinnedTopYInUnified: CGFloat = 0
    @State private var regularTopYInUnified: CGFloat = 0
    
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
    
    // Named coordinate spaces (scoped to this instance)
    private var pinnedSectionSpaceName: String { "SpacePinnedSection-\(space.id.uuidString)" }
    private var regularSectionSpaceName: String { "RegularSection-\(space.id.uuidString)" }
    private var unifiedSpaceName: String { "SpaceUnified-\(space.id.uuidString)" }
    
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
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(
                            key: PinnedContainerTopInUnifiedKey.self,
                            value: proxy.frame(in: .named(unifiedSpaceName)).minY
                        )
                    })
                    .onPreferenceChange(PinnedContainerTopInUnifiedKey.self) { top in
                        pinnedTopYInUnified = top
                    }
                    .overlay(
                        SpacePinnedInsertionOverlay(spaceId: space.id, frames: spacePinnedFrames)
                    )
                } else {
                    // Empty pinned section: provide a clear, easy drop target
                    ZStack { Color.clear.frame(height: 44) }
                        .coordinateSpace(name: pinnedSectionSpaceName)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(
                                key: PinnedContainerTopInUnifiedKey.self,
                                value: proxy.frame(in: .named(unifiedSpaceName)).minY
                            )
                        })
                        .onPreferenceChange(PinnedContainerTopInUnifiedKey.self) { top in
                            pinnedTopYInUnified = top
                        }
                        .overlay(
                            SpacePinnedInsertionOverlay(spaceId: space.id, frames: [:])
                        )
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
                            }
                            .background(GeometryReader { proxy in
                                Color.clear.preference(
                                    key: RegularContainerTopInUnifiedKey.self,
                                    value: proxy.frame(in: .named(unifiedSpaceName)).minY
                                )
                            })
                            .onPreferenceChange(RegularContainerTopInUnifiedKey.self) { top in
                                regularTopYInUnified = top
                            }
                            .overlay(
                                SpaceRegularInsertionOverlay(spaceId: space.id, frames: regularFrames)
                            )
                        } else {
                            // Empty regular section: provide a drop target
                            ZStack { Color.clear.frame(height: 40) }
                                .coordinateSpace(name: regularSectionSpaceName)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: RegularContainerTopInUnifiedKey.self,
                                        value: proxy.frame(in: .named(unifiedSpaceName)).minY
                                    )
                                })
                                .onPreferenceChange(RegularContainerTopInUnifiedKey.self) { top in
                                    regularTopYInUnified = top
                                }
                                .overlay(
                                    SpaceRegularInsertionOverlay(spaceId: space.id, frames: [:])
                                )
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: tabs.count)
                }
                .coordinateSpace(name: unifiedSpaceName)
                .contentShape(Rectangle())
                // Use space-aware delegate that normalizes coordinates between sections
                .onDrop(of: [.text], delegate: SpaceUnifiedDropDelegate(
                    dragManager: (dragManager ?? TabDragManager.shared),
                    spaceId: space.id,
                    pinnedFramesProvider: { spacePinnedFrames },
                    regularFramesProvider: { regularFrames },
                    pinnedTopYProvider: { pinnedTopYInUnified },
                    regularTopYProvider: { regularTopYInUnified },
                    onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
                ))
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
    
    private struct PinnedContainerTopInUnifiedKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
    
    private struct RegularContainerTopInUnifiedKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
    
    struct SpacePinnedInsertionOverlay: View {
        let spaceId: UUID
        let frames: [Int: CGRect]
        @ObservedObject var dragManager = TabDragManager.shared
        
        var body: some View {
            let boundaries = SidebarDropMath.computeListBoundaries(frames: frames)
            print("🔍 SpacePinnedOverlay - isDragging: \(dragManager.isDragging), dropTarget: \(dragManager.dropTarget)")
            return SidebarSectionInsertionOverlay(
                isActive: dragManager.isDragging && dragManager.dropTarget == .spacePinned(spaceId),
                index: max(dragManager.insertionIndex, 0),
                boundaries: boundaries
            )
        }
    }
    
    struct SpaceRegularInsertionOverlay: View {
        let spaceId: UUID
        let frames: [Int: CGRect]
        @ObservedObject var dragManager = TabDragManager.shared
        
        var body: some View {
            let boundaries = SidebarDropMath.computeListBoundaries(frames: frames)
            print("🔍 SpaceRegularOverlay - isDragging: \(dragManager.isDragging), dropTarget: \(dragManager.dropTarget)")
            return SidebarSectionInsertionOverlay(
                isActive: dragManager.isDragging && dragManager.dropTarget == .spaceRegular(spaceId),
                index: max(dragManager.insertionIndex, 0),
                boundaries: boundaries
            )
        }
    }
}
