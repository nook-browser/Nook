import SwiftUI
import AppKit

// Presents content in an NSPopover with .applicationDefined behavior
// so it doesn't auto-close when Web Inspector is open.
struct PersistentPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var contentSize: CGSize
    let preferredEdge: NSRectEdge
    let content: () -> Content

    init(isPresented: Binding<Bool>, contentSize: Binding<CGSize>, preferredEdge: NSRectEdge = .maxY, @ViewBuilder content: @escaping () -> Content) {
        self._isPresented = isPresented
        self._contentSize = contentSize
        self.preferredEdge = preferredEdge
        self.content = content
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator

        if isPresented {
            if coordinator.popover == nil || coordinator.popover?.isShown == false {
                let popover = NSPopover()
                popover.behavior = .applicationDefined // do not auto-close on focus changes
                let hosting = NSHostingController(rootView: content())
                coordinator.hostingController = hosting
                popover.contentViewController = hosting
                popover.contentSize = contentSize
                coordinator.popover = popover
                if let anchor = coordinator.anchorView {
                    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: preferredEdge)
                }
            } else {
                // Update content and size when already shown
                if let hosting = coordinator.hostingController {
                    // Avoid re-entrant layout by scheduling updates on next runloop
                    DispatchQueue.main.async {
                        hosting.rootView = content()
                    }
                }
                if coordinator.popover?.contentSize != contentSize {
                    let newSize = contentSize
                    DispatchQueue.main.async {
                        coordinator.popover?.contentSize = newSize
                    }
                }
            }
        } else {
            coordinator.popover?.performClose(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var popover: NSPopover?
        weak var anchorView: NSView?
        var hostingController: NSHostingController<Content>?
    }
}
