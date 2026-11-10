// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc App/Window/EscapeKey.swift scripts/tests/EscapeKeyCheck.swift -o /tmp/x && /tmp/x
//
//  An Escape a web page leaves alone must reach EscapeKey.onEscape in a routed window and in
//  no other, and must not leave full screen in a routed one. The windows sit off screen; full
//  screen is faked through the two things AppKit's doCommandBySelector: reads.

import AppKit
import WebKit

final class Probe: NSWindow {
    var seen = 0
    var exits = 0
    var fakeFullScreen = false
    // A subclass override runs first and calls into the patched NSWindow method.
    override func cancelOperation(_ sender: Any?) { seen += 1; super.cancelOperation(sender) }
    override var styleMask: NSWindow.StyleMask {
        get { fakeFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
    @objc func _fullScreenTileFillsScreen() -> Bool { fakeFullScreen }
    @objc(exitFullScreenMode:) func recordExit(_ sender: Any?) { exits += 1 }
}

@main
struct EscapeKeyCheck {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var escapes: [NSWindow] = []
        EscapeKey.onEscape = { escapes.append($0) }

        func window() -> (Probe, WKWebView) {
            let w = Probe(contentRect: NSRect(x: -6000, y: -6000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            w.contentView = web
            web.loadHTMLString("<body>page", baseURL: nil)
            w.orderBack(nil)
            return (w, web)
        }
        let (routed, routedWeb) = window()
        let (plain, plainWeb) = window()
        let (full, fullWeb) = window()
        let (plainFull, plainFullWeb) = window()
        EscapeKey.route(in: routed)
        EscapeKey.route(in: full)
        full.fakeFullScreen = true
        plainFull.fakeFullScreen = true

        func press(in w: NSWindow, _ web: WKWebView) {
            w.makeFirstResponder(web)
            w.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                         isARepeat: false, keyCode: 53)!)
        }
        // WebKit sends a fresh view's first Escape up twice, so count against what each window saw.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { press(in: routed, routedWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { press(in: plain, plainWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { press(in: full, fullWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { press(in: plainFull, plainFullWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            guard routed.seen > 0, plain.seen > 0 else {
                fatalError("the web view no longer forwards an unhandled Escape to the window: \(routed.seen), \(plain.seen)")
            }
            guard plainFull.exits > 0 else {
                fatalError("the fake no longer reaches AppKit's full-screen exit, so the full-screen case proves nothing")
            }
            guard full.exits == 0 else { fatalError("a routed window left full screen on Escape") }
            let fromRouted = escapes.filter { $0 === routed }.count, fromFull = escapes.filter { $0 === full }.count
            guard fromRouted == routed.seen, fromFull > 0, fromRouted + fromFull == escapes.count else {
                fatalError("expected \(routed.seen) from the routed window and some from full screen, got \(fromRouted), \(fromFull) of \(escapes.count)")
            }
            print("EscapeKey ok: routed windows hand over Escape and stay in full screen")
            exit(0)
        }
        app.run()
    }
}
