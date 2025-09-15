import AppKit
import WebKit

// Simple subclass to ensure clicking a webview focuses its tab in the app state
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?

    override func mouseDown(with event: NSEvent) {
        owningTab?.activate()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        owningTab?.activate()
        super.rightMouseDown(with: event)
    }
}

