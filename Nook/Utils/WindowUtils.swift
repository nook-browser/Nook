import AppKit
import Foundation
//
//  WindowUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//
import SwiftUI

func zoomCurrentWindow() {
    if let window = NSApp.keyWindow {
        window.zoom(nil)
    }
}

extension View {
    public func backgroundDraggable() -> some View {
        modifier(BackgroundDraggableModifier(gesture: WindowDragGesture()))
    }

    public func backgroundDraggable<G: Gesture>(gesture: G) -> some View {
        modifier(BackgroundDraggableModifier(gesture: gesture))
    }

    public func conditionalWindowDrag() -> some View {
        modifier(ConditionalWindowDragModifier())
    }
}

private struct BackgroundDraggableModifier<G: Gesture>: ViewModifier {
    let gesture: G

    func body(content: Content) -> some View {
        content
            .gesture(
                gesture
            )
    }
}

private struct ConditionalWindowDragModifier: ViewModifier {
    @StateObject private var dragLockManager = DragLockManager.shared

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        // Only allow window dragging if no active drag of any type
                        if dragLockManager.canStartAnyDrag() {
                            let sessionID = UUID().uuidString
                            if dragLockManager.startDrag(ownerID: sessionID) {
                                if let window = NSApp.keyWindow {
                                    window.performDrag(with: NSApp.currentEvent!)
                                }
                            }
                        } else {
                            print("🚫 [ConditionalWindowDrag] Blocked - \(dragLockManager.debugInfo)")
                        }
                    }
                    .onEnded { value in
                        dragLockManager.forceReleaseAll()
                    }
            )
    }
}

struct WindowDragGesture: Gesture {
    var body: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // Check global drag lock directly from shared instance
                let dragLockManager = DragLockManager.shared

                if dragLockManager.canStartAnyDrag() {
                    // Generate a session ID for this specific drag attempt
                    let sessionID = UUID().uuidString

                    if dragLockManager.startDrag(ownerID: sessionID) {
                        if let window = NSApp.keyWindow {
                            window.performDrag(with: NSApp.currentEvent!)
                        }
                    } else {
                        print("🚫 [WindowDragGesture] Failed to acquire universal drag lock")
                    }
                } else {
                    // Window drag is blocked by another active drag
                    print("🚫 [WindowDragGesture] Window drag blocked - \(dragLockManager.debugInfo)")
                }
            }
            .onEnded { value in
                // We can't reliably track session ID in a struct, so force release all locks
                DragLockManager.shared.forceReleaseAll()
            }
    }
}
