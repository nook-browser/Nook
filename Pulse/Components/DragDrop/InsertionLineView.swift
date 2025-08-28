//
//  InsertionLineView.swift
//  Pulse
//
//  Visual insertion line for drag & drop feedback
//

import SwiftUI

struct InsertionLineView: View {
    @ObservedObject var dragManager: TabDragManager
    
    init(dragManager: TabDragManager) {
        self.dragManager = dragManager
    }
    
    var body: some View {
        let shouldShow = dragManager.showInsertionLine && shouldShowInsertionLine
        
        return GeometryReader { geometry in
            ZStack {
                if shouldShow {
                    let frame = dragManager.insertionLineFrame
                    
                    // Convert relative container coordinates to absolute window coordinates
                    let windowX = effectiveFrameX + 8  // Add sidebar padding (8pt)
                    
                    // Y coordinate conversion is more complex:
                    // 1. Add nav/URL bar offset (~70pt)  
                    // 2. Add essentials grid height (~150pt)
                    // 3. Add scroll offset for the space this coordinate belongs to
                    // 4. Add the space header heights for spaces above this one
                    let baseOffset: CGFloat = 70 + 150  // nav + essentials
                    let spaceOffset = calculateSpaceOffset(for: dragManager.dropTarget)
                    let windowY = effectiveFrameY + baseOffset + spaceOffset
                    
                    let _ = print("🎯 [Coordinate Conversion] relative(\(effectiveFrameY)) + base(\(baseOffset)) + space(\(spaceOffset)) = window(\(windowY))")
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.9),
                                    Color.red,
                                    Color.red.opacity(0.9)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: effectiveFrameWidth, height: 4)
                        .position(x: windowX, y: windowY)
                        .animation(.easeInOut(duration: 0.15), value: dragManager.insertionLineFrame)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(9999) // Very high z-index to ensure visibility
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false) // Don't interfere with drag operations
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowInsertionLine: Bool {
        let hasValidFrame = dragManager.insertionLineFrame != .zero
        if !hasValidFrame && dragManager.showInsertionLine {
            print("⚠️ [InsertionLineView] Show requested but frame is zero: \(dragManager.insertionLineFrame)")
        }
        return hasValidFrame
    }
    
    private var effectiveFrameWidth: CGFloat {
        // Fallback frame handling for empty zones
        let frameWidth = dragManager.insertionLineFrame.width
        return frameWidth > 0 ? frameWidth : 200 // Reasonable fallback width
    }
    
    private var effectiveFrameX: CGFloat {
        // Coordinate with section overlays - use frame if valid, otherwise center
        let frameX = dragManager.insertionLineFrame.midX
        return frameX > 0 ? frameX : 100 // Fallback to reasonable center position
    }
    
    private var effectiveFrameY: CGFloat {
        // Z-index considerations - use frame if valid, otherwise reasonable fallback
        let frameY = dragManager.insertionLineFrame.midY
        return frameY > 0 ? frameY : 20 // Fallback to top area position
    }
    
    private func calculateSpaceOffset(for target: TabDragManager.DragContainer) -> CGFloat {
        // Calculate vertical offset for the specific space container
        // This is an approximation - ideally we'd get actual space positions
        
        switch target {
        case .none, .essentials:
            return 0 // Already handled in baseOffset
            
        case .spacePinned(let spaceId), .spaceRegular(let spaceId):
            // For now, assume first space starts immediately after essentials
            // Each space has a header (~30pt) + pinned section (~variable) + regular section
            // This is a simplified calculation - in reality you'd want to:
            // 1. Get the actual space index/order
            // 2. Sum up the heights of all spaces above this one
            // 3. Account for scroll position
            
            // Simple approximation: assume we're in the first space
            let spaceHeaderHeight: CGFloat = 30
            let averagePinnedSectionHeight: CGFloat = 60 // varies by space
            
            if case .spacePinned = target {
                return spaceHeaderHeight // Just the space header
            } else {
                return spaceHeaderHeight + averagePinnedSectionHeight // Header + pinned section
            }
        }
    }
}

struct InsertionLineModifier: ViewModifier {
    let dragManager: TabDragManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Separate layer for insertion line with high z-index
            InsertionLineView(dragManager: dragManager)
                .animation(.easeInOut(duration: 0.15), value: dragManager.showInsertionLine)
                .zIndex(9999) // Very high z-index
        }
    }
}

extension View {
    func insertionLineOverlay(dragManager: TabDragManager) -> some View {
        modifier(InsertionLineModifier(dragManager: dragManager))
    }
}