// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc App/Window/EscapeKey.swift scripts/tests/EscapeKeyCheck.swift -o /tmp/x && /tmp/x
//
//  An Escape a web page leaves alone must reach EscapeKey.onEscape in a routed window and in
//  no other. The windows sit off screen; full screen itself needs a hand test.

import AppKit
import WebKit

final class Probe: NSWindow {
    var seen = 0
    // A subclass override runs first and calls into the patched NSWindow method.
    override func cancelOperation(_ sender: Any?) { seen += 1; super.cancelOperation(sender) }
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
        EscapeKey.route(in: routed)

        func press(in w: NSWindow, _ web: WKWebView) {
            w.makeFirstResponder(web)
            w.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                         isARepeat: false, keyCode: 53)!)
        }
        // WebKit sends a fresh view's first Escape up twice, so count against what each window saw.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { press(in: routed, routedWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { press(in: plain, plainWeb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard routed.seen > 0, plain.seen > 0 else {
                fatalError("the web view no longer forwards an unhandled Escape to the window: \(routed.seen), \(plain.seen)")
            }
            guard escapes.count == routed.seen, escapes.allSatisfy({ $0 === routed }) else {
                fatalError("expected \(routed.seen) from the routed window only, got \(escapes.count)")
            }
            print("EscapeKey ok: only the routed window handed over its Escape")
            exit(0)
        }
        app.run()
    }
}
