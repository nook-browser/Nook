import AppKit
import WebKit

final class PopupConsole: NSObject {
    static let shared = PopupConsole()

    private var window: NSWindow?
    private var textView: NSTextView?
    private var inputField: NSTextField?
    private weak var targetWebView: WKWebView?

    private override init() { super.init() }

    func attach(to webView: WKWebView) {
        targetWebView = webView
        
        // Add console message handler if not already present
        let consoleScript = """
        (function() {
            const originalLog = console.log;
            const originalError = console.error;
            const originalWarn = console.warn;
            
            function sendToNative(level, args) {
                try {
                    const message = args.map(arg => 
                        typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
                    ).join(' ');
                    window.webkit?.messageHandlers?.popupConsole?.postMessage({
                        level: level,
                        message: message,
                        timestamp: new Date().toISOString()
                    });
                } catch (e) {
                    // Fallback if webkit messaging isn't available
                }
            }
            
            console.log = function(...args) {
                originalLog.apply(console, args);
                sendToNative('log', args);
            };
            
            console.error = function(...args) {
                originalError.apply(console, args);
                sendToNative('error', args);
            };
            
            console.warn = function(...args) {
                originalWarn.apply(console, args);
                sendToNative('warn', args);
            };
            
            // Log initial extension API availability
            console.log('Extension APIs available:', {
                browser: typeof browser !== 'undefined',
                chrome: typeof chrome !== 'undefined',
                runtime: typeof (browser?.runtime || chrome?.runtime) !== 'undefined',
                storage: typeof (browser?.storage || chrome?.storage) !== 'undefined',
                tabs: typeof (browser?.tabs || chrome?.tabs) !== 'undefined'
            });
        })();
        """
        
        let script = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        log("[PopupConsole] Attached to WebView with console logging")
    }

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 720, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Popup Console"

            let content = NSView(frame: win.contentLayoutRect)
            content.autoresizingMask = [.width, .height]

            let scroll = NSScrollView(frame: NSRect(x: 0, y: 44, width: content.bounds.width, height: content.bounds.height - 44))
            scroll.autoresizingMask = [.width, .height]
            let tv = NSTextView(frame: scroll.bounds)
            tv.isEditable = false
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            scroll.documentView = tv

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: content.bounds.width - 80, height: 24))
            input.autoresizingMask = [.width, .maxYMargin]
            input.placeholderString = "Enter JS to evaluate in popup context"

            let runButton = NSButton(frame: NSRect(x: content.bounds.width - 75, y: 0, width: 75, height: 24))
            runButton.autoresizingMask = [.minXMargin, .maxYMargin]
            runButton.title = "Run"
            runButton.bezelStyle = .rounded
            runButton.target = self
            runButton.action = #selector(runJS)

            content.addSubview(scroll)
            content.addSubview(input)
            content.addSubview(runButton)

            win.contentView = content
            window = win
            textView = tv
            inputField = input
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func log(_ line: String) {
        guard let tv = textView else { return }
        let s = (tv.string.isEmpty ? "" : tv.string + "\n") + line
        tv.string = s
        tv.scrollToEndOfDocument(nil)
    }

    @objc private func runJS() {
        guard let js = inputField?.stringValue, js.isEmpty == false else { return }
        guard let webView = targetWebView else { log("[error] No popup webview attached"); return }
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                self?.log("[error] \(error.localizedDescription)")
            } else if let result = result {
                self?.log("[result] \(result)")
            } else {
                self?.log("[result] undefined")
            }
        }
    }
}

