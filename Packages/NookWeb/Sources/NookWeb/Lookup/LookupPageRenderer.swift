// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPageRenderer.swift
//  NookWeb
//
//  The page a lookup becomes: static HTML with no script, every string from the web escaped,
//  every link an https result URL and every image a file in the lookup's own folder.
//  Foundation only, so `Checks/LookupPageCheck.swift` can compile it.
//

import Foundation

public enum LookupPageRenderer {
    private static let maxTitle = 200
    private static let maxPhotos = 5

    public static func html(_ record: LookupRecord) -> String {
        let answerTitle = record.answer?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: String
        var title = record.request
        switch record.outcome {
        case .running, .stopped:
            body = heading(record.request) + searchInstead(record)
        case .nothingFound:
            body = heading(record.request) + nothing(record)
        case .failed:
            body = heading(record.request) + (notesBody(record) ?? nothing(record))
        case .done:
            if record.sources.contains(where: { $0.prefilledURL != nil }) {
                body = heading(record.request) + placesBody(record)
            } else if let answer = record.answer, !answer.isEmpty {
                if !answerTitle.isEmpty { title = answerTitle }
                body = "<p class=\"ask\">\(escaped(record.request))</p>" + answerBody(answer, title: title, record)
            } else {
                body = heading(record.request) + (notesBody(record) ?? nothing(record))
            }
        }
        return document(title: title, accent: record.accentHex, body: body)
    }

    // MARK: - Layouts

    private static func answerBody(_ answer: LookupAnswer, title: String, _ record: LookupRecord) -> String {
        if answer.options.isEmpty {
            let photos = record.sources.compactMap { image($0.imageFile) }.prefix(maxPhotos).joined()
            return (photos.isEmpty ? "" : "<div class=\"photos\">\(photos)</div>")
                + heading(title) + points(answer.points, record) + sources(record)
                + answer.sections.map { "<h2>\(escaped($0.heading))</h2>" + points($0.points, record) }.joined()
        }
        let intro = answer.intro.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading(title) + (intro.isEmpty ? "" : "<p class=\"intro\">\(escaped(intro))</p>")
            + "<div class=\"cards\">" + answer.options.map { card($0, record) }.joined() + "</div>" + sources(record)
    }

    private static func points(_ points: [LookupPoint], _ record: LookupRecord) -> String {
        guard !points.isEmpty else { return "" }
        return "<ul class=\"points\">" + points.map { point in
            "<li><b>\(escaped(point.label))</b><span>\(escaped(point.sentence)) \(cite(point.source, record))</span></li>"
        }.joined() + "</ul>"
    }

    /// The source's number, linked to its page when that page is https.
    private static func cite(_ number: Int, _ record: LookupRecord) -> String {
        guard record.sources.indices.contains(number - 1) else { return "" }
        guard let href = link(record.sources[number - 1].hit.url) else { return "<span class=\"cite\">\(number)</span>" }
        return "<a class=\"cite\" href=\"\(href)\">\(number)</a>"
    }

    private static func card(_ option: LookupOption, _ record: LookupRecord) -> String {
        let source = record.sources.indices.contains(option.source - 1) ? record.sources[option.source - 1] : nil
        let open = source.flatMap { source in
            link(source.hit.url).map { "<a class=\"open\" href=\"\($0)\">Open on \(escaped(host(source.hit.url)))</a>" }
        } ?? ""
        return "<article class=\"card\">\(source.flatMap { image($0.imageFile) } ?? "")<div><h3>\(escaped(option.name))</h3>"
            + "<p>\(escaped(option.detail))</p>\(open)</div></article>"
    }

    /// A booking: one card a place. Nothing here was written across pages.
    private static func placesBody(_ record: LookupRecord) -> String {
        "<div class=\"cards\">" + record.sources.enumerated().map { place($1, number: $0 + 1, record) }.joined() + "</div>" + sources(record)
    }

