// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatWebNavigation.swift
//  Nook
//
//  The two `chrome.webNavigation` events WebKit never fires: a page that changes its address
//  without loading a document. Foundation and WebKit only.
//

import Foundation
import WebKit

@MainActor
final class ExtensionCompatWebNavigation: ExtensionCompatAPI {
    let name = "webNavigation"
    let permission: String? = "webNavigation"
    private weak var bridge: ExtensionCompatBridge?

    init(bridge: ExtensionCompatBridge) { self.bridge = bridge }

    /// WebKit answers the namespace's functions itself. Nook only adds events.
    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        reply(.failure(ExtensionCompatError("webNavigation.\(method) is not available")))
    }

    /// Chrome's rule: a change of fragment alone is `onReferenceFragmentUpdated`, anything else
    /// the page did to its address is `onHistoryStateUpdated`.
    static func event(from old: URL, to new: URL) -> String? {
        guard old.absoluteString != new.absoluteString else { return nil }
        func bare(_ url: URL) -> String { url.absoluteString.components(separatedBy: "#")[0] }
        return bare(old) == bare(new) ? "webNavigation.onReferenceFragmentUpdated" : "webNavigation.onHistoryStateUpdated"
    }

    /// The main frame of `tab` went from `old` to `new` without a load. Told to each extension
    /// that asked for `webNavigation`, listens, and may see that address in that tab.
    func sameDocumentNavigation(from old: URL, to new: URL, in tab: any WKWebExtensionTab, isPrivate: Bool,
                                contexts: some Sequence<WKWebExtensionContext>) {
        guard let bridge, let event = Self.event(from: old, to: new) else { return }
        var details: [String: Any] = [
            "url": new.absoluteString, "frameId": 0, "parentFrameId": -1, "processId": -1,
            "timeStamp": (Date().timeIntervalSince1970 * 1000).rounded(), "transitionType": "link",
            "transitionQualifiers": [String](), "frameType": "outermost_frame", "documentLifecycle": "active",
        ]
        for context in contexts where bridge.isListening(context, for: event) {
            guard ExtensionCompatBridge.declares("webNavigation", in: context),
                  !isPrivate || context.hasAccessToPrivateData, context.hasAccess(to: new, in: tab) else { continue }
            // The shim puts the tab's id in place of `tabIndex`: WebKit does not tell the app its ids.
            details["tabIndex"] = tab.indexInWindow?(for: context) ?? 0
            bridge.emit(event, [details], to: context)
        }
    }
}
