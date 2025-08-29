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
        let shouldShow = dragManager.showInsertionLine && dragManager.insertionLineFrame != .zero
        
        return GeometryReader { _ in
            ZStack {
                if shouldShow {
                    let frame = dragManager.insertionLineFrame
                    
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
                        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                        .position(x: frame.midX, y: frame.midY)
                        .animation(.easeInOut(duration: 0.15), value: dragManager.insertionLineFrame)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(9999)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
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
