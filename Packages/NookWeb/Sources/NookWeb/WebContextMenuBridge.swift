// Licensed under GPL-3.0. See LICENSE.
//
//  WebContextMenuBridge.swift
//  Nook
//
//  Created by Codex on 09/02/2025.
//

import NookBlocker
import NookSettings
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
public final class WebContextMenuBridge: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private weak var session: PageSession?
    private weak var userContentController: WKUserContentController?

    public init(session: PageSession?, configuration: WKWebViewConfiguration) {
        self.session = session
        let controller = configuration.userContentController
        self.userContentController = controller
        super.init()

        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
        controller.addUserScript(Self.script)
        controller.addScriptMessageHandler(self, contentWorld: Self.world, name: Self.gateName)
        if session?.controller?.settings.linkPreviews == true { controller.addUserScript(Self.previewUserScript) }
        Self.live.add(self)
        Self.observeSetting()
    }

    // MARK: - Setting changes

    private static let live = NSHashTable<WebContextMenuBridge>.weakObjects()
    private static var observing = false
    private static let previewMarker = "// Nook Link Preview"

    private static func observeSetting() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: NookSettingsService.linkPreviewsDidChange, object: nil, queue: .main) { note in
            let on = note.userInfo?["enabled"] as? Bool ?? false
            MainActor.assumeIsolated { syncPreviewScripts(on: on) }
        }
    }

    /// Runs once per toggle of the setting: adds the preview script to live controllers, or takes
    /// it out by keeping the other Nook-owned scripts (the pattern the tweaks use).
    private static func syncPreviewScripts(on: Bool) {
        var seen = Set<ObjectIdentifier>()
        for bridge in live.allObjects {
            guard let ucc = bridge.userContentController, seen.insert(ObjectIdentifier(ucc)).inserted else { continue }
            let all = ucc.userScripts
            guard all.contains(where: { $0.source.hasPrefix(previewMarker) }) != on else { continue }
            if on {
                ucc.addUserScript(previewUserScript)
            } else {
                let others = all.nookOwned.filter { !$0.source.hasPrefix(previewMarker) }
                ucc.removeAllUserScripts()
                others.forEach { ucc.addUserScript($0) }
            }
        }
    }

    /// Link Previews listen only on a page that asked and was told yes: the setting is on and
    /// the page is neither private nor the Agent's. Checked again for every message received.
    private var previewsAllowed: Bool {
        guard let session else { return false }
        return session.controller?.settings.linkPreviews == true && !session.isPrivate && !session.isAgentPage
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                      replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        replyHandler(message.name == Self.gateName && message.frameInfo.isMainFrame && previewsAllowed, nil)
    }

    public func detach() {
        userContentController?.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.world)
        userContentController?.removeScriptMessageHandler(forName: Self.gateName, contentWorld: Self.world)
        userContentController = nil
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        guard let dictionary = message.body as? [String: Any] else {
            session?.deliverContextMenuPayload(nil)
            return
        }
        // A middle click or Command-click on a link rides the same bridge: WebKit does not
        // turn either into a new tab, so the page has to report it. Shift brings the tab forward.
        if let href = (dictionary["middleClickHref"] ?? dictionary["commandClickHref"]) as? String {
            if let url = URL(string: href) {
                session?.openInNewTab(url, foreground: dictionary["foreground"] as? Bool == true)
            }
            return
        }
        if dictionary.keys.contains("linkPreview") {
            guard message.frameInfo.isMainFrame, previewsAllowed || dictionary["linkPreview"] is NSNull else { return }
            session?.linkPreview = (dictionary["linkPreview"] as? String).flatMap(URL.init(string:)).map { url in
                let number = { (key: String) in (dictionary[key] as? NSNumber)?.doubleValue ?? 0 }
                return LinkPreviewTarget(url: url, rect: CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height")))
            }
            return
        }
        let payload = WebContextMenuPayload(dictionary: dictionary)
        session?.deliverContextMenuPayload(payload)
    }

    private static let handlerName = "contextMenuPayload"
    private static let gateName = "nookLinkPreviewGate"

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
                        window.webkit.messageHandlers.contextMenuPayload.postMessage({ middleClickHref: href, foreground: event.shiftKey });
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
                    window.webkit.messageHandlers.contextMenuPayload.postMessage({ commandClickHref: link.href, foreground: event.shiftKey });
                }
            } catch (error) {
                console.error('[Nook Context Menu] command click error', error);
            }
        }, false);

        console.log('[Nook Context Menu] Event listener registered');
    })();
    """
    // Link Previews: Shift pressed while the pointer rests on a link reports it with its box in
    // the viewport; leaving, scrolling, typing or switching away takes the preview down. Main
    // frame only, so the box is in the web view's own coordinates. Every listener ignores events
    // the page dispatched itself (isTrusted), and none is added until the app answers the gate.
    private static let previewSource = """
    // Nook Link Preview
    (function() {
        if (window.__nookLinkPreviewInstalled) { return; }
        window.__nookLinkPreviewInstalled = true;
        var handlers = window.webkit && window.webkit.messageHandlers;
        if (!handlers || !handlers.nookLinkPreviewGate || !handlers.contextMenuPayload) { return; }
        handlers.nookLinkPreviewGate.postMessage(1).then(function(allowed) {
            if (allowed === true) { install(handlers.contextMenuPayload); }
        }, function() {});

        function install(handler) {
            var previewLink = null;
            var pointerTarget = null;
            function webLink(target) {
                var link = target && target.closest ? target.closest('a[href]') : null;
                return link && /^https?:/i.test(link.href) ? link : null;
            }
            function reportPreview(link) {
                if (link === previewLink) { return; }
                previewLink = link;
                if (!link) { handler.postMessage({ linkPreview: null }); return; }
                var box = link.getBoundingClientRect();
                handler.postMessage({ linkPreview: link.href, x: box.left, y: box.top, width: box.width, height: box.height });
            }
            document.addEventListener('mouseover', function(event) {
                if (!event.isTrusted) { return; }
                pointerTarget = event.target;
                var link = webLink(event.target);
                if (event.shiftKey && link) { reportPreview(link); }
                else if (previewLink && link !== previewLink) { reportPreview(null); }
            }, true);
            window.addEventListener('keydown', function(event) {
                if (!event.isTrusted) { return; }
                if (event.key !== 'Shift') { reportPreview(null); return; }
                if (event.repeat) { return; }
                var active = document.activeElement;
                if (active && (active.isContentEditable || /^(input|textarea|select)$/i.test(active.tagName))) { return; }
                reportPreview(webLink(pointerTarget));
            }, true);
            window.addEventListener('scroll', function() { reportPreview(null); }, true);
            window.addEventListener('blur', function() { reportPreview(null); });
            document.addEventListener('mouseleave', function() { pointerTarget = null; reportPreview(null); });
        }
    })();
    """
    private static var previewUserScript: WKUserScript {
        WKUserScript(source: previewSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)
    }

    private static var script: WKUserScript {
        WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        )
    }
}

/// A link the person is holding Shift over, with its box in the page's viewport (CSS pixels).
public struct LinkPreviewTarget: Equatable, Sendable {
    public let url: URL
    public let rect: CGRect
}
