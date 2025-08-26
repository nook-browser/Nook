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
        ZStack {
            if dragManager.showInsertionLine {
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.8),
                                Color.accentColor,
                                Color.accentColor.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: dragManager.insertionLineFrame.width, height: 3)
                    .position(
                        x: dragManager.insertionLineFrame.midX,
                        y: dragManager.insertionLineFrame.midY
                    )
                    .animation(.easeInOut(duration: 0.2), value: dragManager.insertionLineFrame)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 2, x: 0, y: 0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false) // Don't interfere with drag operations
    }
}

struct InsertionLineModifier: ViewModifier {
    let dragManager: TabDragManager
    
    func body(content: Content) -> some View {
        content
            .overlay(
                InsertionLineView(dragManager: dragManager)
                    .animation(.easeInOut(duration: 0.15), value: dragManager.showInsertionLine)
            )
    }
}

extension View {
    func insertionLineOverlay(dragManager: TabDragManager) -> some View {
        modifier(InsertionLineModifier(dragManager: dragManager))
    }
}