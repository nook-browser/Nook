// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatNotifications.swift
//  Nook
//
//  `chrome.notifications`: an extension's notification in the Mac's notification center, and
//  what the person did with it told back to the extension. Foundation and WebKit only; the
//  center itself is the app's, behind `ExtensionCompatNotificationCenter`.
//

import Foundation
import WebKit

/// What Nook shows for one notification of an extension.
struct ExtensionCompatNotification: Equatable {
    /// The center's identifier: unique across extensions, and names the extension.
    var identifier: String
    var title: String
    /// The extension's name, so the person can tell who is speaking.
    var subtitle: String
    var body: String
    var buttons: [String]
    var silent: Bool
}

/// The Mac's notification center, as far as the API needs it.
@MainActor
protocol ExtensionCompatNotificationCenter: AnyObject {
    /// Whether the person lets Nook post notifications. `asking` puts the system's question when it is undecided.
    func allowed(asking: Bool, _ done: @escaping (Bool) -> Void)
    func show(_ notification: ExtensionCompatNotification, _ done: @escaping (Bool) -> Void)
    func remove(_ identifiers: [String])
    /// Identifiers still in the notification center.
    func delivered(_ done: @escaping ([String]) -> Void)
}

@MainActor
final class ExtensionCompatNotifications: ExtensionCompatAPI {
    let name = "notifications"
    let permission: String? = "notifications"
    private weak var bridge: ExtensionCompatBridge?
    var center: ExtensionCompatNotificationCenter?
    /// A loaded extension by context identifier, for a click that comes long after the call.
    var context: ((String) -> WKWebExtensionContext?)?

    enum Response: Equatable { case clicked, dismissed, button(Int) }

    /// Shown since launch, by center identifier: what `update` merges into, and in what order they came.
    private var shown: [String: (notification: ExtensionCompatNotification, order: Int)] = [:]
    private var posts = 0
    private var posted: [String: [Date]] = [:]
    /// Notifications one extension may have up at a time. One more takes the oldest down.
    var liveLimit = 30

    init(bridge: ExtensionCompatBridge) { self.bridge = bridge }

    // MARK: - Rules

    nonisolated static let prefix = "nook.ext"
    /// Posts an extension may make in a minute. Past it `create` and `update` fail.
    static let postsPerMinute = 20
    static let titleLimit = 256, bodyLimit = 2048, idLimit = 256

    /// An id is the extension's to choose, within a length Nook is willing to keep.
    static func accepts(id: String) -> Bool { id.utf16.count <= idLimit }

    /// The identifiers to take down so that `limit` stay up: the oldest.
    static func overflow(_ live: [(identifier: String, order: Int)], limit: Int) -> [String] {
        live.sorted { $0.order < $1.order }.dropLast(max(limit, 0)).map(\.identifier)
    }

    /// The extension's id goes last: it may hold any character, the separator included.
    static func identifier(_ id: String, in contextID: String) -> String { [prefix, contextID, id].joined(separator: "\n") }

