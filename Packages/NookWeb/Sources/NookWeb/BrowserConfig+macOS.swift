// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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
        // JavaScript clipboard access (navigator.clipboard, document.execCommand('copy')).
        // Required for third-party WKWebView apps; Safari enables this by default.
        config.preferences.setValue(true, forKey: "javaScriptCanAccessClipboard")
        config.preferences.setValue(true, forKey: "DOMPasteAllowed")
        config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        config.preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
        // The inspector itself is enabled per web view through isInspectable.
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
    }
}
#endif
