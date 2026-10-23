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
    public func backgroundDraggable(onClick: (() -> Void)? = nil) -> some View {
        overlay(WindowFrameInteractionSurface(onClick: onClick))
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
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowFrameInteractionView {
        let view = WindowFrameInteractionView()
        view.beginDrag = {
            let owner = UUID().uuidString
            return DragLockManager.shared.startDrag(ownerID: owner) ? owner : nil
        }
        view.endDrag = { DragLockManager.shared.endDrag(ownerID: $0) }
        view.clickAction = onClick
        return view
    }

    func updateNSView(_ nsView: WindowFrameInteractionView, context: Context) {
        nsView.clickAction = onClick
    }
}
