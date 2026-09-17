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

    /// Lets extensions with host permissions for this URL inject before the load starts.
    func grantAccess(to url: URL)
    /// MV3 service workers die after about five minutes idle; a page load wakes them.
    func wakeBackgroundWorkers()
    /// The controller new web view configurations are attached to, nil when extensions are off.
    var nativeController: WKWebExtensionController? { get }
    /// Debug-build reporting of content script and messaging state.
    func diagnose(for webView: WKWebView, url: URL)
}
