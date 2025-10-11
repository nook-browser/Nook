//
//  SidebarResizeView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @StateObject private var dragLockManager = DragLockManager.shared
    @State private var dragSessionID: String = UUID().uuidString

    var body: some View {
        ZStack {
            // Hit detection area - 16pt wide spanning the sidebar boundary
            Rectangle()
                .fill(Color.clear)
                .frame(width: 3)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard windowState.isSidebarVisible else { return }

                    isHovering = hovering

                    if hovering && !isResizing {
                        NSCursor.resizeLeftRight.set()
                    } else if !hovering && !isResizing {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            guard windowState.isSidebarVisible else { return }

                            if !isResizing {
                                // Acquire drag lock before starting resize operation
                                guard dragLockManager.startDrag(ownerID: dragSessionID) else {
                                    print("🚫 [SidebarResizeView] Resize drag blocked - \(dragLockManager.debugInfo)")
                                    return
                                }

                                startingWidth = windowState.sidebarWidth
                                startingMouseX = value.startLocation.x
                                isResizing = true
                                NSCursor.resizeLeftRight.set()
                            }

                            // Use absolute mouse positions for true 1:1 tracking
                            let currentMouseX = value.location.x
                            let mouseMovement = browserManager.settingsManager.sidebarPosition == .left ? (currentMouseX - startingMouseX) : (startingMouseX - currentMouseX)
                            let newWidth = startingWidth + mouseMovement
                            let clampedWidth = max(170, min(400, newWidth))

                            browserManager.updateSidebarWidth(clampedWidth, for: windowState)
                        }
                        .onEnded { _ in
                            isResizing = false
                            browserManager.saveSidebarWidthToDefaults()

                            // Release drag lock when resize ends
                            dragLockManager.endDrag(ownerID: dragSessionID)

                            if isHovering {
                                NSCursor.resizeLeftRight.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                ).offset(x: browserManager.settingsManager.sidebarPosition == .left ? 0 : 2)

            // Visual feedback line - positioned within sidebar area
            if isHovering && !isResizing {
                RoundedRectangle(cornerRadius: 1) // Rounded ends (half of width)
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: browserManager.settingsManager.sidebarPosition == .left ? -6 : 6) // Positioned within sidebar area (14pts into sidebar - 1pt for centering)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
        }
        .frame(width: 3)
    }
}
