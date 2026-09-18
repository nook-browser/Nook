// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  WKUserScript+NookOwned.swift
//  Nook
//
//  WKUserContentController has no remove-one API, so changing a single user
//  script means removeAllUserScripts() followed by re-adding the survivors.
//  The controller is shared with WKWebExtensionController, which injects its
//  own content scripts into it and is not told when we clear them.
//
//  Re-adding a script we did not add therefore duplicates it: our copy plus the
//  one the extension controller re-injects on the next navigation. Measured at
//  8 extension scripts becoming 32, 128 and 512 over three blocker toggles,
//  until WebKit's own Vector<WebUserScriptData> overflowed and killed the app
//  while building the parameters for a new web process.
//
//  So: re-add only what we own, and let the extension controller look after its
//  own scripts.
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import WebKit

extension WKUserScript {
    /// Every user script Nook injects begins with a `// Nook …` comment.
    /// Anything else in the controller belongs to WebKit or to an extension.
    public static let nookOwnedPrefix = "// Nook"

    public var isNookOwned: Bool { source.hasPrefix(Self.nookOwnedPrefix) }
}

extension Array where Element == WKUserScript {
    /// The subset safe to re-add after `removeAllUserScripts()`.
    public var nookOwned: [WKUserScript] { filter(\.isNookOwned) }
}
