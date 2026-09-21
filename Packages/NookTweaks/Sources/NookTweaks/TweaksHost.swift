// Licensed under GPL-3.0. See LICENSE.
//
//  TweaksHost.swift
//  NookTweaks
//
//  Created by Claude on 17/09/2026.
//
//  The two seams the tweaks need from the app. Everything else in this package
//  is Foundation and WebKit, so it builds on iOS unchanged.
//

import Foundation
import WebKit

/// Air Traffic Control hands the app a matched rule and lets it do the window and space work.
/// `page` is a `PageSession` on the app side; this package never looks inside it.
@MainActor public protocol SiteRoutingHost: AnyObject {
    /// Open `url` as a new tab in `spaceID`, in the window showing `page`, or the active window
    /// when `page` is nil (external URLs). False when nothing was opened: a private or incognito
    /// window, no window at all, a space that is gone, or a window already showing that space.
    /// The open itself may be deferred: callers are WebKit policy callbacks.
    func route(url: URL, toSpace spaceID: UUID, from page: AnyObject?) -> Bool

    /// The spaces that exist now, used to drop rules whose target was merged away.
    func liveSpaceIDs() -> Set<UUID>
}

/// The download button on Instagram, Facebook, and VSCO saves through the app's download path.
/// `webView` is the `FocusableWKWebView` the message came from; the app downcasts it.
@MainActor public protocol MediaDownloading: AnyObject {
    func downloadImage(at url: URL, from webView: WKWebView)
}
