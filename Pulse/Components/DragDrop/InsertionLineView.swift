//
//  InsertionLineView.swift
//  Pulse
//
//  Visual insertion line for drag & drop feedback
//

import SwiftUI

struct InsertionLineView: View {
    let dragManager: TabDragManager
    
    var body: some View {
        let shouldShow = dragManager.showInsertionLine && shouldShowInsertionLine
        
        return GeometryReader { geometry in
            ZStack {
                // MASSIVE TEST - Fill the entire window with bright color when dragging
                if dragManager.isDragging {
                    let _ = print("🔥 [InsertionLineView] DRAWING MASSIVE TEST VIEW - isDragging=true")
                    Rectangle()
                        .fill(Color.red.opacity(0.8)) // Semi-transparent red overlay
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .zIndex(9999)
                        .overlay(
                            Text("DRAG TEST - CAN YOU SEE THIS?")
                                .font(.system(size: 48, weight: .black))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 4, x: 2, y: 2)
                        )
                } else {
                    let _ = print("🔥 [InsertionLineView] Not dragging - isDragging=false")
                }
                
                if shouldShow {
                    let _ = print("👁️ [InsertionLineView] Showing insertion line at frame: \(dragManager.insertionLineFrame)")
                    let _ = print("👁️ [InsertionLineView] Effective position: x=\(effectiveFrameX), y=\(effectiveFrameY), width=\(effectiveFrameWidth)")
                    let _ = print("👁️ [InsertionLineView] Geometry size: \(geometry.size)")
                    
                    // TEST: Fixed position to see if it renders at all
                    Rectangle()
                        .fill(Color.yellow) // Bright yellow for visibility
                        .frame(width: 200, height: 50) // Large and thick
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Center of screen
                        .animation(.easeInOut(duration: 0.15), value: dragManager.insertionLineFrame)
                        .zIndex(8000) // Very high z-index
                        .overlay(
                            Text("INSERTION LINE TEST")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false) // Don't interfere with drag operations
    }
    
    // MARK: - Empty Zone Enhancements
    
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