// Licensed under GPL-3.0. See LICENSE.
//
//  WebContextMenuBridge.swift
//  Nook
//
//  Created by Codex on 09/02/2025.
//

import WebKit

/// What the page reported under the cursor when the context menu opened.
public enum WebContextMenuPayload {
    case page(url: URL)
    case textSelection(text: String)
    case link(url: URL)
    case image(resource: String)
    case multiple([WebContextMenuPayload])
    case ignored

    public init?(dictionary: [String: Any]) {
        guard let rawInvocations = dictionary["invocations"] as? Int,
              let params = dictionary["parameters"] as? [String: Any]
        else {
            return nil
        }

        var payloads: [WebContextMenuPayload] = []
        let invocations = Invocation(rawValue: rawInvocations)

        if invocations.contains(.ignored) {
            self = .ignored
            return
        }

        if invocations.contains(.page),
           let href = dictionary["href"] as? String,
           let url = WebContextMenuPayload.makeURL(from: href) {
            payloads.append(.page(url: url))
        }

        if invocations.contains(.textSelection),
           let contents = params["contents"] as? String {
            payloads.append(.textSelection(text: contents))
        }

        if invocations.contains(.link),
           let href = params["href"] as? String,
           let url = WebContextMenuPayload.makeURL(from: href) {
            payloads.append(.link(url: url))
        }

        if invocations.contains(.image),
           let src = params["src"] as? String {
            payloads.append(.image(resource: src))
        }

        guard !payloads.isEmpty else { return nil }
        self = payloads.count == 1 ? payloads[0] : .multiple(payloads)
    }

    public var linkURL: URL? {
        switch self {
        case .link(let url):
            return url
        case .multiple(let payloads):
            return payloads.compactMap(\.linkURL).first
        default:
            return nil
        }
    }

    public var imageURL: URL? {
        switch self {
        case .image(let resource):
            return WebContextMenuPayload.makeURLAllowingData(from: resource)
        case .multiple(let payloads):
            return payloads.compactMap(\.imageURL).first
        default:
            return nil
        }
    }

    public var imageSourceString: String? {
        switch self {
        case .image(let resource):
            return resource
        case .multiple(let payloads):
            return payloads.compactMap(\.imageSourceString).first
        default:
            return nil
        }
    }

    public var textSelection: String? {
        switch self {
        case .textSelection(let text):
            return text
        case .multiple(let payloads):
            return payloads.compactMap(\.textSelection).first
        default:
            return nil
        }
    }

    public var pageURL: URL? {
        switch self {
        case .page(let url):
            return url
        case .multiple(let payloads):
            return payloads.compactMap(\.pageURL).first
        default:
            return nil
        }
    }

    public var shouldProvideCustomMenu: Bool {
        switch self {
        case .ignored:
            return false
        default:
            return true
        }
    }

    var containsImage: Bool {
        switch self {
        case .image:
            return true
        case .multiple(let payloads):
            return payloads.contains { $0.containsImage }
        default:
            return false
        }
    }

    private struct Invocation: OptionSet {
        let rawValue: Int
        static let page = Invocation(rawValue: 1 << 0)
        static let textSelection = Invocation(rawValue: 1 << 1)
        static let link = Invocation(rawValue: 1 << 2)
        static let image = Invocation(rawValue: 1 << 3)
        static let ignored = Invocation(rawValue: 1 << 4)
    }

    private static func makeURL(from string: String) -> URL? {
        if let url = URL(string: string) {
            return url
        }
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    private static func makeURLAllowingData(from string: String) -> URL? {
        if string.hasPrefix("data:") {
            return URL(string: string)
        }
        return makeURL(from: string)
    }
}


@MainActor
public final class WebContextMenuBridge: NSObject, WKScriptMessageHandler {
    private weak var session: PageSession?
    private weak var userContentController: WKUserContentController?

    public init(session: PageSession?, configuration: WKWebViewConfiguration) {
        self.session = session
        let controller = configuration.userContentController
        self.userContentController = controller
        super.init()

        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
        controller.addUserScript(Self.script)
    }

    public func detach() {
        userContentController?.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.world)
        userContentController = nil
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        guard let dictionary = message.body as? [String: Any] else {
            session?.deliverContextMenuPayload(nil)
            return
        }
        // A middle click or Command-click on a link rides the same bridge: WebKit does not
        // turn either into a new tab, so the page has to report it.
        if let href = (dictionary["middleClickHref"] ?? dictionary["commandClickHref"]) as? String {
            if let url = URL(string: href) {
                session?.openInNewTab(url)
            }
            return
        }
        let payload = WebContextMenuPayload(dictionary: dictionary)
        session?.deliverContextMenuPayload(payload)
    }

    private static let handlerName = "contextMenuPayload"