    /// A place's card: its booking page's picture, a line about it, what it offers at the asked time
    /// and its address set to the party and day. `#do/<number>` asks Nook to press that time.
    private static func place(_ source: LookupSource, number: Int, _ record: LookupRecord) -> String {
        let target = source.prefilledURL ?? source.hit.url
        let href = link(target)
        let name = String((source.name.isEmpty ? (source.title.isEmpty ? source.hit.title : source.title) : source.name).prefix(maxTitle))
        let shot = image(source.shotFile, class: "shot").map { picture in href.map { "<a href=\"\($0)\">\(picture)</a>" } ?? picture } ?? ""
        let about = source.about.isEmpty ? "" : "<p>\(escaped(source.about))</p>"
        let times: String
        if source.prefilledURL != nil, !source.wasRead {
            times = "<p>This site would not load in the background.</p>"
        } else {
            times = LookupTimes.line(place: name, asked: record.booking?.time, times: source.times).map { "<p class=\"times\">\(escaped($0))</p>" } ?? ""
        }
        let open = href.map { "<a class=\"open\" href=\"\($0)\">Open on \(escaped(host(target)))</a>" } ?? ""
        var pick = ""
        if source.prefilledURL != nil, source.wasRead, let asked = record.booking?.time, LookupTimes.offers(asked, in: source.times),
           let shown = LookupTimes.display(asked) {
            pick = "<a class=\"open pick\" href=\"#do/\(number)\">Pick \(escaped(shown)) for Me</a>"
        }
        return "<article class=\"card place\">\(shot)<div><h3>\(escaped(name))</h3>\(about)\(times)\(pick)\(open)</div></article>"
    }

    private static func sources(_ record: LookupRecord) -> String {
        guard !record.sources.isEmpty else { return "" }
        return "<section class=\"sources\"><h2>Pages Read</h2>" + record.sources.enumerated().map { index, source in
            let name = escaped(String((source.title.isEmpty ? source.hit.title : source.title).prefix(maxTitle)))
            let unread = source.wasRead ? "" : "<small>This site would not load in the background.</small>"
            let inner = "\(image(source.iconFile, class: "icon") ?? "<i></i>")<span><b>\(index + 1). \(name)</b>"
                + "<small>\(escaped(host(source.hit.url)))</small>\(unread)</span>"
            return link(source.hit.url).map { "<a class=\"row\" href=\"\($0)\">\(inner)</a>" } ?? "<div class=\"row\">\(inner)</div>"
        }.joined() + "</section>"
    }

    /// Each page's notes under its title, for when the answer could not be written.
    private static func notesBody(_ record: LookupRecord) -> String? {
        let noted = record.sources.filter { source in
            let notes = source.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return !notes.isEmpty && notes.uppercased() != "NONE"
        }
        guard !noted.isEmpty else { return nil }
        return "<h2>What Each Page Says</h2>" + noted.map { source in
            let name = escaped(String((source.title.isEmpty ? source.hit.title : source.title).prefix(maxTitle)))
            let title = link(source.hit.url).map { "<a href=\"\($0)\">\(name)</a>" } ?? name
            let lines = source.notes.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t")) }
                .filter { !$0.isEmpty && $0.uppercased() != "NONE" }
            return "<h3>\(title)</h3><ul class=\"notes\">" + lines.map { "<li>\(escaped($0))</li>" }.joined() + "</ul>"
        }.joined() + searchInstead(record)
    }

    /// The one line for a lookup with nothing to show, then whatever pages it did find.
    private static func nothing(_ record: LookupRecord) -> String {
        "<p class=\"intro\">Nothing came back for this.</p>" + searchInstead(record) + sources(record)
    }

