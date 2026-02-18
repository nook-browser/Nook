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

        debugLog("🔽 [WebContextMenuBridge] Initializing bridge for tab: \(tab.id)")
        controller.add(self, name: Self.handlerName)
        controller.addUserScript(Self.script)
        debugLog("🔽 [WebContextMenuBridge] Added message handler and user script")
    }

    func detach() {
        userContentController?.removeScriptMessageHandler(forName: Self.handlerName)
        userContentController = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        debugLog("🔽 [WebContextMenuBridge] Received message from JavaScript")
        guard let dictionary = message.body as? [String: Any] else {
            debugLog("🔽 [WebContextMenuBridge] Failed to cast message.body as dictionary")
            tab?.deliverContextMenuPayload(nil)
            return
        }
        debugLog("🔽 [WebContextMenuBridge] Dictionary: \(dictionary)")
        let payload = WebContextMenuPayload(dictionary: dictionary)
        debugLog("🔽 [WebContextMenuBridge] Created payload: \(String(describing: payload))")
        tab?.deliverContextMenuPayload(payload)
    }

    /// Logs debug messages only in DEBUG builds
    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private static let handlerName = "contextMenuPayload"
    private static let scriptSource: String = """
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
        console.log('[Nook Context Menu] Event listener registered');
    })();
    """
    private static var script: WKUserScript {
        WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
