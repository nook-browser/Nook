//
//  SidebarResizeView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI
import NookDesign
import NookWeb

struct SidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @StateObject private var dragLockManager = DragLockManager.shared
    @State private var dragSessionID: String = UUID().uuidString
    @State private var hoverTask: Task<Void, Never>?

    private let minWidth: CGFloat = 180
    private let maxWidth: CGFloat = 520
    private let defaultWidth: CGFloat = 250

    private var sitsOnRight: Bool {
        nookSettings.sidebarPosition == .right
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
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .offset(x: indicatorOffset)
                    .animation(NookDesign.Motion.quick, value: isResizing)
                    .animation(NookDesign.Motion.quick, value: isHovering)
                    .padding(.vertical, 30)
            }

            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .padding(.vertical, 30)
                .offset(x: hitAreaOffset)
                .contentShape(.interaction, .rect)
                .onTapGesture(count: 2) {
                    guard windowState.isSidebarVisible else { return }
                    withAnimation(NookDesign.Motion.spring) {
                        browserManager.updateSidebarWidth(defaultWidth, for: windowState)
                    }
                }
                .onHoverTracking { hovering in
                    guard windowState.isSidebarVisible else { return }

                    hoverTask?.cancel()

                    if hovering && !isResizing {
                        hoverTask = Task {
                            try? await Task.sleep(for: .seconds(0.1))
                            guard !Task.isCancelled else { return }
                            isHovering = true
                            NSCursor.resizeLeftRight.set()
                        }
                    } else {
                        isHovering = false
                        if !isResizing {
                            NSCursor.arrow.set()
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            guard windowState.isSidebarVisible else { return }

                            if !isResizing {
                                guard dragLockManager.startDrag(ownerID: dragSessionID) else {
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
