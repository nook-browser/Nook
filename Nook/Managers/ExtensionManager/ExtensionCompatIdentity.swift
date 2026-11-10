// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatIdentity.swift
//  Nook
//
//  `chrome.identity.launchWebAuthFlow`: a sign-in page in a window, until it redirects to the
//  extension's own `chromiumapp.org` address. Foundation and WebKit only; the window is the app's.
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

    private struct Flow {
        let reply: (Result<Any?, ExtensionCompatError>) -> Void
        var close: (() -> Void)?
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
        // ponytail: no silent flows. Chrome loads the page unseen with the person's cookies; here the extension asks again with a window.
        guard details["interactive"] as? Bool == true else {
            return reply(.failure(ExtensionCompatError("User interaction required.")))
        }
        guard flows[id] == nil else {
            return reply(.failure(ExtensionCompatError("Another authorization flow is in progress.")))
        }
        // The provider may send the person straight back.
        if Self.isRedirect(url, for: id) { return reply(.success(url.absoluteString)) }
        flows[id] = Flow(reply: reply, close: nil)
        let close = present?(url, { [weak self] next in
            guard let self, self.flows[id] != nil, Self.isRedirect(next, for: id) else { return false }
            self.finish(id, .success(next.absoluteString))
            return true
        }, { [weak self] in
            self?.finish(id, .failure(ExtensionCompatError("The user did not approve access.")), closing: false)
        })
        guard let close else { return finish(id, .failure(ExtensionCompatError("Authorization page could not be loaded."))) }
        flows[id]?.close = close
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
