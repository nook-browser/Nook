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

public extension View {
    func backgroundDraggable() -> some View {
        modifier(BackgroundDraggableModifier(gesture: WindowDragGesture()))
    }

    func backgroundDraggable<G: Gesture>(gesture: G) -> some View {
        modifier(BackgroundDraggableModifier(gesture: gesture))
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
