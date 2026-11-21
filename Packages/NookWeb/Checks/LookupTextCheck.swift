// Licensed under GPL-3.0. See LICENSE.
//
//  LookupTextCheck.swift
//  Nook
//
//  What Look It Up reads from a page's HTML and from a web view's innerText:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Lookup/LookupText.swift \
//           Packages/NookWeb/Checks/LookupTextCheck.swift -o /tmp/lookup-text && /tmp/lookup-text
//

import Foundation

@main
struct LookupTextCheck {
    static func main() {
        let base = URL(string: "https://example.com/x/y")!
        let html = "<html><head><title> A &amp; B </title><meta property=\"og:image\" content=\"/img/a.jpg\"><script>var x='<p>no</p>'</script><style>p{}</style></head><body><nav>Menu</nav><article><h2>Soups</h2><ul><li>White bean</li><li>Minestrone</li></ul>"
            + String(repeating: "<p>Real text here.</p>", count: 150) + "</article><footer>Foot</footer></body></html>"
        let page = LookupText.page(fromHTML: html, baseURL: base)
        precondition(page.title == "A & B")
        precondition(page.image?.absoluteString == "https://example.com/img/a.jpg")
        precondition(page.text.contains("Soups") && page.text.contains("White bean") && page.text.contains("Minestrone"))
        precondition(!page.text.contains("Menu") && !page.text.contains("Foot") && !page.text.contains("var x") && !page.text.contains("<"))
        // list items stay apart
        precondition(page.text.contains("White bean\nMinestrone"))

        // an image that is not https is dropped; attribute order does not matter
        let e = URL(string: "https://e.com")!
        precondition(LookupText.page(fromHTML: "<meta property=\"og:image\" content=\"http://10.0.0.1/a.png\">", baseURL: e).image == nil)
        precondition(LookupText.page(fromHTML: "<meta content=\"https://e.com/b.png\" property=\"og:image\">", baseURL: e).image?.path == "/b.png")
        precondition(LookupText.page(fromHTML: "<meta property='og:image' content='javascript:alert(1)'>", baseURL: e).image == nil)

        // a page with no article keeps its body text; nothing in gives nothing out
        precondition(LookupText.page(fromHTML: "<body><div>Plain &lt;b&gt; &#8217;quoted&#x27; text</div></body>", baseURL: e).text == "Plain <b> \u{2019}quoted' text")
        let empty = LookupText.page(fromHTML: "", baseURL: e)
        precondition(empty.text.isEmpty && empty.title == nil && empty.image == nil)

        // a page is read in the encoding it names: the response's first, then its own meta tag, then UTF-8
        let latin = Data("<p>caf".utf8) + Data([0xE9, 0x20, 0x92]) + Data("</p>".utf8)
        precondition(LookupText.text(of: latin, encodingName: "iso-8859-1") == "<p>caf\u{E9} \u{2019}</p>", "a Latin-1 label reads as windows-1252")
        precondition(LookupText.text(of: Data("caf".utf8) + Data([0xE9, 0x81]), encodingName: "ISO-8859-1") == "caf\u{E9}\u{81}", "bytes windows-1252 leaves undefined still read")
        precondition(LookupText.text(of: latin, encodingName: "windows-1252") == "<p>caf\u{E9} \u{2019}</p>")
        let japanese = "<p>\u{65E5}\u{672C}\u{8A9E}</p>"
        let sjis = japanese.data(using: .shiftJIS)!
        precondition(String(decoding: sjis, as: UTF8.self).contains("\u{FFFD}"), "as UTF-8 these bytes are lost")
        for name in ["Shift_JIS", "shift_jis", "x-sjis"] { precondition(LookupText.text(of: sjis, encodingName: name) == japanese, name) }
        let tagged = Data("<html><head><meta charset=\"shift_jis\"></head>".utf8) + sjis
        precondition(LookupText.text(of: tagged, encodingName: nil).hasSuffix(japanese), "the page's own meta tag")
        let httpEquiv = Data("<META http-equiv=Content-Type content='text/html; charset=windows-1252'>".utf8) + Data([0x93, 0x94])
        precondition(LookupText.text(of: httpEquiv, encodingName: nil).hasSuffix("\u{201C}\u{201D}"))
        let utf8Page = "<meta charset=\"shift_jis\"><p>caf\u{E9} \u{65E5}</p>"
        precondition(LookupText.text(of: Data(utf8Page.utf8), encodingName: "utf-8") == utf8Page, "the response outranks the meta tag")
        precondition(LookupText.text(of: Data("plain \u{E9}".utf8), encodingName: "no-such-charset") == "plain \u{E9}", "a name it does not know falls back to UTF-8")
        precondition(LookupText.text(of: Data("plain \u{E9}".utf8), encodingName: nil) == "plain \u{E9}")
        let broken = LookupText.text(of: Data("kept ".utf8) + Data([0xFF, 0xFE]) + Data(" text".utf8), encodingName: "utf-8")
        precondition(broken.hasPrefix("kept ") && broken.hasSuffix(" text") && broken.contains("\u{FFFD}"), "bad bytes are replaced, the page stays")
        precondition(LookupText.text(of: Data(), encodingName: nil).isEmpty)
        // a fetched Shift-JIS page reads whole
        let article = "<html><head><title>\u{65E5}\u{672C}</title></head><body><p>" + String(repeating: "\u{65E5}\u{672C}\u{8A9E}", count: 400) + "</p></body></html>"
        let read = LookupText.page(fromHTML: LookupText.text(of: article.data(using: .shiftJIS)!, encodingName: "Shift_JIS"), baseURL: e)
        precondition(read.title == "\u{65E5}\u{672C}" && read.text.count >= LookupText.thin && !read.text.contains("\u{FFFD}"))

        // titles and snippets: tags out, entities decoded, one line
        precondition(LookupText.plain("I came across <b>Vision</b> <b>Pro</b>\n glasses") == "I came across Vision Pro glasses")
        precondition(LookupText.plain("Here&#x27;s &amp; &quot;that&quot;") == "Here's & \"that\"")

        // line breaks survive, runs of spaces and blank lines do not
        precondition(LookupText.tidy(innerText: "Dinner\n\n\n5:00 PM   \t Bar\n9:15 PM\n") == "Dinner\n5:00 PM Bar\n9:15 PM")
        precondition(LookupText.excerpt(String(repeating: "x", count: 9000), characters: 6000).count == 6000)
        precondition(LookupText.excerpt("short", characters: 6000) == "short")
        precondition(LookupText.thin == 800)

        // excerpts share one budget: a short text whole, what it leaves split between the long ones
        let shared = LookupText.excerpts([String(repeating: "b", count: 5000), String(repeating: "a", count: 100), String(repeating: "c", count: 9000)], characters: 6100)
        precondition(shared.map(\.count) == [3000, 100, 3000] && shared[0].hasPrefix("b") && shared[2].hasPrefix("c"))
        precondition(LookupText.excerpts(["abc", "de"], characters: 100) == ["abc", "de"])
        precondition(LookupText.excerpts(["abc", "de"], characters: 0) == ["", ""] && LookupText.excerpts([], characters: 100).isEmpty)

        // no straight double quote reaches a model that answers in JSON: an inch mark closes, a quotation opens and closes
        precondition(LookupText.curlyQuotes("a 48\" TV, \"so called\" (\"x\")\n\"y\"") == "a 48\u{201D} TV, \u{201C}so called\u{201D} (\u{201C}x\u{201D})\n\u{201C}y\u{201D}")
        precondition(LookupText.curlyQuotes("it's plain") == "it's plain")
        // the answer's quotes go back, so a command copied from it still runs
        precondition(LookupText.straightQuotes("user.name \u{201C}Your Name\u{201D}, a 48\u{201D} TV") == "user.name \"Your Name\", a 48\" TV")

        // a tag that never closes costs nothing extra: these took 5 s and 23 s as regular expressions
        func seconds(_ body: () -> Void) -> Double {
            let start = Date()
            body()
            return Date().timeIntervalSince(start)
        }
        let filler = String(repeating: "word and another word. ", count: 30_000)
        for hostile in ["<nav>" + filler, "<title>" + filler, "<article>" + filler, String(repeating: "<", count: 600_000),
                        String(repeating: "<meta property=\"og:image\" ", count: 20_000), String(repeating: "<nav ", count: 150_000)] {
            var text = ""
            let took = seconds { text = LookupText.page(fromHTML: hostile, baseURL: e).text }
            precondition(took < 2, "\(hostile.prefix(12)) took \(took) s")
            _ = text
        }
        // a main holding several articles reads back whole, not as its first article
        let story = { (k: Int) in "<article><h2>Story \(k)</h2>" + String(repeating: "<p>Body of the story, some words.</p>", count: 60) + "</article>" }
        let stories = LookupText.page(fromHTML: "<body><nav>Menu</nav><main>" + (1...5).map(story).joined() + "</main></body>", baseURL: e).text
        for k in 1...5 { precondition(stories.contains("Story \(k)"), "Story \(k) missing") }
        precondition(!stories.contains("Menu"))
        // a main that never closes is read as text around its article
        precondition(LookupText.page(fromHTML: "<body><main>Intro " + story(1) + "</body>", baseURL: e).text.contains("Story 1"))
        // many articles: each is paired with its own closing tag in one pass, not one pass to the end per article
        let long = "<body><main>" + (1...600).map(story).joined() + "</main></body>"
        precondition(long.utf8.count > 1_300_000)
        let tookLong = seconds { _ = LookupText.page(fromHTML: long, baseURL: e) }
        precondition(tookLong < 1, "600 articles took \(tookLong) s")
        let tookMany = seconds { _ = LookupText.page(fromHTML: "<body>" + String(repeating: story(0), count: 600) + "</body>", baseURL: e) }
        precondition(tookMany < 1, "600 sibling articles took \(tookMany) s")
        // an element left open is read as text, as before
        precondition(LookupText.page(fromHTML: "<body><nav>Menu<p>Kept text</p>", baseURL: e).text == "Menu\nKept text")
        precondition(LookupText.page(fromHTML: "<title>Never closed", baseURL: e).title == nil)
        // elements are matched whatever their case or attributes
        precondition(LookupText.page(fromHTML: "<BODY><SCRIPT type=\"x\">no</SCRIPT><Nav class=\"a\">no</NAV>Yes<navigation>kept</navigation></BODY>", baseURL: e).text == "Yes kept")
    }
}
