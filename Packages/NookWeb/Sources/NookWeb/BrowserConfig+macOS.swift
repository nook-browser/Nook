// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserConfig+macOS.swift
//  NookWeb
//
//  AppKit's WKPreferences takes these through KVC; none has a public spelling there.
//

#if os(macOS)
import WebKit

extension BrowserConfiguration {
    static func applyPlatformPreferences(to config: WKWebViewConfiguration) {
        // No clipboard overrides here. Setting `javaScriptCanAccessClipboard` and `DOMPasteAllowed`
        // together makes WebKit's requestDOMPasteAccess return granted before it reaches the
        // user-gesture check, so any page could read the clipboard silently. Safari does not set
        // them either. Gesture-driven copy and paste go through WebKit's own path.
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        // The inspector itself is enabled per web view through isInspectable.
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
    }
}
#endif
