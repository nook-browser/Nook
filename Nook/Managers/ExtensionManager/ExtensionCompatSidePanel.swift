// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatSidePanel.swift
//  Nook
//
//  `chrome.sidePanel`. Nook has no side panel, so the panel page opens in a window of its own;
//  the options and the behaviour an extension sets are kept. Foundation and WebKit only.
//

import Foundation
import WebKit

@MainActor
final class ExtensionCompatSidePanel: ExtensionCompatAPI {
    let name = "sidePanel"
    let permission: String? = "sidePanel"

    /// A window showing a panel page: how to bring it forward and how to close it.
    struct Panel {
        var focus: () -> Void
        var close: () -> Void
    }
    /// Shows one of the extension's pages as its panel. `closed` is for the person closing it.
    var present: ((_ url: URL, _ context: WKWebExtensionContext, _ closed: @escaping () -> Void) -> Panel?)?

    struct Options: Equatable {
        var path: String?
        var enabled: Bool?
    }
    private struct State {
        var defaults = Options()
        var tabs: [Int: Options] = [:]
        var open: (url: URL, panel: Panel)?
    }
    private var states: [String: State] = [:]
    /// Extensions whose toolbar button opens the panel. An extension often sets this once, when it is installed.
    private let defaults: UserDefaults
    private static let behaviorKey = "ExtensionSidePanelOpensOnAction"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: - Rules

    /// What applies to a tab: its own options over the extension's, over the manifest's. As in
    /// Chrome, a tab given options of its own has a panel unless those say otherwise.
    static func effective(tab: Options?, defaults: Options, manifest: [String: Any]) -> (path: String?, enabled: Bool) {
        let declared = (manifest["side_panel"] as? [String: Any])?["default_path"] as? String
        return (tab?.path ?? defaults.path ?? declared, tab.map { $0.enabled ?? true } ?? defaults.enabled ?? true)
    }

    /// A panel is a page of the extension itself.
    static func panelURL(_ path: String, base: URL) -> URL? {
        guard let url = URL(string: path, relativeTo: base.appendingPathComponent(""))?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host else { return nil }
        return url
    }

    // MARK: - ExtensionCompatAPI

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        let id = context.uniqueIdentifier
        let details = arguments.first as? [String: Any] ?? [:]
        let tabID = (details["tabId"] as? NSNumber)?.intValue
        switch method {
        case "setOptions":
            var state = states[id] ?? State()
            var options = tabID.flatMap { state.tabs[$0] } ?? (tabID == nil ? state.defaults : Options())
            if let path = details["path"] as? String { options.path = path }
            if let enabled = details["enabled"] as? Bool { options.enabled = enabled }
            if let tabID { state.tabs[tabID] = options } else { state.defaults = options }
            states[id] = state
            // Chrome closes a panel that is switched off.
            if tabID == nil, options.enabled == false { close(id) }
            reply(.success(nil))
        case "getOptions":
            let state = states[id] ?? State()
            let now = Self.effective(tab: tabID.flatMap { state.tabs[$0] }, defaults: state.defaults, manifest: context.webExtension.manifest)
            var out: [String: Any] = ["enabled": now.enabled]
            out["path"] = now.path
            out["tabId"] = tabID
            reply(.success(out))
        case "setPanelBehavior":
            if let opens = details["openPanelOnActionClick"] as? Bool { setOpensOnActionClick(opens, for: id) }
            reply(.success(nil))
        case "getPanelBehavior":
            reply(.success(["openPanelOnActionClick": opensOnActionClick(context)]))
        case "open":
            open(context, tab: tabID).map { reply(.failure($0)) } ?? reply(.success(nil))
        case "close":
            close(id)
            reply(.success(nil))
        case "getLayout":
            reply(.success(["side": "right"]))
        default:
            reply(.failure(ExtensionCompatError("sidePanel.\(method) is not available")))
        }
    }

    func contextUnloaded(_ context: WKWebExtensionContext) {
        close(context.uniqueIdentifier)
        states[context.uniqueIdentifier] = nil
    }

    // MARK: - The panel

    /// Whether a click on the toolbar button should open the panel. The app asks when the button has no popup.
    func opensOnActionClick(_ context: WKWebExtensionContext) -> Bool {
        ExtensionCompatBridge.declares("sidePanel", in: context)
            && (defaults.dictionary(forKey: Self.behaviorKey)?[context.uniqueIdentifier] as? Bool) == true
    }

    private func setOpensOnActionClick(_ opens: Bool, for id: String) {
        var all = defaults.dictionary(forKey: Self.behaviorKey) ?? [:]
        all[id] = opens ? true : nil
        defaults.set(all, forKey: Self.behaviorKey)
    }

    /// The extension was removed: nothing of it is kept.
    func forget(_ id: String) { setOpensOnActionClick(false, for: id) }

    /// Opens the panel that applies to `tab`, or brings it forward. Returns why not.
    @discardableResult
    func open(_ context: WKWebExtensionContext, tab: Int? = nil) -> ExtensionCompatError? {
        let id = context.uniqueIdentifier
        let state = states[id] ?? State()
        let now = Self.effective(tab: tab.flatMap { state.tabs[$0] }, defaults: state.defaults, manifest: context.webExtension.manifest)
        guard now.enabled else { return ExtensionCompatError("The side panel is disabled.") }
        guard let path = now.path, let url = Self.panelURL(path, base: context.baseURL) else {
            return ExtensionCompatError("No side panel page is set.")
        }
        if let open = state.open, open.url == url {
            open.panel.focus()
            return nil
        }
        close(id)
        guard let panel = present?(url, context, { [weak self] in self?.states[id]?.open = nil }) else {
            return ExtensionCompatError("The side panel could not be opened.")
        }
        states[id, default: State()].open = (url, panel)
        return nil
    }

    private func close(_ id: String) {
        guard let open = states[id]?.open else { return }
        states[id]?.open = nil
        open.panel.close()
    }
}
