// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatOffscreen.swift
//  Nook
//
//  `chrome.offscreen`: one hidden page per extension, in a web view built from the extension's
//  own configuration and kept out of every window. Foundation and WebKit only.
//

import Foundation
import WebKit

@MainActor
final class ExtensionCompatOffscreen: NSObject, ExtensionCompatAPI, WKNavigationDelegate, WKUIDelegate {
    let name = "offscreen"
    let permission: String? = "offscreen"

    /// WebKit delivers runtime messages only to pages it knows: the background, popups and tabs.
    /// The document is a tab in no window, announced to its own extension and to no other.
    private final class HiddenTab: NSObject, WKWebExtensionTab {
        weak var view: WKWebView?
        let owner: String
        init(view: WKWebView, owner: String) { self.view = view; self.owner = owner }
        private func mine(_ context: WKWebExtensionContext) -> WKWebView? { context.uniqueIdentifier == owner ? view : nil }
        func webView(for context: WKWebExtensionContext) -> WKWebView? { mine(context) }
        func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { nil }
        func url(for context: WKWebExtensionContext) -> URL? { mine(context)?.url }
        func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { view?.isLoading == false }
        func isSelected(for context: WKWebExtensionContext) -> Bool { false }
    }

    @MainActor
    private final class Document {
        let view: WKWebView
        let url: URL
        let tab: HiddenTab
        weak var context: WKWebExtensionContext?
        let id = UUID().uuidString
        /// Answers `createDocument` once the page has loaded or failed.
        var loaded: ((Result<Any?, ExtensionCompatError>) -> Void)?
        init(view: WKWebView, url: URL, context: WKWebExtensionContext) {
            self.view = view
            self.url = url
            self.tab = HiddenTab(view: view, owner: context.uniqueIdentifier)
            self.context = context
        }
    }

    /// By context identifier. Chrome allows an extension one offscreen document at a time.
    private var documents: [String: Document] = [:]
    private static let loadTimeout: TimeInterval = 15

    /// The package's compatibility shim, which the document runs first as every other context does.
    var shimSource: ((WKWebExtensionContext) -> String?)?

    /// The live document's view, for the harness and for diagnostics.
    func view(for context: WKWebExtensionContext) -> WKWebView? { documents[context.uniqueIdentifier]?.view }

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        let id = context.uniqueIdentifier
        switch method {
        case "createDocument":
            create(arguments.first as? [String: Any] ?? [:], for: context, reply: reply)
        case "closeDocument":
            guard let document = documents.removeValue(forKey: id) else {
                return reply(.failure(ExtensionCompatError("No current offscreen document.")))
            }
            close(document)
            reply(.success(nil))
        case "hasDocument":
            reply(.success(documents[id] != nil))
        case "link":
            // A restarted worker looks for its document: the shim there opens its port again.
            guard let document = documents[id] else { return reply(.success(false)) }
            document.view.evaluateJavaScript("window.dispatchEvent(new Event('nook-relink'))", completionHandler: nil)
            reply(.success(true))
        case "document":
            // For runtime.getContexts, which the shim answers from this.
            reply(.success(documents[id].map { ["url": $0.url.absoluteString, "documentId": $0.id] }))
        default:
            reply(.failure(ExtensionCompatError("offscreen.\(method) is not available")))
        }
    }

    func contextUnloaded(_ context: WKWebExtensionContext) {
        documents.removeValue(forKey: context.uniqueIdentifier).map(close)
    }

    private func create(_ parameters: [String: Any], for context: WKWebExtensionContext,
                        reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        let id = context.uniqueIdentifier
        guard documents[id] == nil else {
            return reply(.failure(ExtensionCompatError("Only a single offscreen document may be created.")))
        }
        guard let reasons = parameters["reasons"] as? [Any], !reasons.isEmpty else {
            return reply(.failure(ExtensionCompatError("At least one reason must be given.")))
        }
        // Only a page of the extension itself: the document gets the extension's APIs.
        let base = context.baseURL
        guard let path = parameters["url"] as? String,
              let url = URL(string: path, relativeTo: base.appendingPathComponent(""))?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host
        else { return reply(.failure(ExtensionCompatError("Invalid URL."))) }
        guard let configuration = context.webViewConfiguration else {
            return reply(.failure(ExtensionCompatError("The extension is not loaded.")))
        }
        // Handlers are keyed by name, so the view gets a controller of its own, as an extension tab does.
        configuration.userContentController = WKUserContentController()
        if let shim = shimSource?(context) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "// Nook extension compatibility, offscreen document\nglobalThis.__nookOffscreen = true;\n" + shim,
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        // AUDIO_PLAYBACK is a reason to have one of these, and nobody can click in it.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isInspectable = true
        let document = Document(view: view, url: url, context: context)
        document.loaded = reply
        documents[id] = document
        // The context's own call, where the controller's would tell every extension of the tab.
        context.didOpenTab(document.tab)
        view.load(URLRequest(url: url))
        // WebKit drops some loads without a callback, and the caller must not wait forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout) { [weak self, weak document] in
            guard let self, let document, document.loaded != nil else { return }
            self.finish(document, .failure(ExtensionCompatError("The offscreen document did not load.")))
        }
    }

    private func close(_ document: Document) {
        document.loaded?(.failure(ExtensionCompatError("The offscreen document was closed.")))
        document.loaded = nil
        document.context?.didCloseTab(document.tab, windowIsClosing: false)
        document.view.navigationDelegate = nil
        document.view.uiDelegate = nil
        document.view.stopLoading()
    }

    /// Settles `createDocument`. A document that failed to load does not stay.
    private func finish(_ document: Document, _ result: Result<Any?, ExtensionCompatError>) {
        guard let reply = document.loaded else { return }
        document.loaded = nil
        if case .failure = result, let key = documents.first(where: { $0.value === document })?.key {
            documents.removeValue(forKey: key)
            close(document)
        }
        reply(result)
    }

    private func document(for webView: WKWebView) -> Document? {
        documents.values.first { $0.view === webView }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        document(for: webView).map { finish($0, .success(nil)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        document(for: webView).map { finish($0, .failure(ExtensionCompatError(error.localizedDescription))) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        document(for: webView).map { finish($0, .failure(ExtensionCompatError(error.localizedDescription))) }
    }

    /// The document stays the page it was created as: it never leaves the extension.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true, let document = document(for: webView),
              let url = navigationAction.request.url
        else { return decisionHandler(.allow) }
        decisionHandler(url.scheme == document.url.scheme && url.host == document.url.host ? .allow : .cancel)
    }

    // MARK: - WKUIDelegate

    /// A page nobody can see does not get the camera or the microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    /// `window.close()` in the document closes it, as in Chrome.
    func webViewDidClose(_ webView: WKWebView) {
        guard let key = documents.first(where: { $0.value.view === webView })?.key,
              let document = documents.removeValue(forKey: key) else { return }
        close(document)
    }
}
