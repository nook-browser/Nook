import AppKit
import Foundation
//
//  WindowUtils.swift
//  Pulse
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
}

private struct BackgroundDraggableModifier<G: Gesture>: ViewModifier {
    @GestureState private var isDraggingWindow = false
    let gesture: G

    func body(content: Content) -> some View {
        content
            .gesture(
                gesture.updating($isDraggingWindow) { _, state, _ in
                    state = true
                }
            )
    }
}
