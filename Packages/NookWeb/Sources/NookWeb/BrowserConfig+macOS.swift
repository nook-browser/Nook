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
        setPrivatePreference("allowsPictureInPictureMediaPlayback", in: config.preferences)
        setPrivatePreference("allowsInlineMediaPlayback", in: config.preferences)
        // The inspector itself is enabled per web view through isInspectable.
        #if DEBUG
        setPrivatePreference("developerExtrasEnabled", in: config.preferences)
        #endif
        hidePDFHUD(in: config.preferences)
    }

    /// KVC on a key WebKit has dropped throws NSUndefinedKeyException and would take down every
    /// new web view, so a missing private setter is skipped.
    private static func setPrivatePreference(_ key: String, in preferences: WKPreferences) {
        let setter = "_set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        guard preferences.responds(to: NSSelectorFromString(setter)) else { return }
        preferences.setValue(true, forKey: key)
    }

    /// WebKit's PDF viewer draws its own zoom/save bar over the page. Nook draws its own controls
    /// in its place (`PDFControlsView`), so WebKit's is switched off. `PDFPluginHUDEnabled` is an
    /// embedder-facing feature flag, set through the private feature API; a WebKit without the
    /// flag or the API leaves its own bar in place, and both bars would show.
    static func hidePDFHUD(in preferences: WKPreferences) {
        let list = NSSelectorFromString("_features")
        let set = NSSelectorFromString("_setEnabled:forFeature:")
        guard (WKPreferences.self as AnyObject).responds(to: list), preferences.responds(to: set) else { return }
        typealias Features = @convention(c) (AnyClass, Selector) -> NSArray
        let features = unsafeBitCast((WKPreferences.self as AnyObject).method(for: list), to: Features.self)(WKPreferences.self, list)
        guard let hud = features.first(where: { ($0 as AnyObject).value(forKey: "key") as? String == "PDFPluginHUDEnabled" }) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, false, hud as AnyObject)
    }
}
#endif
