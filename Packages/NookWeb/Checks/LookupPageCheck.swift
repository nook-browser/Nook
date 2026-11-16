// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPageCheck.swift
//  Nook
//
//  The page Look It Up writes, for every way a lookup can end, and the folder it lives in.
//  Hostile text from the web must come out inert.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup
//    swiftc $L/LookupModels.swift $L/LookupPageRenderer.swift $L/LookupStore.swift \
//           Packages/NookWeb/Checks/LookupPageCheck.swift -o /tmp/lookup-page && /tmp/lookup-page
//

import Foundation

@main
struct LookupPageCheck {
    static func attributes(_ name: String, in html: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "\\s\(name)=\"([^\"]*)\"")
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).map { String(html[Range($0.range(at: 1), in: html)!]) }
    }

    static func main() {
        let evil = "<script>alert(1)</script>\"'><img src=x onerror=1>"
        func source(_ url: String, title: String = "A Page", read: Bool = true, image: String? = nil, notes: String = "") -> LookupSource {
            LookupSource(hit: LookupHit(url: URL(string: url)!, title: title, snippet: "snip"), search: 0, title: title, text: "text",
                         wasRead: read, imageFile: image, iconFile: nil, notes: notes)
        }
        let search = URL(string: "https://search.example/?q=x")!

        // MARK: done, explain
        var record = LookupRecord(request: "why " + evil, searchURL: search, accentHex: "#aa3366")
        record.outcome = .done
        record.sources = [
            source("https://example.com/a", title: evil, image: "photo1.jpg"),
            source("http://insecure.example/b", title: "Insecure"),
            source("https://www.example.org/c", title: "Unread", read: false, image: "../../etc/passwd"),
            source("https://example.net/d", title: "Odd image", image: "https://evil.example/x.png"),
        ]
        record.answer = LookupAnswer(
            title: evil + String(repeating: "x", count: 50_000),
            points: [LookupPoint(label: evil, sentence: evil, source: 1), LookupPoint(label: "Second", sentence: "From two.", source: 2)],
            sections: [LookupSection(heading: evil, points: [LookupPoint(label: "L", sentence: "In a section.", source: 3)])])
        var html = LookupPageRenderer.html(record)
        precondition(!html.contains("<script") && !html.contains("onerror=1>") && html.contains("&lt;script&gt;"))
        precondition(html.contains("Content-Security-Policy") && html.contains("default-src 'none'") && !html.contains("script-src"))
        precondition(html.contains("Pages Read") && html.contains("In a section.") && html.contains("From two."))
        precondition(html.contains("--accent:#aa3366"))
        precondition(attributes("href", in: html).allSatisfy { $0.hasPrefix("https://") || $0.hasPrefix("do/") }, "links are https or the page's own action")
        record.searchURL = URL(string: "http://searx.local:8080/search?q=x")
        precondition(!LookupPageRenderer.html(record).contains("searx.local"), "a finished answer offers no search link")
        record.searchURL = search
        precondition(attributes("href", in: html).contains("https://example.com/a") && !html.contains("insecure.example/b\""))
        precondition(attributes("src", in: html) == ["photo1.jpg"], "an image is a bare file name in the folder")
        precondition(html.contains("This site would not load in the background."))
        precondition(!html.contains(String(repeating: "x", count: 201)), "a title is cut to 200 characters")
        precondition(!html.contains("Nothing came back") && !html.contains("What Each Page Says"))

        // an accent that is not a color falls back
        record.accentHex = "red;}</style><script>"
        precondition(!LookupPageRenderer.html(record).contains("red;}"))
        record.accentHex = "#aa3366"

        // MARK: done, choose
        record.answer = LookupAnswer(title: "Soups", intro: "Three soups " + evil, options: [
            LookupOption(name: "White Bean " + evil, detail: "Takes an hour.", source: 1),
            LookupOption(name: "Nowhere", detail: "Bad source.", source: 9),
        ])
        html = LookupPageRenderer.html(record)
        precondition(html.contains("White Bean") && html.contains("Takes an hour.") && html.contains("Open on example.com"))
        precondition(html.contains("Nowhere") && html.contains("Pages Read"))
        precondition(!html.contains("<script") && attributes("href", in: html).allSatisfy { $0.hasPrefix("https://") || $0.hasPrefix("do/") })
        precondition(attributes("src", in: html).allSatisfy { !$0.contains("/") && !$0.contains(":") })

        // MARK: nothing found, and failed with nothing to show
        record.answer = nil
        record.sources = []
        for outcome in [LookupOutcome.nothingFound, .failed] {
            record.outcome = outcome
            html = LookupPageRenderer.html(record)
            precondition(html.contains("Nothing came back for this.") && html.contains("Search the Web Instead"))
            precondition(attributes("href", in: html) == ["https://search.example/?q=x"])
        }
        // the pages that were found are still listed when nothing could be written from them
        record.outcome = .failed
        record.sources = [source("https://example.com/a", title: "Found", notes: ""), source("https://example.com/b", title: "Also Found", notes: "NONE")]
        html = LookupPageRenderer.html(record)
        precondition(html.contains("Nothing came back for this.") && html.contains("Pages Read") && html.contains("Also Found"))
        precondition(attributes("href", in: html).contains("https://example.com/a") && html.contains("Search the Web Instead"))
        record.sources = []
        // the person's own search engine may be plain http (a local one); nothing else may
        record.searchURL = URL(string: "http://searx.local:8080/search?q=x")
        precondition(LookupPageRenderer.html(record).contains("href=\"http://searx.local:8080/search?q=x\""))
        // no ordinary search to offer: the line alone
        record.searchURL = URL(string: "javascript:alert(1)")
        html = LookupPageRenderer.html(record)
        precondition(html.contains("Nothing came back for this.") && !html.contains("Search the Web Instead") && attributes("href", in: html).isEmpty)
        record.searchURL = search

        // MARK: failed with notes
        record.outcome = .failed
        record.sources = [source("https://example.com/a", title: "First", notes: "- Built in 1956 " + evil), source("https://example.com/b", title: "Second", notes: "NONE")]
        html = LookupPageRenderer.html(record)
        precondition(html.contains("What Each Page Says") && html.contains("Built in 1956") && html.contains("Search the Web Instead"))
        precondition(!html.contains("NONE") && !html.contains("<script") && !html.contains("Nothing came back"))

        // MARK: running and stopped
        for outcome in [LookupOutcome.running, .stopped] {
            record.outcome = outcome
            html = LookupPageRenderer.html(record)
            precondition(html.contains("why &lt;script&gt;") && html.contains("Search the Web Instead"))
            precondition(!html.contains("Pages Read") && !html.contains("Nothing came back") && !html.contains("Built in 1956"))
        }

        // MARK: the folder
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("lookup-check-\(UUID().uuidString)").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: support) }
        record.outcome = .done
        try! LookupStore.write(record, in: support)
        let page = LookupStore.pageURL(for: record.id, in: support)
        precondition(page.path.hasSuffix("/Lookups/\(record.id.uuidString)/page.html"))
        precondition(FileManager.default.fileExists(atPath: page.path))
        precondition(LookupStore.record(for: record.id, in: support) == record)
        precondition(LookupStore.record(for: UUID(), in: support) == nil)
        precondition(LookupStore.lookupID(ofPage: page, in: support) == record.id)
        let root = LookupStore.root(in: support)
        for stranger in [
            URL(fileURLWithPath: "/etc/hosts"), URL(string: "https://example.com/Lookups/\(record.id.uuidString)/page.html")!,
            root.appendingPathComponent("../x/page.html"), root.appendingPathComponent("not-a-uuid/page.html"),
            root.appendingPathComponent(record.id.uuidString).appendingPathComponent("record.json"),
            URL(fileURLWithPath: "/tmp/Lookups/\(record.id.uuidString)/page.html"),
            root.appendingPathComponent(record.id.uuidString).appendingPathComponent("sub/page.html"),
        ] {
            precondition(LookupStore.lookupID(ofPage: stranger, in: support) == nil, stranger.path)
        }

        precondition(LookupStore.hasLookups(in: support) && !LookupStore.hasLookups(in: support.appendingPathComponent("missing")))
        let other = LookupRecord(request: "other")
        try! LookupStore.write(other, in: support)
        let outside = support.appendingPathComponent("Tabs")
        try! FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        // a folder made after the sweep's cutoff belongs to a lookup that started since, and stays
        LookupStore.sweep(keeping: [record.id], in: support, olderThan: Date(timeIntervalSinceNow: -3600))
        precondition(LookupStore.record(for: other.id, in: support) != nil)
        LookupStore.sweep(keeping: [record.id], in: support, olderThan: Date(timeIntervalSinceNow: 60))
        precondition(LookupStore.record(for: record.id, in: support) != nil && LookupStore.record(for: other.id, in: support) == nil)
        precondition(FileManager.default.fileExists(atPath: outside.path), "nothing outside Lookups is touched")
        LookupStore.sweep(keeping: [], in: support.appendingPathComponent("missing"), olderThan: Date())
    }
}
