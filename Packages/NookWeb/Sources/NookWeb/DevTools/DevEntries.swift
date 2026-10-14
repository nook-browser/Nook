// Licensed under GPL-3.0. See LICENSE.
//
//  DevEntries.swift
//  Nook
//
//  What the capture script reports: console lines and network requests.
//

import Foundation

public enum DevPanelTab: String, CaseIterable, Sendable {
    case agent, console, network, blocker, perf
}

/// Something the content blocker did to this page: a load or its cookies blocked, a load moved
/// to HTTPS, or a navigation rewritten by `$removeparam` or `urlskip`.
public struct DevBlockEntry: DevLogEntry, Identifiable {
    public enum Action: String {
        case blocked, cookiesBlocked, madeHTTPS, redirected, strippedParams, skippedRedirect
    }

    public var id = 0
    public var seq = 0
    public var key: String? { action.rawValue + "|" + url }
    public var action: Action
    public var url: String
    /// Where a rewrite went.
    public var target: String?
    public var count = 1
    public var date = Date()

    public init(action: Action, url: String, target: String? = nil) {
        self.action = action
        self.url = url
        self.target = target
    }

    public var host: String { URL(string: url)?.host ?? url }
}

/// The engine's rules for the current page beyond the compiled rule lists.
public struct DevPageRules {
    public var procedural: [String]
    public var scriptletBytes: Int
    /// uBO scriptlet names found in the injected code, in order.
    public var scriptlets: [String]

    public init(procedural: [String], scriptletCode: String) {
        self.procedural = procedural
        self.scriptletBytes = scriptletCode.utf8.count
        self.scriptlets = Self.names(in: scriptletCode)
    }

    /// adblock-rust ends the code with one `try {` / `name(args)` / `} catch ( e ) { }` block per
    /// scriptlet (resource_storage.rs, get_scriptlet_resources). Template-style ones span lines and are skipped.
    static func names(in code: String) -> [String] {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        var seen: [String] = []
        for i in lines.indices.dropFirst().dropLast()
        where lines[i - 1] == "try {" && lines[i + 1] == "} catch ( e ) { }" {
            guard let paren = lines[i].firstIndex(of: "(") else { continue }
            let name = String(lines[i][..<paren])
            if !name.isEmpty, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }
}

public struct DevConsoleEntry: DevLogEntry, Identifiable {
    public var id = 0
    public var seq = 0
    public var key: String? { nil }
    /// log, info, warn, error, debug, uncaught, unhandledRejection, loadError, input, result
    public var level: String
    public var message: String
    public var location: String?
    public var frameURL: String?
    public var repeatCount = 1
    public var date = Date()

    public init(level: String, message: String, location: String? = nil, frameURL: String? = nil) {
        self.level = level
        self.message = message
        self.location = location
        self.frameURL = frameURL
    }

    public var isError: Bool {
        ["error", "uncaught", "unhandledRejection", "loadError"].contains(level)
    }

    public var isWarning: Bool { level == "warn" }
}

public struct DevNetworkEntry: DevLogEntry, Identifiable {
    public enum State: String { case pending, done, failed }

    public var id = 0
    public var seq = 0
    public var key: String?
    /// fetch, xhr, or a Resource Timing initiator type (script, img, link, css, ...).
    public var kind: String
    public var method: String
    public var url: String
    public var state: State = .pending
    public var status: Int?
    public var duration: Double?
    public var size: Int?
    public var requestHeaders: [String: String] = [:]
    public var responseHeaders: [String: String] = [:]
    public var requestBody: String?
    public var responseBody: String?
    public var error: String?
    public var frameURL: String?
    public var date = Date()

    public init(key: String?, kind: String, method: String, url: String) {
        self.key = key
        self.kind = kind
        self.method = method
        self.url = url
    }

    /// Only fetch and XHR go through the wrappers that see headers and bodies.
    public var hasDetail: Bool { kind == "fetch" || kind == "xhr" }

    public var name: String {
        guard let components = URLComponents(string: url) else { return url }
        let last = components.path.split(separator: "/").last.map(String.init) ?? ""
        return last.isEmpty ? (components.host ?? url) : last
    }

    public var curl: String {
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var parts = ["curl", quote(url)]
        if method != "GET" { parts += ["-X", method] }
        for (name, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            parts += ["-H", quote("\(name): \(value)")]
        }
        if let body = requestBody { parts += ["--data-raw", quote(body)] }
        return parts.joined(separator: " ")
    }
}
