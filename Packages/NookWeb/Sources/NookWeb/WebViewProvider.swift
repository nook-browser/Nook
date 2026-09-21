// Licensed under GPL-3.0. See LICENSE.
//
//  WebViewProvider.swift
//  NookWeb
//
//  The web view pool, as PageSession and TabsController see it. The app implements this
//  over WebViewCoordinator, which clones a page's view into every window showing it.
//

import WebKit

/// A web view that belongs to a `PageSession`. The app's concrete subclass (`FocusableWKWebView`
/// on macOS) carries the platform's focus, context menu and download behaviour.
@MainActor
public protocol SessionWebView: AnyObject {
    var owningSession: PageSession? { get set }
    var contextMenuBridge: WebContextMenuBridge? { get set }
    func contextMenuPayloadDidUpdate(_ payload: WebContextMenuPayload?)
}

@MainActor
public protocol WebViewProvider: AnyObject {
    /// A new view of the app's session web view class.
    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView

    /// The view a window displays for an item: the primary one or that window's clone.
    func webView(for itemID: UUID, in windowID: UUID) -> WKWebView?

    /// Every view showing the item, across windows.
    func allWebViews(for itemID: UUID) -> [WKWebView]

    /// Drops every pooled view of the session; called when its page unloads.
    func releaseWebViews(for session: PageSession)

    /// Takes one view out of whatever container holds it; called when a clone is cleaned up.
    func removeFromContainers(_ webView: WKWebView)
}
