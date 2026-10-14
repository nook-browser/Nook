// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+DevTools.swift
//  Nook
//
//  Developer Mode on a page: the capture handler on each of its views, and the evaluate field.
//

import Foundation
import WebKit

extension PageSession {
    var developerModeOn: Bool { controller?.settings.developerModeEnabled == true }

    /// Every view showing this page: the primary plus window clones.
    private var allViews: [WKWebView] {
        var views = controller?.webViews?.allWebViews(for: itemID) ?? []
        if let primary = primaryWebView, !views.contains(where: { $0 === primary }) { views.append(primary) }
        return views
    }

    /// Developer Mode changed: script and handler on or off for every view, capture made or dropped.
    func setDeveloperMode(_ on: Bool) {
        for view in allViews {
            DevCaptureScript.setInstalled(on, in: view.configuration.userContentController)
            on ? attachDevCaptureHandler(to: view) : detachDevCaptureHandler(from: view)
        }
        if on, devCapture == nil, primaryWebView != nil { devCapture = DevCapture() }
        if !on { devCapture = nil }
    }

    func attachDevCaptureHandler(to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DevCaptureScript.handlerName)
        controller.add(self, name: DevCaptureScript.handlerName)
        controller.removeScriptMessageHandler(forName: DevPickerScript.handlerName, contentWorld: DevPickerScript.world)
        controller.add(self, contentWorld: DevPickerScript.world, name: DevPickerScript.handlerName)
        if devCapture == nil { devCapture = DevCapture() }
    }

    func detachDevCaptureHandler(from webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DevCaptureScript.handlerName)
        controller.removeScriptMessageHandler(forName: DevPickerScript.handlerName, contentWorld: DevPickerScript.world)
    }

    /// Starts the element picker. Installs it first, for a page loaded before Developer Mode was on.
    public func startDevPicker() {
        guard developerModeOn, let webView = primaryWebView else { return }
        webView.evaluateJavaScript(DevPickerScript.source + "\nwindow.__nookDevPicker.start();",
                                   in: nil, in: DevPickerScript.world)
    }

    /// Outlines the element at `selector` for a moment, from the picker's world.
    public func devHighlight(_ selector: String) {
        guard developerModeOn, let webView = primaryWebView, !selector.isEmpty else { return }
        webView.callAsyncJavaScript(
            DevPickerScript.source + "\nreturn window.__nookDevPicker.flash(selector);",
            arguments: ["selector": selector], in: nil, in: DevPickerScript.world)
    }

    /// Accessibility outline of the element at `selector` (the body when empty), one line per role.
    public func devSnapshot(_ selector: String, maxDepth: Int, maxNodes: Int) async throws -> String? {
        guard developerModeOn, let webView = primaryWebView else { return nil }
        let result = try await webView.callAsyncJavaScript(
            DevPickerScript.source + "\nreturn window.__nookDevPicker.snapshot(selector, maxDepth, maxNodes);",
            arguments: ["selector": selector, "maxDepth": maxDepth, "maxNodes": maxNodes],
            in: nil, contentWorld: DevPickerScript.world)
        return result as? String
    }

    /// The picker posts from its isolated world, main frame only; the page cannot reach this.
    func receiveDevPick(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, var element = DevPickedElement(message: message.body),
              let webView = primaryWebView else { return }
        if element.source?.isEmpty == true { element.source = nil }
        Task { @MainActor in
            let hints = try? await webView.callAsyncJavaScript(
                DevPickerScript.hintsSource, arguments: ["selector": element.selector], in: nil, contentWorld: .page)
            element.apply(hints: hints)
            self.controller?.onDevPick?(self, element)
        }
    }

    /// Errors and failed requests the handoff carries alongside an element.
    public var devHandoffContext: (errors: [DevConsoleEntry], failed: [DevNetworkEntry]) {
        guard let capture = devCapture else { return ([], []) }
        return (capture.console.items.filter(\.isError),
                capture.network.items.filter { $0.state == .failed || ($0.status ?? 0) >= 400 })
    }

    func receiveDevCapture(_ message: WKScriptMessage) {
        let frame = message.frameInfo.isMainFrame ? nil : message.frameInfo.request.url?.absoluteString
        devCapture?.ingest(message.body, frameURL: frame)
    }

    /// Runs the Console's evaluate field in the page world and logs input and result.
    public func devEvaluate(_ code: String) async {
        guard let webView = primaryWebView, let capture = devCapture else { return }
        capture.appendLocal(level: "input", code)
        do {
            let value = try await webView.evaluateJavaScript(code)
            capture.appendLocal(level: "result", Self.describe(value))
        } catch {
            let info = (error as NSError).userInfo
            let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            capture.appendLocal(level: "error", message)
        }
    }

    static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "undefined" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: value)
    }
}

extension TabsController {
    /// Developer Mode changed: the shared configuration carries the capture script for new views,
    /// and every live page picks it up on its next load.
    public func setDeveloperMode(_ on: Bool) {
        DevCaptureScript.setInstalled(on, in: BrowserConfiguration.shared.webViewConfiguration.userContentController)
        for session in sessions { session.setDeveloperMode(on) }
    }
}

// MARK: - Content rule list actions

extension PageSession {
    /// WebKit SPI on WKNavigationDelegatePrivate: one call per action a compiled rule list took.
    /// The identifier is a chunk of every list merged, so it does not name the list.
    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func devContentRuleList(_ webView: WKWebView, identifier: String, performedAction action: NSObject, url: URL) {
        guard let capture = devCapture else { return }
        func flag(_ key: String) -> Bool {
            action.responds(to: NSSelectorFromString(key)) && (action.value(forKey: key) as? Bool) == true
        }
        let kind: DevBlockEntry.Action
        if flag("blockedLoad") { kind = .blocked }
        else if flag("madeHTTPS") { kind = .madeHTTPS }
        else if flag("redirected") { kind = .redirected }
        else if flag("blockedCookies") { kind = .cookiesBlocked }
        else { return }
        capture.recordBlock(DevBlockEntry(action: kind, url: url.absoluteString))
    }
}

extension PageSession {
    /// The page's WebContent process, through the `_webProcessIdentifier` SPI; 0 when there is none.
    public var webProcessID: Int32 {
        let selector = NSSelectorFromString("_webProcessIdentifier")
        guard let webView = primaryWebView, webView.responds(to: selector) else { return 0 }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
        return unsafeBitCast(webView.method(for: selector), to: Getter.self)(webView, selector)
    }
}