    /// The bridge runs in its own world so the page cannot reach the handler. Now that this
    /// handler can open a tab, leaving it in the page world would let any site call
    /// `postMessage({ middleClickHref })` in a loop and bury the user in tabs with no click
    /// ever happening. An isolated world sees the same DOM, which is all the script needs.
    private static let world = WKContentWorld.world(name: "NookContextMenuBridge")

    private static let scriptSource: String = """
    // Nook Context Menu Bridge
    (function() {
        if (window.__nookContextMenuBridgeInstalled) { return; }
        window.__nookContextMenuBridgeInstalled = true;
        console.log('[Nook Context Menu] Bridge script installed');

        const INVOCATIONS = {
            page: 1 << 0,
            textSelection: 1 << 1,
            link: 1 << 2,
            image: 1 << 3,
            ignored: 1 << 4
        };

        function sanitizeURL(value) {
            if (!value) { return null; }
            return value;
        }

        function capturePayload(event) {
            console.log('[Nook Context Menu] capturePayload called');
            try {
                var invocations = 0;
                var params = {};

                var selection = window.getSelection();
                if (selection && !selection.isCollapsed) {
                    invocations |= INVOCATIONS.textSelection;
                    params.contents = selection.toString().slice(0, 2000);
                }

                var link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
                if (link && link.href) {
                    invocations |= INVOCATIONS.link;
                    params.href = sanitizeURL(link.href);
                }

                var image = event.target;
                if (!image) {
                    invocations |= INVOCATIONS.page;
                } else {
                    if (!(image.tagName && image.tagName.toUpperCase() === 'IMG')) {
                        image = image.closest ? image.closest('img') : null;
                    }
                    if (image && (image.src || image.currentSrc)) {
                        invocations |= INVOCATIONS.image;
                        params.src = sanitizeURL(image.currentSrc || image.src || image.getAttribute('src'));
                    }
                }

                if (invocations === 0) {
                    invocations |= INVOCATIONS.page;
                    params.href = sanitizeURL(document.location.href);
                }

                const payload = {
                    invocations: invocations,
                    parameters: params,
                    href: sanitizeURL(document.location.href)
                };

                console.log('[Nook Context Menu] Payload prepared:', JSON.stringify(payload));
                
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenuPayload) {
                    console.log('[Nook Context Menu] Posting message to native');
                    window.webkit.messageHandlers.contextMenuPayload.postMessage(payload);
                } else {
                    console.error('[Nook Context Menu] messageHandler not available!');
                }
            } catch (error) {
                console.error('[Nook Context Menu] Context menu payload error', error);
            }
        }

        document.addEventListener('contextmenu', capturePayload, true);

        // Middle click on a link. WebKit does not deliver this as a navigation, so the
        // page reports the href and the app opens a background tab. auxclick is the event
        // for non-primary buttons; button 1 is the middle one.
        //
        // Deliberately on the bubble phase, and skipped once the page has called
        // preventDefault. That is the contract other browsers keep: a page that wants to
        // handle its own middle clicks cancels the event, and a single-page app that
        // answers with window.open would otherwise give us two tabs for one click.
        document.addEventListener('auxclick', function(event) {
            if (!event.isTrusted || event.button !== 1 || event.defaultPrevented) { return; }
            try {
                var link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
                if (!link || !link.href) { return; }
                var href = link.href;
                // Decide once the event has finished propagating. Listeners the page adds to
                // document or window after ours run after ours, so a page that cancels the
                // click and opens its own tab would otherwise leave the user with two.
                setTimeout(function() {
                    if (event.defaultPrevented) { return; }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenuPayload) {
                        window.webkit.messageHandlers.contextMenuPayload.postMessage({ middleClickHref: href });
                    }
                }, 0);
            } catch (error) {
                console.error('[Nook Context Menu] auxclick error', error);
            }
        }, false);

        // Command-click on a link opens it in a background tab. Only a real click counts:
        // isTrusted is false for anything the page dispatches itself. Listening on window,
        // bubble phase, puts this after the page's document listeners, so a page that
        // cancels the click keeps it. preventDefault stops the link loading in this tab
        // too, and has to happen now, so unlike middle click this cannot wait a tick.
        window.addEventListener('click', function(event) {
            if (!event.isTrusted || !event.metaKey || event.button !== 0 || event.defaultPrevented) { return; }
            try {
                var link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
                if (!link || !link.href) { return; }
                event.preventDefault();
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenuPayload) {
                    window.webkit.messageHandlers.contextMenuPayload.postMessage({ commandClickHref: link.href });
                }
            } catch (error) {
                console.error('[Nook Context Menu] command click error', error);
            }
        }, false);

        console.log('[Nook Context Menu] Event listener registered');
    })();
    """
    private static var script: WKUserScript {
        WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        )
    }
}
