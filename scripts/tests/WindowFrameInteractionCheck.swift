// Licensed under GPL-3.0. See LICENSE.
// swiftc App/Window/WindowFrameInteraction.swift scripts/tests/WindowFrameInteractionCheck.swift -o /tmp/nook-frame-check && /tmp/nook-frame-check
import AppKit

@MainActor
private final class RecordingWindow: NSWindow {
    var zoomCalls = 0
    var minimizeCalls = 0
    var dragCalls = 0
    override func performZoom(_ sender: Any?) { zoomCalls += 1 }
    override func performMiniaturize(_ sender: Any?) { minimizeCalls += 1 }
    override func performDrag(with event: NSEvent) { dragCalls += 1 }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: flag, animate: false)
    }
}

@main
struct WindowFrameInteractionCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = RecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .resizable, .miniaturizable], backing: .buffered, defer: false)
        let region = WindowFrameInteractionView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = region
        func event(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        region.doubleClickActionProvider = { "Zoom" }
        region.mouseDown(with: event(.leftMouseDown, .zero))
        region.mouseUp(with: event(.leftMouseUp, .zero))
        precondition(window.zoomCalls == 0)
        region.mouseDown(with: event(.leftMouseDown, .zero, clicks: 2))
        region.mouseUp(with: event(.leftMouseUp, .zero, clicks: 2))
        precondition(window.zoomCalls == 1)
        window.zoomCalls = 0
        let otherWindow = RecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let wrongWindowUp = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: otherWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        region.mouseDown(with: event(.leftMouseDown, .zero, clicks: 2))
        region.mouseUp(with: wrongWindowUp)
        precondition(window.zoomCalls == 0 && otherWindow.zoomCalls == 0)
        if let screen = window.screen {
            let originalFrame = window.frame
            region.performDoubleClick(in: window, action: "Fill")
            precondition(window.frame == screen.visibleFrame)
            let anotherRegion = WindowFrameInteractionView()
            anotherRegion.performDoubleClick(in: window, action: "Fill")
            precondition(window.frame == originalFrame)
        }
        var acquired = 0
        var released = 0
        region.beginDrag = { acquired += 1; return "frame" }
        region.endDrag = { precondition($0 == "frame"); released += 1 }
        region.mouseDown(with: event(.leftMouseDown, .zero))
        region.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 1, y: 1)))
        precondition(window.dragCalls == 0 && acquired == 0)
        region.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 4, y: 0)))
        precondition(window.dragCalls == 1 && acquired == 1 && released == 1)
        region.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 8, y: 0)))
        precondition(window.dragCalls == 1)
        region.mouseUp(with: event(.leftMouseUp, NSPoint(x: 8, y: 0), clicks: 2))
        precondition(window.zoomCalls == 0)

        region.beginDrag = { nil }
        region.mouseDown(with: event(.leftMouseDown, .zero))
        region.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 5, y: 0)))
        precondition(window.dragCalls == 1)
        region.mouseUp(with: event(.leftMouseUp, NSPoint(x: 5, y: 0), clicks: 2))
        precondition(window.zoomCalls == 0)

        region.performDoubleClick(in: window, action: "Zoom")
        region.performDoubleClick(in: window, action: "Minimize")
        region.performDoubleClick(in: window, action: "None")
        region.performDoubleClick(in: window, action: "unknown")
        precondition(window.zoomCalls == 1 && window.minimizeCalls == 1)
        let name = "com.nook.frame-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("None", forKey: "AppleActionOnDoubleClick")
        precondition(WindowFrameInteractionView.doubleClickAction(defaults: defaults) == "None")
        defaults.set("Minimize", forKey: "AppleActionOnDoubleClick")
        precondition(WindowFrameInteractionView.doubleClickAction(defaults: defaults) == "Minimize")
        defaults.set("Fill", forKey: "AppleActionOnDoubleClick")
        precondition(WindowFrameInteractionView.doubleClickAction(defaults: defaults) == "Fill")
        print("Window frame interaction checks passed")
    }
}
