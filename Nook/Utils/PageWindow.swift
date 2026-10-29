// Licensed under GPL-3.0. See LICENSE.
//
//  PageWindow.swift
//  Nook
//
//  Setup shared by every window that shows web pages.
//

import AppKit

extension NSWindow {
    /// Run once the window has its controller, which takes the next-responder slot.
    func setUpAsPageWindow() {
        // ARC owns these windows. AppKit's default release on close over-releases them and
        // crashes in the next autorelease pool drain.
        isReleasedWhenClosed = false

        guard objc_getAssociatedObject(self, &unhandledKeySinkKey) == nil else { return }
        let sink = UnhandledKeySink()
        sink.nextResponder = nextResponder
        nextResponder = sink
        objc_setAssociatedObject(self, &unhandledKeySinkKey, sink, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private var unhandledKeySinkKey: UInt8 = 0

/// Follows a page window in its responder chain: a key event nothing handled, typically one a
/// page ignored and WebKit passed back up, stops here instead of beeping.
private final class UnhandledKeySink: NSResponder {
    override func keyDown(with event: NSEvent) {}
}
