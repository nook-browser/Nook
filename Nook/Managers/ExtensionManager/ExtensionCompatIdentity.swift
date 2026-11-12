// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatIdentity.swift
//  Nook
//
//  `chrome.identity.launchWebAuthFlow`: a sign-in page, in a window or unseen, until it redirects
//  to the extension's own `chromiumapp.org` address. Foundation and WebKit only; the window is the app's.
//

import Foundation
import WebKit

@MainActor
final class ExtensionCompatIdentity: ExtensionCompatAPI {
    let name = "identity"
    let permission: String? = "identity"

    /// Shows `url` in a sign-in window and returns how to close it. `redirected` is asked about each
    /// address before it loads and answers true to end the flow; `closed` is the person closing it.
    var present: ((_ url: URL, _ redirected: @escaping (URL) -> Bool, _ closed: @escaping () -> Void) -> (() -> Void)?)?
    /// A web view in no window, with the cookies of the space in front, for a flow without the person.
    var hiddenView: (() -> WKWebView?)?

    private final class Flow {
        let reply: (Result<Any?, ExtensionCompatError>) -> Void
        var close: (() -> Void)?
        init(reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) { self.reply = reply }
    }
    /// One flow per extension at a time, by context identifier.
    private var flows: [String: Flow] = [:]

    // MARK: - Rules

    /// Where a provider sends the person back to. It names one extension and resolves nowhere.
    static func redirectHost(for extensionID: String) -> String { extensionID.lowercased() + ".chromiumapp.org" }

    static func isRedirect(_ url: URL, for extensionID: String) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == redirectHost(for: extensionID)
    }

    /// A flow starts on the web, never at a file, a script or a page of the extension.
    static func mayStart(at url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host?.isEmpty == false else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// A page nobody sees loads over TLS only, which keeps it off routers and other plain-http hosts on the network.
    static func mayLoadUnseen(at url: URL) -> Bool {
        mayStart(at: url) && url.scheme?.lowercased() == "https"
    }

    /// How long a flow without the person may run: what the extension asks for, a minute at most.
    static func silentLimit(_ milliseconds: Any?) -> TimeInterval {
        guard let asked = (milliseconds as? NSNumber)?.doubleValue, asked > 0 else { return 60 }
        return min(asked / 1000, 60)
    }

    // MARK: - ExtensionCompatAPI

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        guard method == "launchWebAuthFlow" else {
            // getAuthToken and the account calls need Chrome's own Google sign-in.
            return reply(.failure(ExtensionCompatError("identity.\(method) is not available")))
        }
        let id = context.uniqueIdentifier
        guard let details = arguments.first as? [String: Any], let text = details["url"] as? String,
              let url = URL(string: text), Self.mayStart(at: url) else {
            return reply(.failure(ExtensionCompatError("Authorization page could not be loaded.")))
        }
        guard flows[id] == nil else {
            return reply(.failure(ExtensionCompatError("Another authorization flow is in progress.")))
        }
        // The provider may send the person straight back.
        if Self.isRedirect(url, for: id) { return reply(.success(url.absoluteString)) }
        let flow = Flow(reply: reply)
        flows[id] = flow
        // A window or page that outlives its flow must not end the next one.
        let ends: (Result<Any?, ExtensionCompatError>, Bool) -> Bool = { [weak self, weak flow] result, closing in
            guard let self, let flow, self.flows[id] === flow else { return false }
            self.finish(id, result, closing: closing)
            return true
        }
        if details["interactive"] as? Bool == true {
            flow.close = present?(url, { next in
                Self.isRedirect(next, for: id) && ends(.success(next.absoluteString), true)
            }, {
                _ = ends(.failure(ExtensionCompatError("The user did not approve access.")), false)
            })
        } else if Self.mayLoadUnseen(at: url), let view = hiddenView?() {
            // Unseen, as in Chrome: it succeeds only when the provider needs nothing from the person.
            let page = ExtensionCompatSilentPage(
                view: view, extensionID: id, waitsAfterLoad: details["abortOnLoadForNonInteractive"] as? Bool == false,
                limit: Self.silentLimit(details["timeoutMsForNonInteractive"]), mayLoad: Self.mayLoadUnseen) { _ = ends($0, true) }
            page.load(url)
            flow.close = { page.stop() }
        }
        if flow.close == nil { finish(id, .failure(ExtensionCompatError("Authorization page could not be loaded."))) }
    }

    func contextUnloaded(_ context: WKWebExtensionContext) {
        finish(context.uniqueIdentifier, .failure(ExtensionCompatError("The extension was unloaded.")))
    }

    private func finish(_ id: String, _ result: Result<Any?, ExtensionCompatError>, closing: Bool = true) {
        guard let flow = flows.removeValue(forKey: id) else { return }
        // Not inside the navigation decision that ended the flow: the window goes on the next turn.
        if closing, let close = flow.close { DispatchQueue.main.async { close() } }
        flow.reply(result)
    }
}

/// A sign-in page nobody sees. It ends at the extension's redirect address or fails, and since
/// there is nobody to ask it opens no window, dialog or prompt.
@MainActor
final class ExtensionCompatSilentPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let needsPerson = ExtensionCompatError("User interaction required.")
    private static let notLoaded = ExtensionCompatError("Authorization page could not be loaded.")

    private let view: WKWebView
    private let extensionID: String
    private let waitsAfterLoad: Bool
    private let mayLoad: (URL) -> Bool
    private var done: ((Result<Any?, ExtensionCompatError>) -> Void)?

    /// `waitsAfterLoad`: the provider redirects from script, so a loaded page is not yet a failure.
    /// `mayLoad` is asked about every address the page itself would go to.
    init(view: WKWebView, extensionID: String, waitsAfterLoad: Bool, limit: TimeInterval,
         mayLoad: @escaping (URL) -> Bool, done: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        self.view = view
        self.extensionID = extensionID
        self.waitsAfterLoad = waitsAfterLoad
        self.mayLoad = mayLoad
        self.done = done
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + limit) { [weak self] in self?.end(.failure(Self.needsPerson)) }
    }

    func load(_ url: URL) { view.load(URLRequest(url: url)) }

    func stop() {
        done = nil
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
    }

    private func end(_ result: Result<Any?, ExtensionCompatError>) {
        guard let done else { return }
        self.done = nil
        done(result)
    }

    private func failed(_ error: Error) {
        // A navigation the page replaced with another is not the end of the flow.
        if (error as NSError).code != NSURLErrorCancelled { end(.failure(Self.notLoaded)) }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url
        else { return decisionHandler(.allow) }
        if ExtensionCompatIdentity.isRedirect(url, for: extensionID) {
            decisionHandler(.cancel)
            return end(.success(url.absoluteString))
        }
        if mayLoad(url) { return decisionHandler(.allow) }
        // A hidden page opens no other app and reads no file. WebKit reports nothing for a refusal here.
        decisionHandler(.cancel)
        if navigationAction.targetFrame != nil { end(.failure(Self.notLoaded)) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { end(.failure(Self.notLoaded)) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // As in Chrome, a page that loads and stays is one that wants the person.
        if !waitsAfterLoad { end(.failure(Self.needsPerson)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    // MARK: - WKUIDelegate

    /// WebKit would ask the person itself. A page nobody can see gets no camera or microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}
