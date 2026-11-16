// Licensed under GPL-3.0. See LICENSE.
//
//  LookupSearchCheck.swift
//  Nook
//
//  What Look It Up reads from a results page and which results it picks. NookWeb has no test
//  target, so this compiles the source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Lookup/LookupModels.swift \
//           Packages/NookWeb/Sources/NookWeb/Lookup/LookupText.swift \
//           Packages/NookWeb/Sources/NookWeb/Lookup/LookupSearch.swift \
//           Packages/NookWeb/Checks/LookupSearchCheck.swift -o /tmp/lookup-search && /tmp/lookup-search
//

import Foundation

@main
struct LookupSearchCheck {
    static func main() {
        // Two rows copied from the live markup, 2026-11-15.
        let organic = #"<div class="result results_links results_links_deep web-result "> <h2 class="result__title"> <a rel="nofollow" class="result__a" href="https://www.ibisik.com/vision-pro-glasses-review/">Vision Pro Review: Here&#x27;s What I Found</a> </h2> <a class="result__snippet" href="https://www.ibisik.com/vision-pro-glasses-review/">I came across <b>Vision</b> <b>Pro</b> glasses</a> <div class="clear"></div>"#
        let ad = #"<div class="result results_links results_links_deep result--ad "> <a rel="nofollow" class="result__a" href="https://duckduckgo.com/y.js?ad_domain=x.com&amp;u3=https%3A%2F%2Fbing.com">Buy Now</a> <a class="result__snippet" href="https://duckduckgo.com/y.js?ad_domain=x.com">Ad text</a> <div class="clear"></div>"#
        let hits = LookupSearch.hits(inHTML: ad + organic)
        precondition(hits.count == 1)
        precondition(hits[0].url.absoluteString == "https://www.ibisik.com/vision-pro-glasses-review/")
        precondition(hits[0].title == "Vision Pro Review: Here's What I Found")
        precondition(hits[0].snippet == "I came across Vision Pro glasses")
        precondition(LookupSearch.hits(inHTML: "").isEmpty && LookupSearch.hits(inHTML: "<html>202</html>").isEmpty)
        precondition(LookupSearch.url(for: "a b&c").absoluteString == "https://html.duckduckgo.com/html/?q=a%20b%26c")
        // a row with no snippet keeps its own text and does not take the next row's
        let bare = #"<div class="result results_links results_links_deep web-result "> <a rel="nofollow" class="result__a" href="https://one.example/">One</a> <div class="clear"></div>"#
        let paired = LookupSearch.hits(inHTML: bare + organic)
        precondition(paired.map(\.title) == ["One", "Vision Pro Review: Here's What I Found"] && paired[0].snippet.isEmpty && paired[1].snippet == "I came across Vision Pro glasses")
        // a results page of unclosed rows is read in a moment
        let started = Date()
        _ = LookupSearch.hits(inHTML: String(repeating: #"<a class="result__a" href="https://x.example/">"#, count: 20_000))
        precondition(Date().timeIntervalSince(started) < 2)

        // a form endpoint reads a bare "+" as a space
        precondition(LookupSearch.url(for: "c++ a").absoluteString == "https://html.duckduckgo.com/html/?q=c%2B%2B%20a")
        // http, file and javascript results never come back
        for scheme in ["http://www.ibisik.com", "file:///etc", "javascript:alert(1)//"] {
            precondition(LookupSearch.hits(inHTML: organic.replacingOccurrences(of: "https://www.ibisik.com", with: scheme)).isEmpty, scheme)
        }

        // One named thing never fans out; a listed request keeps its searches; each search is capped.
        let long = "can you please find me a really good recipe for a soup that i can make this winter"
        precondition(LookupSearch.normalized(["vision pro reviews", "apple vision pro", "Vision Pro Reviews"], request: "vision pro reviews") == ["vision pro reviews"])
        precondition(LookupSearch.normalized(["lilia brooklyn", "llama inn brooklyn", "kings co imperial brooklyn", "brooklyn"], request: "table at lilia, llama inn or kings co imperial").count == 4)
        precondition(LookupSearch.normalized(["a", "A ", "b", "c", "d", "e"], request: "a, b and c").count == 4)
        // one search for a short request: the person's own words, which a search engine reads better than a rewrite
        precondition(LookupSearch.normalized(["soda vs powder", "baking soda", "baking powder"], request: "difference between baking soda and baking powder") == ["difference between baking soda and baking powder"])
        precondition(LookupSearch.normalized(["macbook air m4 vs programming"], request: " macbook air m4 vs macbook pro m4 for programming ") == ["macbook air m4 vs macbook pro m4 for programming"])
        precondition(LookupSearch.normalized(["winter soup recipe"], request: long) == ["winter soup recipe"])
        precondition(LookupSearch.normalized(["lilia"], request: "table at lilia, llama inn or kings co imperial") == ["lilia"], "a listed request keeps the model's searches")
        // something to get done is searched in the model's words, which name the place: the person's
        // own sentence put a venue's booking page sixth, the model's put it first
        precondition(LookupSearch.normalized(["book reservation at lilia"], request: "table for 2 tomorrow at 7pm at lilia", kind: .act) == ["book reservation at lilia"])
        precondition(LookupSearch.normalized(["book reservation at lilia", "lilia menu"], request: "table for 2 tomorrow at 7pm at lilia", kind: .act) == ["book reservation at lilia"])
        precondition(LookupSearch.normalized(["book reservation at lilia"], request: "table for 2 tomorrow at 7pm at lilia", kind: .choose) == ["table for 2 tomorrow at 7pm at lilia"])
        precondition(LookupSearch.normalized([], request: "table for 2 at lilia", kind: .act) == ["table for 2 at lilia"])
        precondition(LookupSearch.normalized(["franklin barbecue", "la barbecue"], request: "franklin barbecue or la barbecue").count == 2)
        precondition(LookupSearch.normalized([], request: "  x  ") == ["x"])
        // the search a request will get unless the plan says act, known before any plan
        precondition(LookupSearch.ownSearch(for: " why is the sky blue ") == "why is the sky blue")
        precondition(LookupSearch.ownSearch(for: "ramen, pho or udon") == nil && LookupSearch.ownSearch(for: "franklin barbecue or la barbecue") == nil)
        precondition(LookupSearch.ownSearch(for: long) == nil && LookupSearch.ownSearch(for: "   ") == nil)
        precondition(LookupSearch.normalized(["  ", ""], request: "x") == ["x"])
        precondition(LookupSearch.normalized([String(repeating: "a", count: 2000)], request: long)[0].count == 200)
        precondition(LookupSearch.normalized([], request: String(repeating: "a", count: 2000))[0].count == 200)

        // pick: a URL once, hosts spread, video and social skipped, limit held
        func hit(_ url: String) -> LookupHit { LookupHit(url: URL(string: url)!, title: url, snippet: "") }
        let first = [hit("https://a.com/1"), hit("https://a.com/2"), hit("https://www.youtube.com/watch?v=1"), hit("https://b.com/1"), hit("https://c.com/1")]
        let second = [hit("https://a.com/1"), hit("https://d.com/1"), hit("https://m.youtube.com/x"), hit("https://e.com/1")]
        let picked = LookupSearch.pick([first, second], limit: 6)
        precondition(picked.count <= 6)
        precondition(Set(picked.map(\.hit.url)).count == picked.count, "a URL is picked once")
        precondition(!picked.contains { $0.hit.url.host?.hasSuffix("youtube.com") == true })
        precondition(picked.filter { $0.search == 0 }.count == 3 && picked.filter { $0.search == 1 }.count == 2)
        precondition(Set(picked.filter { $0.search == 0 }.compactMap(\.hit.url.host)).count == 3, "hosts spread within a search")
        precondition(LookupSearch.pick([first], limit: 6).map(\.hit.url.absoluteString) == ["https://a.com/1", "https://b.com/1", "https://c.com/1"], "one page a host within a search")
        precondition(LookupSearch.pick([first, first, first, first], limit: 6).filter { $0.search == 0 }.count == 1)
        precondition(LookupSearch.pick([], limit: 6).isEmpty)

        // the ordinary results page, read in a reader page when the plain endpoint refuses
        precondition(LookupSearch.pageURL(for: "c++ vs rust & go").absoluteString == "https://duckduckgo.com/?q=c%2B%2B%20vs%20rust%20%26%20go&ia=web")
        let rows = [
            "https://resy.com/cities/new-york-ny/venues/lilia\tBook Lilia\tItalian in Williamsburg",
            "https://duckduckgo.com/y.js?ad=1\tAn ad\t",
            "http://plain.example/\tNot https\tx",
            "javascript:alert(1)\tx\ty",
            "https://lilia.example/\tNo snippet",
            "", "only one field",
            "https://long.example/\t" + String(repeating: "t", count: 900) + "\ts",
        ].joined(separator: "\n")
        let read = LookupSearch.hits(inRows: rows)
        precondition(read.map(\.url.absoluteString) == ["https://resy.com/cities/new-york-ny/venues/lilia", "https://lilia.example/", "https://long.example/"])
        precondition(read[0].title == "Book Lilia" && read[0].snippet == "Italian in Williamsburg" && read[1].snippet.isEmpty)
        precondition(read[2].title.count == 300, "a title is cut, whatever the page sent")
        precondition(LookupSearch.hits(inRows: "").isEmpty)
        // rows are read only off that page: a "!w" in the request sends its address to another site
        precondition(LookupSearch.isResultsPage(LookupSearch.pageURL(for: "x")))
        for elsewhere in ["https://en.wikipedia.org/wiki/Swift", "https://duckduckgo.com.evil.example/?q=x", "http://duckduckgo.com/?q=x",
                          "https://evil.example/duckduckgo.com/?q=x", "https://html.duckduckgo.com/html/?q=x"] {
            precondition(!LookupSearch.isResultsPage(URL(string: elsewhere)), elsewhere)
        }
        precondition(!LookupSearch.isResultsPage(nil))
    }
}
