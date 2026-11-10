// Licensed under GPL-3.0. See LICENSE.
//
//  EscapeKey.swift
//  Nook
//
//  An Escape the page does not take comes back from WebKit as `doCommandBySelector:` with
//  `cancelOperation:`. In full screen `-[NSWindow doCommandBySelector:]` leaves full screen itself
//  for that selector and `cancel:`; out of it, the command reaches `cancelOperation:`, whose
//  `_cancelKey:` does AppKit's usual cancel. Browser windows hand that Escape to `onEscape` and, in
//  full screen, stop there, as Safari and Chrome do.
//

import AppKit

enum EscapeKey {
    /// The Escape nothing in `window` handled.
    @MainActor static var onEscape: ((NSWindow) -> Void)?

    /// Every other window keeps AppKit's behavior.
    nonisolated(unsafe) private static let browserWindows = NSHashTable<NSWindow>.weakObjects()
    @MainActor private static var patched = false

    /// If AppKit stops implementing either method on NSWindow, that one is left alone.
    @MainActor static func route(in window: NSWindow) {
        browserWindows.add(window)
        guard !patched else { return }
        patched = true

        let cancelOperation = #selector(NSResponder.cancelOperation(_:))
        if let method = class_getInstanceMethod(NSWindow.self, cancelOperation) {
            typealias CancelIMP = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
            let appKit = unsafeBitCast(method_getImplementation(method), to: CancelIMP.self)
            let routed: @convention(block) (AnyObject, AnyObject?) -> Void = { receiver, sender in
                guard let window = receiver as? NSWindow, browserWindows.contains(window) else {
                    return appKit(receiver, cancelOperation, sender)
                }
                MainActor.assumeIsolated { onEscape?(window) }
                if !window.styleMask.contains(.fullScreen) { appKit(receiver, cancelOperation, sender) }
            }
            method_setImplementation(method, imp_implementationWithBlock(routed))
        }

        let doCommand = #selector(NSResponder.doCommand(by:))
        let cancel = NSSelectorFromString("cancel:")
        if let method = class_getInstanceMethod(NSWindow.self, doCommand) {
            typealias CommandIMP = @convention(c) (AnyObject, Selector, Selector) -> Void
            let appKit = unsafeBitCast(method_getImplementation(method), to: CommandIMP.self)
            let routed: @convention(block) (AnyObject, Selector) -> Void = { receiver, command in
                guard command == cancelOperation || command == cancel,
                      let window = receiver as? NSWindow, browserWindows.contains(window),
                      window.styleMask.contains(.fullScreen) else {
                    return appKit(receiver, doCommand, command)
                }
                MainActor.assumeIsolated { onEscape?(window) }
            }
            method_setImplementation(method, imp_implementationWithBlock(routed))
        }
    }
}
