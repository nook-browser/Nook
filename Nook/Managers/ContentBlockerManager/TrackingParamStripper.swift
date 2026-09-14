//
//  TrackingParamStripper.swift
//  Nook
//
//  Implements `$removeparam` for main-frame navigations. SafariConverterLib drops these rules
//  (WebKit content blockers cannot rewrite URLs), so they are parsed here from the raw filter
//  lines and applied in Tab.decidePolicyFor by restarting the navigation without the parameters.
//
//  Supported forms (uBO/AdGuard):
//    ||host^$removeparam=name           ||host/path$removeparam=/regex/
//    $removeparam=name                  (generic, any URL)
//    ||host^$removeparam                (remove every parameter)
//    ...,domain=a.com|~b.com  ...,doc / document / ~third-party (ignored; navigations only)
//    @@||host^$removeparam  /  @@||host^$removeparam=name   (exceptions)
//
//  ponytail: pattern matching is host-suffix plus substring, not full ABP pattern semantics.
//  Upgrade to adblock-rust's matcher if list authors start relying on wildcards here.
//

import Foundation

struct TrackingParamStripper {

    fileprivate struct Rule {
        enum Param { case all, name(String), regex(NSRegularExpression) }
        let host: String?          // from ||host^ ; nil = generic
        let pathHint: String?      // text after the host in the pattern, matched as substring of the URL
        let param: Param
        let permittedDomains: [String]
        let restrictedDomains: [String]
        let isException: Bool
    }

    fileprivate var hostRules: [String: [Rule]] = [:]   // keyed by registrable host in the pattern
    fileprivate var genericRules: [Rule] = []
    private(set) var ruleCount = 0

    init() {}

    init(rules lines: [String]) {
        for line in lines where line.contains("removeparam") {
            guard let rule = Self.parse(line) else { continue }
            ruleCount += 1
            if let host = rule.host { hostRules[host, default: []].append(rule) } else { genericRules.append(rule) }
        }
    }

    // MARK: - Apply

    /// URL without tracking parameters, or nil if nothing matched.
    func strip(_ url: URL) -> URL? {
        guard ruleCount > 0, let host = url.host?.lowercased(),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return nil }

        let urlString = url.absoluteString
        var candidates = genericRules
        var h = host
        while true {
            if let list = hostRules[h] { candidates.append(contentsOf: list) }
            guard let dot = h.firstIndex(of: "."), h[h.index(after: dot)...].contains(".") else { break }
            h = String(h[h.index(after: dot)...])
        }
        let applicable = candidates.filter { $0.matches(urlString: urlString, host: host) }
        guard applicable.contains(where: { !$0.isException }) else { return nil }

        let exceptions = applicable.filter { $0.isException }
        if exceptions.contains(where: { if case .all = $0.param { return true } else { return false } }) { return nil }
        let blocking = applicable.filter { !$0.isException }

        let kept = items.filter { item in
            let removed = blocking.contains { $0.param.matches(item) }
            let excepted = exceptions.contains { $0.param.matches(item) }
            return !(removed && !excepted)
        }
        guard kept.count != items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }

    // MARK: - Parse

    private static func parse(_ raw: String) -> Rule? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("!"), !line.contains("##"), !line.contains("#$#") else { return nil }
        let isException = line.hasPrefix("@@")
        if isException { line.removeFirst(2) }
        guard let dollar = line.lastIndex(of: "$") else { return nil }
        let pattern = String(line[..<dollar])
        let options = line[line.index(after: dollar)...].split(separator: ",").map(String.init)

        var param: Rule.Param?
        var permitted: [String] = [], restricted: [String] = []
        for opt in options {
            if opt == "removeparam" {
                param = .all
            } else if opt.hasPrefix("removeparam=") {
                let value = String(opt.dropFirst("removeparam=".count))
                if value.hasPrefix("~") { return nil } // inverted form: unsupported, skip rule
                if value.hasPrefix("/"), value.count > 2, let end = value.lastIndex(of: "/"), end != value.startIndex {
                    let body = String(value[value.index(after: value.startIndex)..<end])
                    let flags = value[value.index(after: end)...]
                    guard let re = try? NSRegularExpression(pattern: body, options: flags.contains("i") ? [.caseInsensitive] : []) else { return nil }
                    param = .regex(re)
                } else {
                    param = .name(value)
                }
            } else if opt.hasPrefix("domain=") {
                for d in opt.dropFirst("domain=".count).split(separator: "|") {
                    if d.hasPrefix("~") { restricted.append(String(d.dropFirst()).lowercased()) } else { permitted.append(String(d).lowercased()) }
                }
            } else if ["doc", "document", "~third-party", "3p", "~3p", "third-party", "first-party", "1p", "~1p", "important"].contains(opt) || opt.hasPrefix("app=") {
                continue
            } else {
                return nil // other resource-type options: not a navigation rule
            }
        }
        guard let p = param else { return nil }

        var host: String? = nil
        var pathHint: String? = nil
        if pattern.hasPrefix("||") {
            let rest = pattern.dropFirst(2)
            let hostEnd = rest.firstIndex(where: { $0 == "^" || $0 == "/" || $0 == "*" || $0 == "?" }) ?? rest.endIndex
            host = String(rest[..<hostEnd]).lowercased()
            var hint = String(rest[hostEnd...])
            if hint.hasPrefix("^") { hint.removeFirst() }
            hint = hint.replacingOccurrences(of: "*", with: "")
            if !hint.isEmpty { pathHint = hint }
        } else if !pattern.isEmpty && pattern != "*" {
            var hint = pattern.replacingOccurrences(of: "*", with: "")
            if hint.hasPrefix("|") { hint.removeFirst() }
            if hint.hasSuffix("|") { hint.removeLast() }
            if !hint.isEmpty { pathHint = hint }
        }
        return Rule(host: host, pathHint: pathHint, param: p, permittedDomains: permitted, restrictedDomains: restricted, isException: isException)
    }
}

fileprivate extension TrackingParamStripper.Rule {
    func matches(urlString: String, host: String) -> Bool {
        if let h = self.host, !(host == h || host.hasSuffix("." + h)) { return false }
        if let hint = pathHint, !urlString.contains(hint) { return false }
        for d in restrictedDomains where host == d || host.hasSuffix("." + d) { return false }
        if !permittedDomains.isEmpty, !permittedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return false }
        return true
    }
}

fileprivate extension TrackingParamStripper.Rule.Param {
    func matches(_ item: URLQueryItem) -> Bool {
        switch self {
        case .all: return true
        case .name(let n): return item.name == n
        case .regex(let re):
            let pair = item.value.map { "\(item.name)=\($0)" } ?? item.name
            return re.firstMatch(in: pair, range: NSRange(pair.startIndex..., in: pair)) != nil
                || re.firstMatch(in: item.name, range: NSRange(item.name.startIndex..., in: item.name)) != nil
        }
    }
}
