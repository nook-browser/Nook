// Licensed under GPL-3.0. See LICENSE.
import AppKit
import Foundation
//
//  WindowUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//
import SwiftUI

extension View {
    public func backgroundDraggable() -> some View {
        overlay(WindowFrameInteractionSurface())
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
    func body(content: Content) -> some View {
        content.overlay(WindowFrameInteractionSurface())
    }
}

private struct WindowFrameInteractionSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowFrameInteractionView {
        let view = WindowFrameInteractionView()
        view.beginDrag = {
            let owner = UUID().uuidString
            return DragLockManager.shared.startDrag(ownerID: owner) ? owner : nil
        }
        view.endDrag = { DragLockManager.shared.endDrag(ownerID: $0) }
        return view
    }

    func updateNSView(_ nsView: WindowFrameInteractionView, context: Context) {}
}

/// Retained for callers supplying their own SwiftUI gesture. The built-in decorative chrome
/// uses WindowFrameInteractionView so clicks can retain native double-click behavior.
struct WindowDragGesture: Gesture {
    var body: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                guard let event = NSApp.currentEvent, event.type == .leftMouseDragged,
                      let window = event.window else { return }
                let owner = UUID().uuidString
                guard DragLockManager.shared.startDrag(ownerID: owner) else { return }
                defer { DragLockManager.shared.endDrag(ownerID: owner) }
                window.performDrag(with: event)
            }
    }
}