    /// The same text as an ordinary search. The address is the person's own search engine, not
    /// something a page supplied, so plain http is allowed: a local engine has no certificate.
    private static func searchInstead(_ record: LookupRecord) -> String {
        guard let url = record.searchURL, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return "" }
        return "<p><a class=\"open\" href=\"\(escaped(url.absoluteString))\">Search the Web Instead</a></p>"
    }

    private static func heading(_ text: String) -> String {
        "<h1>\(escaped(String(text.prefix(maxTitle))))</h1>"
    }

    // MARK: - Safety

    /// The escaped address of an https page, the only kind this page links to.
    private static func link(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return escaped(url.absoluteString)
    }

    /// An image tag for a file in the lookup's folder. A name with a path or a scheme is refused.
    private static func image(_ file: String?, class name: String? = nil) -> String? {
        guard let file, !file.isEmpty, !file.contains("/"), !file.contains(":"), !file.contains("\\"), !file.hasPrefix(".") else { return nil }
        return "<img\(name.map { " class=\"\($0)\"" } ?? "") src=\"\(escaped(file))\" alt=\"\">"
    }

    private static func host(_ url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Document

    private static func document(title: String, accent: String, body: String) -> String {
        let isColor = accent.count == 7 && accent.hasPrefix("#") && accent.dropFirst().allSatisfy(\.isHexDigit)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file:; style-src 'unsafe-inline'">
        <title>\(escaped(String(title.prefix(maxTitle))))</title><style>
        :root{--accent:\(isColor ? accent : LookupRecord.defaultAccent)}
        :root{color-scheme:light dark;--bg:#fbfbfa;--fg:#1c1c1e;--dim:#6e6e73;--card:#fff;--line:#0000001a;--ink:color-mix(in srgb,var(--accent) 70%,var(--fg))}
        @media(prefers-color-scheme:dark){:root{--bg:#161617;--fg:#f2f2f3;--dim:#98989d;--card:#232325;--line:#ffffff1f}}
        body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,system-ui,sans-serif;overflow-wrap:anywhere}
        main{max-width:760px;margin:0 auto;padding:48px 24px 96px}
        a{color:var(--ink)}
        .ask{color:var(--dim);font-size:13px;margin:0 0 20px}
        .photos{display:flex;gap:12px;overflow-x:auto;scroll-snap-type:x mandatory;margin:0 0 28px}
        .photos img{height:260px;max-width:86%;object-fit:cover;border-radius:16px;scroll-snap-align:start;border:1px solid var(--line)}
        h1{font-size:32px;line-height:1.15;margin:0 0 24px;letter-spacing:-.02em}
        h2{font-size:15px;color:var(--ink);margin:36px 0 12px}
        h3{font-size:18px;margin:24px 0 6px}
        .intro{font-size:18px;margin:0 0 24px}
        .points,.notes{margin:0;padding:0;display:grid;gap:14px}
        .points{list-style:none}.notes{padding-left:20px;gap:6px}
        .points li{display:grid;grid-template-columns:150px 1fr;gap:16px}
        .points b{font-weight:600}
        .cite{font-size:11px;color:var(--dim);text-decoration:none;border:1px solid var(--line);border-radius:6px;padding:0 5px;vertical-align:2px}
        .cards{display:grid;gap:14px}
        .card{display:grid;grid-template-columns:200px 1fr;gap:18px;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px}
        .card:not(:has(img)),.card.place{grid-template-columns:1fr}
        .card .shot{width:100%;height:auto;border:1px solid var(--line)}
        .times{font-weight:600}
        .card img{width:200px;height:140px;object-fit:cover;border-radius:10px}
        .card h3{margin:2px 0 6px}.card p{margin:0 0 12px}
        .open{display:inline-block;text-decoration:none;font-weight:600;font-size:14px}
        .pick{margin-right:18px}
        .sources{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:6px 14px 10px;margin:32px 0 0}
        .sources h2{font-size:12px;color:var(--dim);font-weight:500;margin:10px 0 4px}
        .row{display:flex;gap:12px;align-items:center;padding:8px 0;color:inherit;text-decoration:none;border-top:1px solid var(--line)}
        .row:first-of-type{border-top:0}
        .row .icon,.row i{flex:none;width:20px;height:20px;border-radius:5px;background:var(--line)}
        .row .icon{background:none}
        .row span{display:grid;min-width:0}.row b{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row small{color:var(--dim)}
        @media(max-width:560px){.points li{grid-template-columns:1fr;gap:2px}.card{grid-template-columns:1fr}.card img{width:100%;height:180px}}
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}
