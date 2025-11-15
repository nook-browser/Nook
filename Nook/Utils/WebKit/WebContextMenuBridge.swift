//
//  WebContextMenuBridge.swift
//  Nook
//
//  Created by Codex on 09/02/2025.
//

import WebKit

@MainActor
final class WebContextMenuBridge: NSObject, WKScriptMessageHandler {
    private weak var tab: Tab?
    private weak var userContentController: WKUserContentController?

    init(tab: Tab, configuration: WKWebViewConfiguration) {
        self.tab = tab
        let controller = configuration.userContentController
        self.userContentController = controller
        super.init()

        controller.add(self, name: Self.handlerName)
        controller.addUserScript(Self.script)
    }

    func detach() {
        userContentController?.removeScriptMessageHandler(forName: Self.handlerName)
        userContentController = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        guard let dictionary = message.body as? [String: Any] else {
            tab?.deliverContextMenuPayload(nil)
            return
        }
        let payload = WebContextMenuPayload(dictionary: dictionary)
        tab?.deliverContextMenuPayload(payload)
    }

    private static let handlerName = "contextMenuPayload"
    private static let script: WKUserScript = WKUserScript(
        source: WebContextMenuBridge.scriptSource,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private static let scriptSource: String = """
    (function() {
        if (window.__nookContextMenuBridgeInstalled) { return; }
        window.__nookContextMenuBridgeInstalled = true;

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

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenuPayload) {
                    window.webkit.messageHandlers.contextMenuPayload.postMessage(payload);
                }
            } catch (error) {
                console.error('Context menu payload error', error);
            }
        }

        document.addEventListener('contextmenu', capturePayload, true);
    })();
    """
}
