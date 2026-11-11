// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatBridge.swift
//  Nook
//
//  Extension APIs WebKit lacks, answered natively. The compatibility shim reaches this over
//  native messaging to Nook's own application id. Foundation and WebKit only, so the eval
//  harness compiles this file as it is.
//

import Foundation
import WebKit

/// A failure the calling extension sees as a rejected promise with this message.
struct ExtensionCompatError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// One API namespace Nook implements natively.
@MainActor
protocol ExtensionCompatAPI: AnyObject {
    /// The namespace, as in `chrome.<name>`.
    var name: String { get }
    /// The manifest permission an extension must declare to be answered. Nil when Chrome asks for none.
    var permission: String? { get }
    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void)
    /// The extension was disabled, removed or replaced: drop what was held for it.
    func contextUnloaded(_ context: WKWebExtensionContext)
    /// The set of events the extension listens for changed. Ask `ExtensionCompatBridge.isListening`.
    func listenersChanged(_ context: WKWebExtensionContext)
}

extension ExtensionCompatAPI {
    func contextUnloaded(_ context: WKWebExtensionContext) {}
    func listenersChanged(_ context: WKWebExtensionContext) {}
}

@MainActor
final class ExtensionCompatBridge {
    /// The native messaging application the shim talks to. No host process carries this name.
    static let applicationID = "com.gstudios.nook.compat"

    private var apis: [String: ExtensionCompatAPI] = [:]
    private final class Listener {
        let port: WKWebExtension.MessagePort
        var events: Set<String> = []
        /// The background's own port, as against a popup's or a page's.
        var isBackground = false
        init(_ port: WKWebExtension.MessagePort) { self.port = port }
    }
    /// Open event ports by context identifier: the background, and any page with a listener.
    private var listeners: [String: [Listener]] = [:]
    /// What each background listens for, kept while it sleeps so that an event can wake it.
    private var lazy: [String: Set<String>] = [:]
    private var queued: [String: [(event: String, message: [String: Any], at: Date)]] = [:]
    /// Contexts the app has described. One it has not is treated as holding the channel alone.
    private var known: Set<String> = []
    /// Contexts whose `nativeMessaging` permission is Nook's addition and not the extension's own.
    private var ownedChannels: Set<String> = []
    /// Of those, the ones the person later granted `nativeMessaging` at the extension's request.
    private var granted: Set<String> = []
    /// Asks the person to grant `nativeMessaging`. The app supplies it; without one the answer is no.
    var askForNativeMessaging: ((WKWebExtensionContext, @escaping (Bool) -> Void) -> Void)?
    /// Tells the app the grant changed, so it survives a relaunch.
    var nativeMessagingGrantChanged: ((WKWebExtensionContext, Bool) -> Void)?

    func register(_ api: ExtensionCompatAPI) { apis[api.name] = api }

    /// The manifest permissions the APIs here answer to. WebKit knows only some of them.
    var gatedPermissions: Set<String> { Set(apis.values.compactMap(\.permission)) }

