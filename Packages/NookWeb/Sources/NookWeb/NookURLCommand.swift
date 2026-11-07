// Licensed under GPL-3.0. See LICENSE.
//
//  NookURLCommand.swift
//  Nook
//

import Foundation

/// A parsed nook:// link: open, search or space. Anything else is rejected.
public struct NookURLCommand: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case open(URL, reuse: Bool)
        case search(String)
        case switchSpace
    }

    public var action: Action
    /// A space name or UUID as typed; resolve it with `match`.
    public var space: String?
    /// Parameters that were present and not used.
    public var ignored: [String]

    private static let maxLength = 8192

    public static func parse(_ link: URL) -> NookURLCommand? {
        guard link.scheme?.lowercased() == "nook",
              let parts = URLComponents(url: link, resolvingAgainstBaseURL: false)
        else { return nil }
        var params: [String: String] = [:]
        for item in parts.queryItems ?? [] where params[item.name] == nil {
            params[item.name] = item.value ?? ""
        }
        func take(_ key: String) -> String? {
            guard let value = params.removeValue(forKey: key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.count > maxLength ? nil : trimmed
        }
        // A space key that is empty or oversized rejects the command rather than widening it.
        if params["space"] != nil, !hasSpace(params["space"]) { return nil }
        let action: Action
        var space: String?
        switch parts.host?.lowercased() {
        case "open":
            guard let raw = take("url"), let url = webURL(raw) else { return nil }
            action = .open(url, reuse: take("reuse") == "1")
            space = take("space")
        case "search":
            guard let q = take("q") else { return nil }
            action = .search(q)
            space = take("space")
        case "space":
            guard let name = take("name") else { return nil }
            action = .switchSpace
            space = name
        default:
            return nil
        }
        return NookURLCommand(action: action, space: space, ignored: params.keys.sorted())
    }

    private static func hasSpace(_ v: String?) -> Bool {
        let t = v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty && t.count <= maxLength
    }

    /// An http or https URL with a host; nothing else may be opened.
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// The default engine's results page for `query`, or nil when the template is not a web URL.
    public static func searchURL(for query: String, template: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=;"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return webURL(template.replacingOccurrences(of: "%@", with: encoded))
    }

    /// The space whose id or name (case-insensitive, exact) is `text`; the first one in order.
    public static func match(_ text: String, in spaces: [(id: UUID, name: String)]) -> UUID? {
        if let id = UUID(uuidString: text), spaces.contains(where: { $0.id == id }) { return id }
        return spaces.first { $0.name.caseInsensitiveCompare(text) == .orderedSame }?.id
    }

    /// Same page: scheme and host ignore case, the fragment and a trailing slash are dropped.
    public static func isSamePage(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> String? {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            parts.scheme = parts.scheme?.lowercased()
            parts.host = parts.host?.lowercased()
            parts.fragment = nil
            while parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
            return parts.string
        }
        guard let left = key(a), let right = key(b) else { return false }
        return left == right
    }
}
