// Licensed under GPL-3.0. See LICENSE.
//
//  LiveParsers.swift
//  Nook
//
//  Pure readers for live folder sources: URL shapes and response parsing. Foundation only, so
//  Packages/NookWeb/Checks/LiveParsersCheck.swift can compile it on its own.
//

import Foundation

enum LiveParse {
    typealias Entry = (url: URL, title: String)

    // MARK: - GitHub

    /// github.com/<owner>/<repo>/<kind>/<number>.
    private static func isGitHubThread(_ url: URL, kinds: Set<String>) -> Bool {
        let parts = url.path.split(separator: "/")
        return url.host == "github.com" && parts.count == 4 && kinds.contains(String(parts[2])) && Int(parts[3]) != nil
    }

    static func ownsIssue(_ url: URL) -> Bool { isGitHubThread(url, kinds: ["issues"]) }

    /// Issue, pull request and discussion threads, plus the commit and release pages notifications link to.
    static func ownsNotification(_ url: URL) -> Bool {
        if isGitHubThread(url, kinds: ["issues", "pull", "discussions"]) { return true }
        let parts = url.path.split(separator: "/")
        guard url.host == "github.com" else { return false }
        return (parts.count == 4 && parts[2] == "commit") || (parts.count == 5 && parts[2] == "releases" && parts[3] == "tag")
    }

    /// The URL without query and fragment, so `notification_referrer_id` and comment anchors drop out.
    static func permalink(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }

    /// Any object in the JSON with a string `title` and an issue URL under `permalink`, `url` or
    /// `html_url`, in document order. Tolerant on purpose: the route's shape is unverified.
    static func githubIssues(_ data: Data) -> [Entry]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: [Entry] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if let title = object["title"] as? String,
                   let link = ["permalink", "url", "html_url"].lazy.compactMap({ object[$0] as? String }).compactMap(URL.init(string:)).first(where: ownsIssue) {
                    found.append((link, title))
                }
                // Sorted keys keep the walk deterministic; arrays keep their order.
                for key in object.keys.sorted() { walk(object[key]!) }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(root)
        return unique(found)
    }

    /// Thread links in github.com/notifications' HTML: anchors whose href is a thread, titled by
    /// their `markdown-title` element when present, else by their text.
    static func githubNotifications(html: String) -> [Entry] {
        let anchor = try! NSRegularExpression(pattern: #"<a\b[^>]*?\bhref="([^"]+)"[^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let markdownTitle = try! NSRegularExpression(pattern: #"class="[^"]*\bmarkdown-title\b[^"]*"[^>]*>(.*?)</"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let base = URL(string: "https://github.com")!
        let ns = html as NSString
        var found: [Entry] = []
        for match in anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = decodeEntities(ns.substring(with: match.range(at: 1)))
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let clean = permalink(url)
            guard ownsNotification(clean) else { continue }
            let inner = ns.substring(with: match.range(at: 2))
            let innerNS = inner as NSString
            let titled = markdownTitle.firstMatch(in: inner, range: NSRange(location: 0, length: innerNS.length))
                .map { innerNS.substring(with: $0.range(at: 1)) } ?? inner
            let title = text(of: titled)
            if !title.isEmpty { found.append((clean, title)) }
        }
        return unique(found)
    }

    // MARK: - Asana

    /// A task permalink: app.asana.com/1/<ws>/…/task/<gid>, or the older /0/<project>/<gid> (an
    /// optional trailing "f" is the focus view). Project and list pages are not tasks.
    static func ownsAsanaTask(_ url: URL) -> Bool {
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.last == "f" { parts.removeLast() }
        guard url.host == "app.asana.com", let last = parts.last, !last.isEmpty, last.allSatisfy(\.isNumber) else { return false }
        if parts.first == "1" { return parts.count >= 4 && parts[parts.count - 2] == "task" }
        return parts.first == "0" && parts.count == 3
    }

    /// Workspace gids from /api/1.0/users/me?opt_fields=workspaces.
    static func asanaWorkspaces(_ data: Data) -> [String]? {
        struct Response: Decodable {
            struct User: Decodable { let workspaces: [Workspace] }
            struct Workspace: Decodable { let gid: String }
            let data: User
        }
        return (try? JSONDecoder().decode(Response.self, from: data))?.data.workspaces.map(\.gid)
    }

    struct AsanaTask: Decodable {
        let name: String
        let permalink_url: URL
        let due_on: String?
        let completed: Bool?
    }

    /// Tasks from /api/1.0/tasks; incomplete only.
    static func asanaTasks(_ data: Data) -> [AsanaTask]? {
        struct Response: Decodable { let data: [AsanaTask] }
        return (try? JSONDecoder().decode(Response.self, from: data))?.data.filter { $0.completed != true }
    }

    /// Due date ascending (ISO dates sort as strings), undated last, at most `limit`.
    static func rankAsanaTasks(_ tasks: [AsanaTask], limit: Int = 25) -> [Entry] {
        let sorted = tasks.enumerated().sorted { a, b in
            switch (a.element.due_on, b.element.due_on) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }
        return unique(sorted.map(\.element).filter { ownsAsanaTask($0.permalink_url) }.map { ($0.permalink_url, $0.name) })
            .prefix(limit).map { $0 }
    }

    // MARK: - Feeds

    /// An RSS 2.0 or Atom document: its own title and its first `limit` items with http(s) links,
    /// in document order. Nil when the data is not a feed.
    static func feed(_ data: Data, base: URL, limit: Int = 15) -> (title: String?, items: [Entry])? {
        let reader = FeedReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        let ok = parser.parse()
        guard reader.sawFeed, ok || !reader.items.isEmpty else { return nil }
        let items: [Entry] = reader.items.compactMap { item in
            guard let url = URL(string: item.link, relativeTo: base)?.absoluteURL,
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            return (url, item.title.isEmpty ? url.absoluteString : item.title)
        }
        let title = reader.title.flatMap { $0.isEmpty ? nil : $0 }
        return (title, Array(unique(items).prefix(limit)))
    }

    private final class FeedReader: NSObject, XMLParserDelegate {
        var title: String?
        var items: [(link: String, title: String)] = []
        var sawFeed = false
        private var inItem = false
        private var itemLink: String?
        private var itemTitle = ""
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "rss", "feed", "rdf:RDF": sawFeed = true
            case "item", "entry": inItem = true; itemLink = nil; itemTitle = ""
            case "link" where inItem && itemLink == nil:
                if let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" { itemLink = href }
            default: break
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "item", "entry":
                if let itemLink { items.append((itemLink, itemTitle)) }
                inItem = false
            case "title" where inItem: itemTitle = LiveParse.text(of: value)
            case "link" where inItem && itemLink == nil && !value.isEmpty: itemLink = value
            case "title" where title == nil: title = LiveParse.text(of: value)
            default: break
            }
            text = ""
        }
    }

    // MARK: - Helpers

    /// First entry per URL, in order.
    private static func unique(_ entries: [Entry]) -> [Entry] {
        var seen: Set<URL> = []
        return entries.filter { seen.insert($0.url).inserted }
    }

    /// Markup stripped, entities decoded, whitespace collapsed.
    static func text(of html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return decodeEntities(stripped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
