// Licensed under GPL-3.0. See LICENSE.
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

extension WKUserContentController {
    /// Clears the scripts and re-adds `scripts`, skipping any WebKit kept. removeAllUserScripts() leaves
    /// extension content scripts in place, and some begin with `// Nook`, so re-adding them stacked a copy per call.
    ///
    /// Sources are matched as NSStrings, by length and then contents. A `[String: Int]` keyed by
    /// source hashed every surviving extension script (bridged from WebKit, often hundreds of KB)
    /// through Unicode normalization one character at a time: seconds of main thread on each
    /// main-frame navigation, which stalled the swipe-back animation running on that thread.
    public func resetUserScripts(to scripts: [WKUserScript]) {
        removeAllUserScripts()
        var kept = userScripts.map { $0.source as NSString }
        for script in scripts {
            if let index = kept.firstIndex(where: { $0.isSameSource(as: script.source) }) {
                kept.remove(at: index)
            } else {
                addUserScript(script)
            }
        }
    }
}

extension NSString {
    /// Exact equality without Swift's normalizing compare: identity, then length, then contents.
    func isSameSource(as source: String) -> Bool {
        let other = source as NSString
        if self === other { return true }
        guard length == other.length else { return false }
        return isEqual(to: source)
    }
}
