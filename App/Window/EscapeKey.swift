// Licensed under GPL-3.0. See LICENSE.
//
//  EscapeKey.swift
//  Nook
//
//  An Escape the page does not take ends at `-[NSWindow cancelOperation:]`, whose `_cancelKey:`
//  leaves full screen. A page counts as not taking it unless it calls preventDefault, so closing
//  a site's own popup also dropped a full-screen Nook to the desktop. Browser windows hand that
//  Escape to `onEscape` and, in full screen, stop there, as Safari and Chrome do.
//

import AppKit

enum EscapeKey {
    /// The Escape nothing in `window` handled.
    @MainActor static var onEscape: ((NSWindow) -> Void)?

    /// Every other window keeps AppKit's behavior.
    nonisolated(unsafe) private static let browserWindows = NSHashTable<NSWindow>.weakObjects()
    @MainActor private static var patched = false

    /// If AppKit stops implementing the method on NSWindow, nothing is patched and Escape
    /// behaves as it did.
    @MainActor static func route(in window: NSWindow) {
        browserWindows.add(window)
        let selector = #selector(NSResponder.cancelOperation(_:))
        guard !patched, let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
        patched = true
        typealias CancelIMP = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let appKit = unsafeBitCast(method_getImplementation(method), to: CancelIMP.self)
        let routed: @convention(block) (AnyObject, AnyObject?) -> Void = { receiver, sender in
            guard let window = receiver as? NSWindow, browserWindows.contains(window) else {
                return appKit(receiver, selector, sender)
            }
            MainActor.assumeIsolated { onEscape?(window) }
            if !window.styleMask.contains(.fullScreen) { appKit(receiver, selector, sender) }
        }
        method_setImplementation(method, imp_implementationWithBlock(routed))
    }
}
