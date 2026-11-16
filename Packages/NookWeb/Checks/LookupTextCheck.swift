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

        // titles and snippets: tags out, entities decoded, one line
        precondition(LookupText.plain("I came across <b>Vision</b> <b>Pro</b>\n glasses") == "I came across Vision Pro glasses")
        precondition(LookupText.plain("Here&#x27;s &amp; &quot;that&quot;") == "Here's & \"that\"")

        // line breaks survive, runs of spaces and blank lines do not
        precondition(LookupText.tidy(innerText: "Dinner\n\n\n5:00 PM   \t Bar\n9:15 PM\n") == "Dinner\n5:00 PM Bar\n9:15 PM")
        precondition(LookupText.excerpt(String(repeating: "x", count: 9000), characters: 6000).count == 6000)
        precondition(LookupText.excerpt("short", characters: 6000) == "short")
        precondition(LookupText.thin == 800)

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
        // an element left open is read as text, as before
        precondition(LookupText.page(fromHTML: "<body><nav>Menu<p>Kept text</p>", baseURL: e).text == "Menu\nKept text")
        precondition(LookupText.page(fromHTML: "<title>Never closed", baseURL: e).title == nil)
        // elements are matched whatever their case or attributes
        precondition(LookupText.page(fromHTML: "<BODY><SCRIPT type=\"x\">no</SCRIPT><Nav class=\"a\">no</NAV>Yes<navigation>kept</navigation></BODY>", baseURL: e).text == "Yes kept")
    }
}
