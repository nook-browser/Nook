// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserWindowState+macOS.swift
//  Nook
//
//  The AppKit half of BrowserWindowState: typed accessors over the shared class's storage.
//

import AppKit
import NookWeb

extension NSWindow: WindowHandle {
    public var frameString: String? { NSStringFromRect(frame) }

    public func applyFrame(_ rectString: String) {
        let rect = NSRectFromString(rectString)
        guard rect.width > 0, rect.height > 0 else { return }
        // Two hops: the window restores its autosaved frame asynchronously after its own setup,
        // and would otherwise overwrite this one.
        DispatchQueue.main.async {
            DispatchQueue.main.async { [weak self] in
                self?.setFrame(rect, display: true)
            }
        }
    }

    public func bringToFront() { makeKeyAndOrderFront(nil) }
}

extension BrowserWindowState {
    /// Reference to the actual NSWindow for this window state
    var window: NSWindow? {
        get { windowHandle as? NSWindow }
        set { windowHandle = newValue }
    }

    var extensionLibraryPanelController: ExtensionLibraryPanelController? {
        get { extensionLibraryPanelStorage as? ExtensionLibraryPanelController }
        set { extensionLibraryPanelStorage = newValue }
    }

    var sidebarPiPController: SidebarPiPController? {
        get { sidebarPiPStorage as? SidebarPiPController }
        set { sidebarPiPStorage = newValue }
    }

    /// Reference to this window's CommandPalette for global shortcuts
    var commandPalette: CommandPalette? {
        get { commandPaletteStorage as? CommandPalette }
        set { commandPaletteStorage = newValue }
    }

    /// Shortcut conflict info for this window's toast
    var shortcutConflictInfo: ShortcutConflictInfo? {
        get { shortcutConflictStorage as? ShortcutConflictInfo }
        set { shortcutConflictStorage = newValue }
    }
}
