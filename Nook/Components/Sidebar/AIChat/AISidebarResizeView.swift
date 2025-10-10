//
//  AISidebarResizeView.swift
//  Nook
//
//  Resize handle for the AI assistant sidebar
//

import SwiftUI

struct AISidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @StateObject private var dragLockManager = DragLockManager.shared
    @State private var dragSessionID: String = UUID().uuidString

    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 520

    private var aiSitsOnRight: Bool {
        browserManager.settingsManager.sidebarPosition == .left
    }

    private var indicatorOffset: CGFloat {
        aiSitsOnRight ? -3 : 3
    }

    private var hitAreaOffset: CGFloat {
        aiSitsOnRight ? -5 : 5
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
                    guard windowState.isSidebarAIChatVisible else { return }

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
                            guard windowState.isSidebarAIChatVisible else { return }

                            if !isResizing {
                                guard dragLockManager.startDrag(ownerID: dragSessionID) else {
                                    print("🚫 [AISidebarResizeView] Resize drag blocked - \(dragLockManager.debugInfo)")
                                    return
                                }

                                startingWidth = windowState.aiSidebarWidth
                                startingMouseX = value.startLocation.x
                                isResizing = true
                                NSCursor.resizeLeftRight.set()
                            }

                            let currentMouseX = value.location.x
                            let mouseMovement = aiSitsOnRight ? (startingMouseX - currentMouseX) : (currentMouseX - startingMouseX)
                            let newWidth = startingWidth + mouseMovement
                            let clampedWidth = max(minWidth, min(maxWidth, newWidth))

                            windowState.aiSidebarWidth = clampedWidth
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
