//
//  PopupUIDelegate.swift
//  Nook
//
//  UI delegate for extension popup webviews.
//  Includes clipboard bridge for extensions that use web Clipboard APIs.
//

import AppKit
import os
import WebKit

// MARK: - Popup Clipboard Handler

/// Bridges JavaScript clipboard operations to the native NSPasteboard.
/// Handles extensions that use navigator.clipboard or document.execCommand('copy')
/// instead of native messaging. (Safari-style extensions like Bitwarden use native
/// messaging, which is handled in ExtensionManager+Delegate.swift.)
@available(macOS 15.4, *)
class PopupClipboardHandler: NSObject, WKScriptMessageHandler {
    static let handlerName = "nookClipboard"

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let text = message.body as? String, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// JS polyfill that overrides clipboard APIs to use the native bridge.
    /// Covers extensions that use web APIs instead of native messaging.
    static let polyfillSource = """
    (function() {
        if (window.__nookClipboardInstalled) return;
        window.__nookClipboardInstalled = true;

        var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName);
        if (!bridge) return;

        function nookCopy(text) {
            try { bridge.postMessage(text); return true; } catch(e) { return false; }
        }

        // Override navigator.clipboard.writeText
        if (navigator.clipboard) {
            var _origWrite = navigator.clipboard.writeText;
            navigator.clipboard.writeText = function(text) {
                return nookCopy(text) ? Promise.resolve()
                    : (_origWrite ? _origWrite.call(navigator.clipboard, text) : Promise.reject());
            };
        }

        // Override document.execCommand('copy') — check both selection and active textarea/input
        var _origExec = document.execCommand.bind(document);
        document.execCommand = function(cmd) {
            if (cmd === 'copy' || cmd === 'cut') {
                var text = '';
                var sel = window.getSelection();
                if (sel && sel.toString()) {
                    text = sel.toString();
                } else if (document.activeElement) {
                    var el = document.activeElement;
                    if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                        text = el.value.substring(el.selectionStart, el.selectionEnd) || el.value;
                    }
                }
                if (text && nookCopy(text)) return true;
            }
            return _origExec.apply(document, arguments);
        };

        // Capture-phase copy event listener as fallback
        document.addEventListener('copy', function(e) {
            var text = '';
            if (document.activeElement) {
                var el = document.activeElement;
                if ((el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') && el.value) {
                    text = el.value.substring(el.selectionStart, el.selectionEnd) || el.value;
                }
            }
            if (!text) {
                var sel = window.getSelection();
                if (sel) text = sel.toString();
            }
            if (text) nookCopy(text);
        }, true);
    })();
    """

    /// Install the clipboard bridge on a popup webview.
    static func install(on webView: WKWebView, retainedBy manager: ExtensionManager) {
        let handler = manager.popupClipboardHandler ?? PopupClipboardHandler()
        manager.popupClipboardHandler = handler

        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: handlerName)
        ucc.add(handler, name: handlerName)

        // Inject polyfill after page loads (evaluateJavaScript for current load)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak webView] in
            webView?.evaluateJavaScript(polyfillSource, completionHandler: nil)
        }
    }
}

// MARK: - Popup UI Delegate

@available(macOS 15.4, *)
class PopupUIDelegate: NSObject, WKUIDelegate {
    weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    #if os(macOS)
    func webView(_ webView: WKWebView, contextMenu: NSMenu) -> NSMenu {
        let reloadItem = NSMenuItem(
            title: "Reload Extension Popup",
            action: #selector(reloadPopup),
            keyEquivalent: "r"
        )
        reloadItem.target = self

        let menu = NSMenu()
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        for item in contextMenu.items {
            menu.addItem(item.copy() as! NSMenuItem)
        }
        return menu
    }
    #endif

    @objc private func reloadPopup() {
        webView?.reload()
    }
}
