// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPageCheck.swift
//  Nook
//
//  The page Look It Up writes, for every way a lookup can end, and the folder it lives in.
//  Hostile text from the web must come out inert.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup
//    swiftc $L/LookupModels.swift $L/LookupTimes.swift $L/LookupPageRenderer.swift $L/LookupStore.swift \
//           Packages/NookWeb/Checks/LookupPageCheck.swift -o /tmp/lookup-page && /tmp/lookup-page
//

import Foundation

@main
struct LookupPageCheck {
    static func attributes(_ name: String, in html: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "\\s\(name)=\"([^\"]*)\"")
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).map { String(html[Range($0.range(at: 1), in: html)!]) }
    }

    /// Nothing the page could run or fetch: no script, no CSS `url(`, no `data:` address.
    static func inert(_ html: String) -> Bool {
        !html.contains("<script") && !html.contains("url(") && !html.contains("data:")
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
            source("https://example.net/e", title: "Inline image", image: "data:image/png;base64,AAAA"),
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
        precondition(inert(html), "an image named as a data: address is refused like any other")
        precondition(attributes("style", in: html).allSatisfy { $0.hasPrefix("--i:") && Int($0.dropFirst(4)) != nil }, "a style attribute holds a number Nook wrote")

        // MARK: glyphs: one a label, the same every launch, and nothing of the label itself
        precondition(LookupPageRenderer.glyph(for: "History") == "📜" && LookupPageRenderer.glyph(for: "Ticket Prices") == "🎟️")
        precondition(LookupPageRenderer.glyph(for: "Zxqv") == "✨", "a label the table does not know still gets the same glyph each time")
        // a glyph that passes judgment is for a label that does
        for neutral in ["Café con leche", "iPhone 17 Pro", "Limited Edition", "Recording Studio"] {
            precondition(!["👍", "👎", "⚠️", "🏆"].contains(LookupPageRenderer.glyph(for: neutral)), neutral)
        }
        precondition(LookupPageRenderer.glyph(for: "Pros") == "👍" && LookupPageRenderer.glyph(for: "Cons") == "👎")
        precondition(LookupPageRenderer.glyph(for: evil).unicodeScalars.allSatisfy { !$0.isASCII }, "a label never reaches its tile")
        let several = LookupPageRenderer.glyphs(for: ["History", "History", "Early History", evil, ""])
        precondition(Set(several).count == several.count && several.joined().unicodeScalars.allSatisfy { !$0.isASCII }, "no glyph twice in a list")

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
        precondition(attributes("src", in: html).allSatisfy { !$0.contains("/") && !$0.contains(":") } && inert(html))

        // MARK: nothing found, and failed with nothing to show
        record.answer = nil
        record.sources = []
        for outcome in [LookupOutcome.nothingFound, .failed] {
            record.outcome = outcome
            html = LookupPageRenderer.html(record)
            precondition(html.contains("Nothing came back for this.") && html.contains("Search the Web Instead"))
            precondition(attributes("href", in: html) == ["https://search.example/?q=x"] && inert(html))
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
        precondition(!html.contains("NONE") && inert(html) && !html.contains("Nothing came back"))

        // MARK: running and stopped
        for outcome in [LookupOutcome.running, .stopped] {
            record.outcome = outcome
            html = LookupPageRenderer.html(record)
            precondition(html.contains("why &lt;script&gt;") && html.contains("Search the Web Instead"))
            precondition(!html.contains("Pages Read") && !html.contains("Nothing came back") && !html.contains("Built in 1956") && inert(html))
        }

        // MARK: a booking: each place's page, the times read off it, and its own address opened on the party and day
        record.outcome = .done
        record.answer = nil
        record.booking = BookingDetails(people: 2, date: "2026-11-16", time: "19:00")
        var lilia = source("https://resy.com/cities/new-york-ny/venues/lilia", title: "Book Lilia")
        lilia.prefilledURL = URL(string: "https://resy.com/cities/new-york-ny/venues/lilia?seats=2&date=2026-11-16")
        lilia.name = "Lilia"
        lilia.about = "Italian in Williamsburg " + evil
        lilia.times = ["5:00 PM", "9:15 PM"]
        lilia.shotFile = "shot1.jpg"
        var kings = source("https://resy.com/cities/new-york-ny/venues/kings", title: "Book Kings")
        kings.prefilledURL = URL(string: "https://resy.com/cities/new-york-ny/venues/kings?seats=2&date=2026-11-16")
        kings.name = "Kings Co Imperial " + evil
        kings.times = ["6:30 PM", "7:00 PM"]
        var down = source("https://resy.com/cities/new-york-ny/venues/llama", title: "Book Llama", read: false)
        down.prefilledURL = down.hit.url
        down.name = "llama inn"
        var plain = source("https://llama.example/p", title: "Llama Inn Blog")
        plain.about = "Peruvian cooking."
        record.sources = [lilia, kings, down, plain]
        html = LookupPageRenderer.html(record)
        precondition(html.contains("Lilia has no 7:00 PM. Open times: 5:00 PM, 9:15 PM.") && html.contains("has 7:00 PM.") && html.contains("Kings Co Imperial &lt;script&gt;"))
        precondition(html.contains("href=\"https://resy.com/cities/new-york-ny/venues/lilia?seats=2&amp;date=2026-11-16\"") && html.contains("Open on resy.com"))
        precondition(html.contains("llama inn") && html.contains("This site would not load in the background."))
        precondition(html.contains("Llama Inn Blog") && html.contains("Peruvian cooking.") && html.contains("Open on llama.example") && html.contains("Pages Read"))
        precondition(inert(html) && attributes("src", in: html) == ["shot1.jpg"])
        precondition(attributes("href", in: html).allSatisfy { $0.hasPrefix("https://") || $0.hasPrefix("#do/") })
        precondition(!html.contains("Nothing came back"), "a booking page with no written answer is still a page")
        // the one thing Nook offers to press: the asked time, on the card whose page has it
        precondition(attributes("href", in: html).filter { $0.hasPrefix("#") } == ["#do/2"] && html.contains(">Pick 7:00 PM for Me</a>"))
        record.sources[1].wasRead = false
        precondition(!LookupPageRenderer.html(record).contains("#do/"), "a page that was not read offers nothing to press")
        record.sources[1].wasRead = true
        // no time asked: nothing is said about times
        record.booking = BookingDetails(people: 2)
        html = LookupPageRenderer.html(record)
        precondition(!html.contains("has no ") && !html.contains(" has 7:00") && html.contains("Open on resy.com"))
        precondition(!html.contains("#do/") && !html.contains("for Me"))

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

        // the card button's address is its own page with a card number after the "#", and means
        // that card only from that page: a file that does not exist is never asked about by WebKit
        func button(_ fragment: String, on page: URL) -> URL { URL(string: page.absoluteString + "#" + fragment)! }
        precondition(LookupStore.action(of: button("do/2", on: page), fromPage: page, in: support) == 2)
        precondition(LookupStore.action(of: URL(string: "#do/2", relativeTo: page)!.absoluteURL, fromPage: page, in: support) == 2)
        let folder = LookupStore.folder(for: record.id, in: support)
        let otherPage = LookupStore.pageURL(for: UUID(), in: support)
        for (target, from) in [
            (button("do/0", on: page), page), (button("do/x", on: page), page), (button("do/2/3", on: page), page),
            (button("do", on: page), page), (button("2", on: page), page), (button("do/999", on: page), page),
            (button("do/02", on: page), page), (button("", on: page), page), (page, page),
            (button("do/2", on: otherPage), page), (button("do/2", on: page), otherPage),
            (button("do/2", on: page), URL(string: "https://example.com/page.html")!),
            (URL(string: "https://example.com/page.html#do/2")!, page),
            (button("do/2", on: folder.appendingPathComponent("record.json")), page),
            (folder.appendingPathComponent("do/2"), page),
        ] {
            precondition(LookupStore.action(of: target, fromPage: from, in: support) == nil, target.absoluteString)
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