    /// What the consent sheet lists for a package. WebKit leaves out the names it does not know,
    /// so the `bridged` ones are read from the manifest; `added` is what Nook put there itself.
    static func consentPermissions(of webExtension: WKWebExtension, hiding added: Set<String>, bridged: Set<String>) -> Set<String> {
        let declared = (webExtension.manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        return Set(webExtension.requestedPermissions.map(\.rawValue)).subtracting(added).union(bridged.intersection(declared))
    }

    // MARK: - Contexts

    /// `ownsChannel`: Nook added `nativeMessaging` to this package for the bridge alone.
    /// `nativeMessagingGranted`: the person granted it since, at the extension's own request.
    func contextLoaded(_ context: WKWebExtensionContext, ownsChannel: Bool, nativeMessagingGranted: Bool) {
        let id = context.uniqueIdentifier
        known.insert(id)
        if ownsChannel { ownedChannels.insert(id) } else { ownedChannels.remove(id) }
        if ownsChannel && nativeMessagingGranted { granted.insert(id) } else { granted.remove(id) }
    }

    func contextUnloaded(_ context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        apis.values.forEach { $0.contextUnloaded(context) }
        listeners.removeValue(forKey: id)?.forEach { $0.port.disconnect() }
        lazy[id] = nil
        queued[id] = nil
        known.remove(id)
        ownedChannels.remove(id)
        granted.remove(id)
    }

    /// True when the only native messaging this extension may do is with the bridge: its
    /// manifest never asked for `nativeMessaging`, so no host and no in-process handler answers it.
    func mayOnlyReachBridge(_ context: WKWebExtensionContext) -> Bool {
        let id = context.uniqueIdentifier
        return !known.contains(id) || (ownedChannels.contains(id) && !granted.contains(id))
    }

    /// Whether the package's manifest lists `permission`. Nook adds none of the names a bridge is gated on.
    static func declares(_ permission: String, in context: WKWebExtensionContext) -> Bool {
        (context.webExtension.manifest["permissions"] as? [Any])?.contains { $0 as? String == permission } == true
    }

    // MARK: - Requests

    /// A `sendNativeMessage` to `applicationID`: `{api, method, args}`, answered with `{result}` or `{error}`.
    func handle(_ message: Any, from context: WKWebExtensionContext, reply: @escaping (Any?, (any Error)?) -> Void) {
        func fail(_ text: String) { reply(["error": text], nil) }
        guard let request = message as? [String: Any], let name = request["api"] as? String,
              let method = request["method"] as? String
        else { return fail("Malformed request") }
        if name == "nook", method == "fail" {
            // A failure on its way to a callback: only WebKit can set `runtime.lastError`, and it does for this reply.
            let text = String(((request["args"] as? [Any])?.first as? String ?? "").prefix(500))
            return reply(nil, NSError(domain: "NookExtensionCompat", code: 1, userInfo: [NSLocalizedDescriptionKey: text]))
        }
        if name == "nook" {
            if let answer = channel(method, context, later: { reply(["result": $0], nil) }) { reply(["result": answer], nil) }
            return
        }
        guard let api = apis[name] else { return fail("\(name) is not available") }
        // The extension's own manifest decides what it may call, as in Chrome.
        if let permission = api.permission, !Self.declares(permission, in: context) {
            return fail("The '\(permission)' permission is required to use \(name).\(method)")
        }
        api.call(method, request["args"] as? [Any] ?? [], from: context) { result in
            switch result {
            case .success(let value): reply(["result": value ?? NSNull()], nil)
            case .failure(let error): fail(error.message)
            }
        }
    }

    /// The shim's questions about `nativeMessaging` itself, which WebKit can no longer answer
    /// truthfully once Nook has added it. Returns the answer, or nil when `later` will carry it.
    private func channel(_ method: String, _ context: WKWebExtensionContext, later: @escaping (Bool) -> Void) -> Bool? {
        let id = context.uniqueIdentifier
        let isGranted = !mayOnlyReachBridge(context)
        switch method {
        case "nativeMessagingGranted":
            return isGranted
        case "requestNativeMessaging":
            // As in Chrome, only a permission the manifest lists as optional can be asked for.
            let optional = context.webExtension.manifest["optional_permissions"] as? [Any] ?? []
            guard !isGranted, optional.contains(where: { $0 as? String == "nativeMessaging" }),
                  let ask = askForNativeMessaging
            else { return isGranted }
            ask(context) { [weak self, weak context] yes in
                if yes, let self, let context {
                    self.granted.insert(id)
                    self.nativeMessagingGrantChanged?(context, true)
                }
                later(yes)
            }
            return nil
        case "removeNativeMessaging":
            guard ownedChannels.contains(id), granted.remove(id) != nil else { return false }
            nativeMessagingGrantChanged?(context, false)
            return true
        default:
            return false
        }
    }

    // MARK: - Events

    /// A `connectNative` to `applicationID`. The extension posts `{subscribe: [event names], lazy}`,
    /// `lazy` from a background that may be put to sleep; Nook posts `{event, args}`.
    func connect(_ port: WKWebExtension.MessagePort, for context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        let listener = Listener(port)
        listeners[id, default: []].append(listener)
        port.messageHandler = { [weak self, weak context, weak listener] message, _ in
            MainActor.assumeIsolated {
                guard let self, let context, let listener, let body = message as? [String: Any],
                      let names = body["subscribe"] as? [String] else { return }
                listener.events = Set(names)
                listener.isBackground = body["lazy"] as? Bool == true
                if listener.isBackground { self.lazy[id] = listener.events }
                self.apis.values.forEach { $0.listenersChanged(context) }
                self.flush(id, to: listener)
            }
        }
        port.disconnectHandler = { [weak self, weak context, weak listener] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.listeners[id]?.removeAll { $0 === listener }
                if let context { self.apis.values.forEach { $0.listenersChanged(context) } }
            }
        }
    }

    /// True while a page of the extension listens, or its background did when it last ran.
    func isListening(_ context: WKWebExtensionContext, for event: String) -> Bool {
        let id = context.uniqueIdentifier
        return lazy[id]?.contains(event) == true || listeners[id]?.contains { $0.events.contains(event) } == true
    }

    /// Delivers `event` to every part of the extension that listens for it. A sleeping
    /// background is woken, and the event waits for its port for a short while.
    func emit(_ event: String, _ arguments: [Any], to context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        let message: [String: Any] = ["event": event, "args": arguments]
        let open = (listeners[id] ?? []).filter { !$0.port.isDisconnected && $0.events.contains(event) }
        open.forEach { $0.port.sendMessage(message) { _ in } }
        guard Self.mustWake(backgroundListens: lazy[id]?.contains(event) == true,
                            reachedBackground: open.contains { $0.isBackground }) else { return }
        queued[id, default: []].append((event, message, Date()))
        if queued[id]!.count > Self.queueLimit { queued[id]!.removeFirst() }
        context.loadBackgroundContent { _ in }
    }

    /// An open popup must not stand in for a sleeping background: the worker is what locks a vault.
    static func mustWake(backgroundListens: Bool, reachedBackground: Bool) -> Bool {
        backgroundListens && !reachedBackground
    }

    private static let queueLimit = 50
    private static let queueLifetime: TimeInterval = 30

    /// Hands the background's port, once it says what it listens for, the events that waited for it.
    private func flush(_ id: String, to listener: Listener) {
        guard listener.isBackground, let waiting = queued[id], !waiting.isEmpty else { return }
        queued[id] = waiting.filter { !listener.events.contains($0.event) }
        for entry in waiting where listener.events.contains(entry.event) && Date().timeIntervalSince(entry.at) < Self.queueLifetime {
            listener.port.sendMessage(entry.message) { _ in }
        }
    }
}
