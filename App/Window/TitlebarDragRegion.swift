// Licensed under GPL-3.0. See LICENSE.
//
//  TitlebarDragRegion.swift
//  Nook
//
//  AppKit asks the window's content view which parts of the title band must not move the window.
//  SwiftUI's hosting view answers with an empty region and leaves out the AppKit views inside it,
//  so the whole 66pt band dragged the window, and selecting text near the top of a page moved it
//  instead. This makes SwiftUI's hosting view answer the way NSView does in a plain AppKit window:
//  any AppKit subview that cannot move the window, the web view, blocks the drag there.
//

import AppKit

enum TitlebarDragRegion {
    private static let selector = NSSelectorFromString("_regionForOpaqueDescendants:forMove:forUnderTitlebar:")
    private typealias RegionIMP = @convention(c) (AnyObject, Selector, NSRect, Bool, Bool) -> OpaquePointer?
    @MainActor private static var patched = Set<Method>()

    /// Once per hosting class: every SwiftUI root view type is its own class with its own copy of
    /// the method. A class that does not override NSView's answer, or whose method has another
    /// signature, is left alone, and the band drags the window as it did before.
    @MainActor static func letAppKitViewsBlockDrags(in window: NSWindow) {
        guard let root = window.contentView,
              let method = class_getInstanceMethod(type(of: root), selector),
              let appKitMethod = class_getInstanceMethod(NSView.self, selector),
              !patched.contains(method) else { return }
        let swiftUIImplementation = method_getImplementation(method)
        let appKitImplementation = method_getImplementation(appKitMethod)
        guard swiftUIImplementation != appKitImplementation,
              let encoding = method_getTypeEncoding(method), let appKitEncoding = method_getTypeEncoding(appKitMethod),
              strcmp(encoding, appKitEncoding) == 0 else { return }

        let swiftUI = unsafeBitCast(swiftUIImplementation, to: RegionIMP.self)
        let appKit = unsafeBitCast(appKitImplementation, to: RegionIMP.self)
        let selector = selector
        // Only the title band changes; SwiftUI keeps answering for the rest of the window.
        let answer: @convention(block) (AnyObject, NSRect, Bool, Bool) -> OpaquePointer? = { view, rect, forMove, underTitlebar in
            (underTitlebar ? appKit : swiftUI)(view, selector, rect, forMove, underTitlebar)
        }
        method_setImplementation(method, imp_implementationWithBlock(answer))
        patched.insert(method)
    }
}
