//
//  DraggableTabView.swift
//  Nook
//
//  Draggable wrapper for tab views with drag state management
//

import SwiftUI
import AppKit

struct DraggableTabView<Content: View>: View {
    let tab: Tab
    let container: TabDragManager.DragContainer
    let index: Int
    let dragManager: TabDragManager
    let content: Content

    @State private var dragGesture = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragLockManager = DragLockManager.shared
    @State private var dragSessionID: String = UUID().uuidString
    
    init(
        tab: Tab,
        container: TabDragManager.DragContainer,
        index: Int,
        dragManager: TabDragManager,
        @ViewBuilder content: () -> Content
    ) {
        self.tab = tab
        self.container = container
        self.index = index
        self.dragManager = dragManager
        self.content = content()
    }
    
    var body: some View {
        content
            .opacity(dragManager.isDragging && dragManager.draggedTab?.id == tab.id ? 0.5 : 1.0)
            .scaleEffect(dragManager.isDragging && dragManager.draggedTab?.id == tab.id ? 0.95 : 1.0)
            .offset(dragOffset)
            .animation(.easeInOut(duration: 0.2), value: dragManager.isDragging)
            .animation(.easeInOut(duration: 0.2), value: dragOffset)
            .onDrag {
                // Pre-emptively acquire drag lock BEFORE anything else
                guard dragLockManager.startDrag(ownerID: dragSessionID) else {
                    print("🚫 [DraggableTabView] Tab drag blocked at onset - \(dragLockManager.debugInfo)")
                    return NSItemProvider(object: tab.id.uuidString as NSString)
                }

                // Start the drag operation with state validation
                DispatchQueue.main.async {
                    // Harden the start guard to prevent concurrent drags
                    guard !dragManager.isDragging else {
                        dragLockManager.endDrag(ownerID: dragSessionID)
                        return
                    }
                    dragManager.startDrag(tab: tab, from: container, at: index)
                }
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if !dragGesture {
                            // Pre-emptively acquire drag lock for gesture-based drag
                            guard dragLockManager.startDrag(ownerID: dragSessionID) else {
                                print("🚫 [DraggableTabView] Gesture drag blocked at onset - \(dragLockManager.debugInfo)")
                                return
                            }

                            dragGesture = true
                            // Enhanced drag gesture coordination - prevent duplicate drag start calls
                            if !dragManager.isDragging {
                                dragManager.startDrag(tab: tab, from: container, at: index)
                            }
                        }

                        // Update drag offset for visual feedback
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        dragGesture = false

                        // Ensure drag offset is properly reset in all scenarios
                        withAnimation(.easeOut(duration: 0.15)) {
                            dragOffset = .zero
                        }

                        // Enhanced drag end handling with state validation
                        if dragManager.isDragging && dragManager.draggedTab?.id == tab.id {
                            // Add validation that the drag manager is in the expected state
                            guard dragManager.draggedTab != nil else {
                                dragLockManager.endDrag(ownerID: dragSessionID)
                                return
                            }
                            // Only cancel drag if no valid drop target
                            if dragManager.dropTarget == .none {
                                dragManager.cancelDrag()
                            }
                        }

                        // Always release drag lock when gesture ends
                        dragLockManager.endDrag(ownerID: dragSessionID)
                    }
            )
            .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
                // Ensure drag lock is released when any tab drag ends
                dragLockManager.endDrag(ownerID: dragSessionID)
            }
    }
}

// MARK: - Extension for easy usage

extension View {
    func draggableTab(
        tab: Tab,
        container: TabDragManager.DragContainer,
        index: Int,
        dragManager: TabDragManager
    ) -> some View {
        DraggableTabView(
            tab: tab,
            container: container,
            index: index,
            dragManager: dragManager
        ) {
            self
        }
    }
}
