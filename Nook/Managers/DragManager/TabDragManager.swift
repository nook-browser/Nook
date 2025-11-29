//
//  TabDragManager.swift
//  Nook
//
//  Advanced drag & drop system for tab reordering
//

import SwiftUI
import AppKit

@MainActor
class TabDragManager: ObservableObject {
    // MARK: - Shared Instance
    static let shared = TabDragManager()
    
    // MARK: - Drag State
    @Published var isDragging: Bool = false {
        didSet {
            print("🔥🔥🔥 [TabDragManager] isDragging changed: \(oldValue) -> \(isDragging)")
        }
    }
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
        case folder(UUID) // folder ID
    }
    
    // MARK: - Drag Operations
    
    func startDrag(tab: Tab, from container: DragContainer, at index: Int) {
        print("🚀 [TabDragManager] Starting drag: \(tab.name) from \(container) at index \(index)")
        isDragging = true
        draggedTab = tab
        draggedTabOriginalIndex = index
        draggedTabOriginalContainer = container
        insertionIndex = -1
        dropTarget = .none // highlight only when we first enter a target
        updateInsertionLineVisibility()
    }
    
    func updateDragTarget(container: DragContainer, insertionIndex: Int, spaceId: UUID? = nil) {
        guard isDragging else {
            print("⚠️ [TabDragManager] updateDragTarget called but not dragging")
            return
        }

        print("🎯 [TabDragManager] Update target: \(container) at \(insertionIndex)")

        let previousIndex = self.insertionIndex
        let previousContainer = self.dropTarget

        // Enhanced cross-zone state validation
        let validatedIndex = max(0, insertionIndex)

        // Validate state consistency for cross-zone transitions
        if previousContainer != .none && container != .none && previousContainer != container {
            // Clear stale state when switching between different container types
            clearStaleStateForTransition(from: previousContainer, to: container)
        }

        // Allow .none to clear state instead of blocking
        if container == .none {
            self.dropTarget = .none
            self.insertionIndex = -1
            self.insertionSpaceId = nil
            updateInsertionLine(frame: .zero)
            updateInsertionLineVisibility()
            return
        }

        // Validate that insertionIndex is appropriate for target container
        guard isValidInsertionIndex(validatedIndex, for: container) else {
            return
        }

        // Ensure insertionSpaceId is properly set/cleared based on container type
        let validatedSpaceId = validateSpaceIdForContainer(spaceId, container: container)

        self.dropTarget = container
        self.insertionIndex = validatedIndex
        self.insertionSpaceId = validatedSpaceId

        if container != previousContainer { 
            hapticPerformer.perform(.alignment, performanceTime: .now) 
        }
        if validatedIndex != previousIndex { 
            triggerHapticFeedback() 
        }

        updateInsertionLineVisibility()
    }
    
    func updateInsertionLine(frame: CGRect) {
        // Enhanced insertion line coordination with fallback frame handling
        let validFrame = frame.width > 0 && frame.height > 0 ? frame : .zero
        let isValidFrame = validFrame != .zero
        insertionLineFrame = validFrame
        showInsertionLine = isDragging && dropTarget != .none && isValidFrame
        
        print("📏 [TabDragManager] Insertion line: frame=\(validFrame), show=\(showInsertionLine), isDragging=\(isDragging), target=\(dropTarget)")
    }
    
    func endDrag(commit: Bool = true) -> DragOperation? {
        defer { 
            if commit {
                resetDragState()
            }
        }
        
        // Enhanced state validation for empty zones
        guard isDragging,
              let draggedTab = draggedTab,
              commit,
              insertionIndex >= 0,
              dropTarget != .none else {
            return nil
        }
        
        // Don't commit if dropping in the same position
        if dropTarget == draggedTabOriginalContainer && insertionIndex == draggedTabOriginalIndex {
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
        
        
        return operation
    }
    
    func cancelDrag() {
        // Release drag lock when cancelling tab drag
        DragLockManager.shared.forceReleaseAll()
        resetDragState()
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }
    
    private func triggerHapticFeedback() {
        // Only trigger haptic if we've moved to a different index
        guard insertionIndex != lastHapticIndex else { return }
        
        lastHapticIndex = insertionIndex
        hapticPerformer.perform(.alignment, performanceTime: .now)
    }
    
    private func updateInsertionLineVisibility() {
        // Enhanced visibility logic: show line only when over valid drop targets
        let wasShowing = showInsertionLine
        showInsertionLine = isDragging && dropTarget != .none
        
        if wasShowing != showInsertionLine {
            print("👁️ [TabDragManager] Insertion line visibility: \(showInsertionLine) (isDragging=\(isDragging), target=\(dropTarget))")
        }
    }
    
    private func resetDragState() {
        // Enhanced state reset with validation and safeguards
        guard isDragging || draggedTab != nil else {
            // Already reset, prevent multiple reset calls
            return
        }

        // Release drag lock when resetting drag state
        DragLockManager.shared.forceReleaseAll()

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

        // Validate that all state is properly cleared
        assert(!isDragging && draggedTab == nil && dropTarget == .none, "State not properly reset")
    }
    
    // MARK: - Cross-zone validation helpers
    
    private func clearStaleStateForTransition(from: DragContainer, to: DragContainer) {
        // Always zero insertionLineFrame and reset lastHapticIndex when from != to
        guard from != to else { return }
        
        insertionLineFrame = .zero
        lastHapticIndex = -1
        
        // If transitioning to .essentials, also set insertionSpaceId = nil
        if case .essentials = to {
            insertionSpaceId = nil
        }
    }
    
    private func isValidInsertionIndex(_ index: Int, for container: DragContainer) -> Bool {
        // Basic validation - index should be non-negative
        guard index >= 0 else { return false }

        // Additional container-specific validation could be added here
        switch container {
        case .none:
            return false
        case .essentials, .spacePinned, .spaceRegular, .folder:
            // For now, accept any non-negative index
            // More sophisticated validation could check actual container sizes
            return true
        }
    }
    
    private func validateSpaceIdForContainer(_ spaceId: UUID?, container: DragContainer) -> UUID? {
        switch container {
        case .none, .essentials:
            // These containers don't use space IDs
            return nil
        case .spacePinned(let containerSpaceId), .spaceRegular(let containerSpaceId):
            // Use the container's space ID if provided spaceId is nil or matches
            return spaceId ?? containerSpaceId
        case .folder:
            // Folders inherit space ID from their parent context
            return spaceId
        }
    }
}

extension Notification.Name {
    static let tabDragDidEnd = Notification.Name("tabDragDidEnd")
    static let tabManagerDidLoadInitialData = Notification.Name("tabManagerDidLoadInitialData")
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
