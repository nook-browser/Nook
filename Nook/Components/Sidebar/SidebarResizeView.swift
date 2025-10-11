//
//  SidebarResizeView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SidebarResizeView: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @StateObject private var dragLockManager = DragLockManager.shared
    @State private var dragSessionID: String = UUID().uuidString

    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 520

    private var sitsOnRight: Bool {
        browserManager.settingsManager.sidebarPosition == .right
    }

    private var indicatorOffset: CGFloat {
        sitsOnRight ? 3 : -3
    }

    private var hitAreaOffset: CGFloat {
        sitsOnRight ? 5 : -5
    }

    var body: some View {
        ZStack {
            if isHovering || isResizing {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: indicatorOffset)
                    .animation(.easeInOut(duration: 0.15), value: isResizing)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                    .padding(.vertical, 30)
            }

            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .padding(.vertical, 30)
                .offset(x: hitAreaOffset)
                .contentShape(.interaction, .rect)
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
                                guard dragLockManager.startDrag(ownerID: dragSessionID) else {
                                    print("🚫 [SidebarResizeView] Resize drag blocked - \(dragLockManager.debugInfo)")
                                    return
                                }

                                startingWidth = windowState.sidebarWidth
                                startingMouseX = value.startLocation.x
                                isResizing = true
                                NSCursor.resizeLeftRight.set()
                            }

                            let currentMouseX = value.location.x
                            let mouseMovement = sitsOnRight ? (startingMouseX - currentMouseX) : (currentMouseX - startingMouseX)
                            let newWidth = startingWidth + mouseMovement
                            let clampedWidth = max(minWidth, min(maxWidth, newWidth))

                            browserManager.updateSidebarWidth(clampedWidth, for: windowState)
                        }
                        .onEnded { _ in
                            isResizing = false
                            dragLockManager.endDrag(ownerID: dragSessionID)

                            if isHovering {
                                NSCursor.resizeLeftRight.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                )
        }
        .frame(width: 3)
    }
}
