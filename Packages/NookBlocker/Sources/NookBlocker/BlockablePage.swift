//
//  BlockablePage.swift
//  NookBlocker
//
//  The seam between the content blocker and whatever owns the pages it acts on.
//  The app conforms `PageSession` to `BlockablePage` and `BrowserManager` to
//  `ContentBlockerHost`; nothing in this package knows either type exists.
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import Foundation
import WebKit

/// One live page, as far as blocking is concerned.
@MainActor
public protocol BlockablePage: AnyObject {
    /// Identity of the tab or folder item the page belongs to, used to key the
    /// per-tab temporary disable.
    var itemID: UUID { get }
    /// True while the page is part of an OAuth flow, which is exempt from blocking.
    var isOAuthFlow: Bool { get }
    /// The page's web view, once it has one.
    var webView: WKWebView? { get }
}

/// What the blocker needs from the app that hosts it.
@MainActor
public protocol ContentBlockerHost: AnyObject {
    /// Every live page, for reconciling rule lists after a toggle or whitelist change.
    var blockablePages: [any BlockablePage] { get }
    /// The page that owns this web view, if any.
    func blockablePage(for webView: WKWebView) -> (any BlockablePage)?
    /// The user content controller shared by every web view configuration.
    var sharedUserContentController: WKUserContentController { get }
    /// Register a hook run against each freshly created user content controller.
    func onNewUserContentController(_ handler: @escaping @MainActor (WKUserContentController) -> Void)
}
