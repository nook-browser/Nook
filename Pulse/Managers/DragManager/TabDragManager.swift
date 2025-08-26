//
//  TabDragManager.swift
//  Pulse
//
//  Advanced drag & drop system for tab reordering
//

import SwiftUI
import AppKit

@MainActor
class TabDragManager: ObservableObject {
    // MARK: - Drag State
    @Published var isDragging: Bool = false
    @Published var draggedTab: Tab?
    @Published var draggedTabOriginalIndex: Int = -1
    @Published var draggedTabOriginalContainer: DragContainer = .none
    
    // MARK: - Drop Target State
    @Published var dropTarget: DragContainer = .none
    @Published var insertionIndex: Int = -1
    @Published var insertionSpaceId: UUID?
    
    // MARK: - Visual Feedback
    @Published var showInsertionLine: Bool = false
    @Published var insertionLineFrame: CGRect = .zero
    
    // MARK: - Haptics
    private var lastHapticIndex: Int = -1
    private let hapticPerformer = NSHapticFeedbackManager.defaultPerformer
    
    enum DragContainer: Equatable {
        case none
        case essentials
        case spacePinned(UUID) // space ID
        case spaceRegular(UUID) // space ID
    }
    
    // MARK: - Drag Operations
    
    func startDrag(tab: Tab, from container: DragContainer, at index: Int) {
        isDragging = true
        draggedTab = tab
        draggedTabOriginalIndex = index
        draggedTabOriginalContainer = container
        
        print("🚀 Started dragging: \(tab.name) from \(container) at index \(index)")
    }
    
    func updateDragTarget(container: DragContainer, insertionIndex: Int, spaceId: UUID? = nil) {
        guard isDragging else { return }
        
        let previousIndex = self.insertionIndex
        
        self.dropTarget = container
        self.insertionIndex = insertionIndex
        self.insertionSpaceId = spaceId
        
        // Trigger haptic feedback when insertion line moves
        if insertionIndex != previousIndex && insertionIndex >= 0 {
            triggerHapticFeedback()
        }
        
        updateInsertionLineVisibility()
    }
    
    func updateInsertionLine(frame: CGRect) {
        insertionLineFrame = frame
        showInsertionLine = isDragging && insertionIndex >= 0
    }
    
    func endDrag(commit: Bool = true) -> DragOperation? {
        defer { resetDragState() }
        
        guard isDragging,
              let draggedTab = draggedTab,
              commit,
              insertionIndex >= 0 else {
            print("🚫 Drag cancelled or invalid")
            return nil
        }
        
        // Don't commit if dropping in the same position
        if dropTarget == draggedTabOriginalContainer && insertionIndex == draggedTabOriginalIndex {
            print("🔄 Drag ended in same position - no change needed")
            return nil
        }
        
        let operation = DragOperation(
            tab: draggedTab,
            fromContainer: draggedTabOriginalContainer,
            fromIndex: draggedTabOriginalIndex,
            toContainer: dropTarget,
            toIndex: insertionIndex,
            toSpaceId: insertionSpaceId
        )
        
        print("✅ Drag completed: \(draggedTab.name) from \(draggedTabOriginalContainer) to \(dropTarget) at \(insertionIndex)")
        
        return operation
    }
    
    private func triggerHapticFeedback() {
        // Only trigger haptic if we've moved to a different index
        guard insertionIndex != lastHapticIndex else { return }
        
        lastHapticIndex = insertionIndex
        hapticPerformer.perform(.alignment, performanceTime: .now)
        
        print("📳 Haptic feedback triggered for insertion at index \(insertionIndex)")
    }
    
    private func updateInsertionLineVisibility() {
        showInsertionLine = isDragging && insertionIndex >= 0 && dropTarget != .none
    }
    
    private func resetDragState() {
        isDragging = false
        draggedTab = nil
        draggedTabOriginalIndex = -1
        draggedTabOriginalContainer = .none
        dropTarget = .none
        insertionIndex = -1
        insertionSpaceId = nil
        showInsertionLine = false
        insertionLineFrame = .zero
        lastHapticIndex = -1
        
        print("🧹 Drag state reset")
    }
}

// MARK: - Drag Operation Result
struct DragOperation {
    let tab: Tab
    let fromContainer: TabDragManager.DragContainer
    let fromIndex: Int
    let toContainer: TabDragManager.DragContainer
    let toIndex: Int
    let toSpaceId: UUID?
    
    var isMovingBetweenContainers: Bool {
        return fromContainer != toContainer
    }
    
    var isReordering: Bool {
        return fromContainer == toContainer && fromIndex != toIndex
    }
}