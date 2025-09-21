import AppKit
import SwiftUI

struct DragWindowView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = DraggableNSView()
        return view
    }

    func updateNSView(_: NSView, context _: Context) {
        // No update needed
    }
}

class DraggableNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        if let window = window {
            window.performDrag(with: event)
        }
    }
}