    static func parse(_ identifier: String) -> (contextID: String, id: String)? {
        let parts = identifier.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix, !parts[1].isEmpty else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    /// Chrome's options as what the Mac can show, laid over `old` for an update. Nil when a new
    /// notification lacks a title or a message.
    static func notification(_ options: [String: Any], identifier: String, extensionName: String,
                             over old: ExtensionCompatNotification? = nil) -> ExtensionCompatNotification? {
        let title = options["title"] as? String ?? old?.title
        var body = options["message"] as? String
        guard let title, body != nil || old != nil else { return nil }
        if var text = body {
            if let context = options["contextMessage"] as? String, !context.isEmpty { text += "\n" + context }
            for item in options["items"] as? [[String: Any]] ?? [] {
                text += "\n" + [item["title"], item["message"]].compactMap { $0 as? String }.joined(separator: " ")
            }
            body = text
        }
        let buttons = (options["buttons"] as? [[String: Any]])?.compactMap { $0["title"] as? String }.prefix(2).map { String($0.prefix(titleLimit)) }
        return ExtensionCompatNotification(
            identifier: identifier, title: String(title.prefix(titleLimit)), subtitle: extensionName,
            body: String((body ?? old?.body ?? "").prefix(bodyLimit)), buttons: buttons ?? old?.buttons ?? [],
            silent: options["silent"] as? Bool ?? old?.silent ?? false)
    }

    /// Whether one more post fits in the minute before `now`.
    static func mayPost(after times: [Date], now: Date) -> Bool {
        times.filter { now.timeIntervalSince($0) < 60 }.count < postsPerMinute
    }

    // MARK: - ExtensionCompatAPI

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        guard let center else { return reply(.failure(ExtensionCompatError("notifications.\(method) is not available"))) }
        let contextID = context.uniqueIdentifier
        func full(_ id: String) -> String { Self.identifier(id, in: contextID) }
        switch method {
        case "create":
            // The id is optional and comes first.
            let given = arguments.first as? String
            guard let options = arguments.compactMap({ $0 as? [String: Any] }).first else {
                return reply(.failure(ExtensionCompatError("Notification options are required.")))
            }
            let id = given.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
            guard Self.accepts(id: id) else { return reply(.failure(ExtensionCompatError("The notification id is too long."))) }
            let name = context.webExtension.displayName ?? ""
            guard let notification = Self.notification(options, identifier: full(id), extensionName: name) else {
                return reply(.failure(ExtensionCompatError("Some of the required properties are missing: type, iconUrl, title and message.")))
            }
            post(notification, from: context, reply: reply) { id }
        case "update":
            guard let id = arguments.first as? String, let options = arguments.dropFirst().first as? [String: Any] else {
                return reply(.failure(ExtensionCompatError("A notification id and options are required.")))
            }
            guard let old = shown[full(id)]?.notification,
                  let notification = Self.notification(options, identifier: old.identifier, extensionName: old.subtitle, over: old)
            else { return reply(.success(false)) }
            post(notification, from: context, reply: reply) { true }
        case "clear":
            guard let id = arguments.first as? String else {
                return reply(.failure(ExtensionCompatError("A notification id is required.")))
            }
            let identifier = full(id)
            center.delivered { [weak self, weak context] delivered in
                guard let self else { return reply(.success(false)) }
                let existed = self.shown.removeValue(forKey: identifier) != nil || delivered.contains(identifier)
                center.remove([identifier])
                if existed, let context { self.bridge?.emit("notifications.onClosed", [id, false], to: context) }
                reply(.success(existed))
            }
        case "getAll":
            center.delivered { [weak self] delivered in
                let mine = (delivered + Array((self?.shown ?? [:]).keys)).compactMap(Self.parse).filter { $0.contextID == contextID }
                reply(.success(Dictionary(mine.map { ($0.id, true) }, uniquingKeysWith: { first, _ in first })))
            }
        case "getPermissionLevel":
            center.allowed(asking: false) { reply(.success($0 ? "granted" : "denied")) }
        default:
            reply(.failure(ExtensionCompatError("notifications.\(method) is not available")))
        }
    }

    private func post(_ notification: ExtensionCompatNotification, from context: WKWebExtensionContext,
                      reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void, answer: @escaping () -> Any) {
        let now = Date(), contextID = context.uniqueIdentifier
        guard Self.mayPost(after: posted[contextID] ?? [], now: now) else {
            return reply(.failure(ExtensionCompatError("Too many notifications.")))
        }
        posted[contextID] = (posted[contextID] ?? []).filter { now.timeIntervalSince($0) < 60 } + [now]
        center?.allowed(asking: true) { [weak self, weak context] allowed in
            // A person who said no is not an error to the extension, as in Chrome.
            guard allowed, let self, let center = self.center else { return reply(.success(answer())) }
            self.posts += 1
            self.shown[notification.identifier] = (notification, self.posts)
            // Past the limit the oldest come down, and the extension is told as for any it cleared.
            let mine = self.shown.filter { Self.parse($0.key)?.contextID == contextID }.map { ($0.key, $0.value.order) }
            let dropped = Self.overflow(mine, limit: self.liveLimit)
            dropped.forEach { self.shown[$0] = nil }
            if !dropped.isEmpty { center.remove(dropped) }
            for old in dropped.compactMap(Self.parse) {
                if let context { self.bridge?.emit("notifications.onClosed", [old.id, false], to: context) }
            }
            center.show(notification) { _ in reply(.success(answer())) }
        }
    }

    /// The extension is gone: so are its notifications, which nothing could answer a click on.
    func contextUnloaded(_ context: WKWebExtensionContext) {
        let contextID = context.uniqueIdentifier
        posted[contextID] = nil
        shown = shown.filter { Self.parse($0.key)?.contextID != contextID }
        center?.delivered { [weak self] delivered in
            self?.center?.remove(delivered.filter { Self.parse($0)?.contextID == contextID })
        }
    }

    /// The person clicked, dismissed or pressed a button of a notification.
    func responded(to identifier: String, _ response: Response) {
        guard let (contextID, id) = Self.parse(identifier), let context = context?(contextID),
              ExtensionCompatBridge.declares("notifications", in: context) else { return }
        // The Mac takes a notification away once it is answered.
        shown[identifier] = nil
        switch response {
        case .clicked: bridge?.emit("notifications.onClicked", [id], to: context)
        case .button(let index): bridge?.emit("notifications.onButtonClicked", [id, index], to: context)
        case .dismissed: bridge?.emit("notifications.onClosed", [id, true], to: context)
        }
    }
}
