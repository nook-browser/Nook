// Licensed under GPL-3.0. See LICENSE.
//
//  TabEventObserver.swift
//  NookWeb
//
//  Tab lifecycle as web extensions see it. The app forwards these to ExtensionManager;
//  a host without extensions leaves the observer nil.
//

import WebKit

@MainActor
public protocol TabEventObserver: AnyObject {
    func tabOpened(_ session: PageSession)
    func tabActivated(new session: PageSession, previous: PageSession?)
    func tabClosed(itemID: UUID)
    func tabMoved(itemID: UUID, from oldIndex: Int?, in oldWindow: BrowserWindowState?, pinnedChanged: Bool)
    func tabPropertiesChanged(_ session: PageSession, properties: WKWebExtension.TabChangedProperties)
    /// The page changed its own address without a load (history API, fragment). `session.url` is the new one.
    func sameDocumentNavigation(_ session: PageSession, from old: URL)

    /// Lets extensions with host permissions for this URL inject before the load starts.
    func grantAccess(to url: URL, for session: PageSession)
    /// MV3 service workers die after about five minutes idle; a page load wakes them.
    func wakeBackgroundWorkers(for session: PageSession)
    /// The controller of the page's extension set, nil when it gets no extensions.
    func nativeController(for session: PageSession) -> WKWebExtensionController?
    /// The configuration the page's web view copies, the one its controller was set up with.
    func baseConfiguration(for session: PageSession) -> WKWebViewConfiguration?
    /// Debug-build reporting of content script and messaging state.
    func diagnose(for webView: WKWebView, url: URL)
}
