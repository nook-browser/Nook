//
//  SidebarResizeView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(Color.clear) // Invisible but interactive
            .frame(width: 12) // Wider hit area
            .overlay(
                // Visual indicator
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 2)
                    .animation(.easeInOut(duration: 0.1), value: isHovering)
            )
            .contentShape(Rectangle()) // Ensures the entire frame is interactive
            .onHover { hovering in
                guard browserManager.isSidebarVisible else { return }
                
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
                
                if hovering && !isResizing {
                    NSCursor.resizeLeftRight.set()
                } else if !hovering && !isResizing {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard browserManager.isSidebarVisible else { return }
                        
                        if !isResizing {
                            startingWidth = browserManager.sidebarWidth
                            isResizing = true
                            NSCursor.resizeLeftRight.set() // Ensure cursor stays consistent during drag
                        }
                        
                        let newWidth = startingWidth + value.translation.width
                        let clampedWidth = max(100, min(300, newWidth))
                        
                        // Use withAnimation(nil) to disable implicit animations during resize
                        withAnimation(nil) {
                            browserManager.updateSidebarWidth(clampedWidth)
                        }
                    }
                    .onEnded { _ in
                        isResizing = false
                        if isHovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
            )
    }
}
