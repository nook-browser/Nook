import AppKit
import SwiftUI

struct DragWindowView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No update needed
    }
}

class DraggableNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        if let window = self.window {
            window.performDrag(with: event)
        }
    }
}
