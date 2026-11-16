// Licensed under GPL-3.0. See LICENSE.
//
//  LookupSearch.swift
//  NookWeb
//
//  The search step of Look It Up: the request URL, the rows read from the results page, and
//  which rows get read. Foundation only, so `Checks/LookupSearchCheck.swift` can compile it.
//  ponytail: DuckDuckGo's HTML endpoint, read by regular expression, then its ordinary page.
//  Neither has a contract; when both change the tab offers an ordinary search.
//

import Foundation

public enum LookupSearch {
    /// Hosts whose pages are video or a feed, which give the model nothing to read.
    public static let skippedHosts = ["youtube.com", "instagram.com", "facebook.com", "tiktok.com", "x.com", "twitter.com", "pinterest.com"]

    /// The most searches one lookup sends, whatever they are for.
    public static let maxSearches = 4
    private static let maxSearchLength = 200
    private static let maxOwnWords = 12
    /// One row of a results page is a title, an address and a snippet: a few hundred characters.
    private static let maxRow = 6_000
    /// A request that lists things may run a search for each. "and" and "vs" are left out: they
    /// join the two halves of one comparison more often than they separate two things.
    private static let listMarks = [",", " or "]

    private static let maxTitle = 300
    private static let maxSnippet = 500

    public static func url(for query: String) -> URL {
        address("https://html.duckduckgo.com/html/", [URLQueryItem(name: "q", value: query)])
    }

    /// The same search as the page a person sees. A reader page loads it when the plain endpoint
    /// has nothing: that endpoint refuses a whole address for a long while, and this page does not.
    public static func pageURL(for query: String) -> URL {
        address("https://duckduckgo.com/", [URLQueryItem(name: "q", value: query), URLQueryItem(name: "ia", value: "web")])
    }

    /// True while a page that loaded `pageURL(for:)` is still that results page.
    public static func isResultsPage(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.lowercased() == "duckduckgo.com"
    }

    private static func address(_ base: String, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = items
        // URLComponents leaves "+" as written, and a form endpoint reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// The rows a reader page read off the results page (`PageSession.readSearchRows`): a line a
    /// row, its address, title and snippet tab-separated.
    public static func hits(inRows rows: String) -> [LookupHit] {
        rows.split(separator: "\n").compactMap { row in
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { return nil }
            return hit(address: fields[0], title: fields[1], snippet: fields.count > 2 ? fields[2] : "")
        }
    }

    /// A row worth reading: https, and not a link through the search engine itself, which is an ad.
    private static func hit(address: String, title: String, snippet: String) -> LookupHit? {
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host != "duckduckgo.com", !host.hasSuffix(".duckduckgo.com") else { return nil }
        return LookupHit(url: url, title: String(title.prefix(maxTitle)), snippet: String(snippet.prefix(maxSnippet)))
    }

    /// The organic rows of a results page. Ads link through duckduckgo.com and are dropped, as is
    /// anything that is not https. A row runs from its title link to the next row's, so a row
    /// with no snippet cannot take its neighbour's.
    public static func hits(inHTML html: String) -> [LookupHit] {
        let text = html as NSString
        let marker = #"class="result__a""#
        var starts: [Int] = []
        var cursor = 0
        while cursor < text.length {
            let found = text.range(of: marker, options: [], range: NSRange(location: cursor, length: text.length - cursor))
            guard found.location != NSNotFound else { break }
            starts.append(found.location)
            cursor = found.location + found.length
        }
        return starts.enumerated().compactMap { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : text.length
            let row = text.substring(with: NSRange(location: start, length: min(end - start, maxRow)))
            guard let link = groups(#"^class="result__a"[^>]*?href="([^"]+)"[^>]*>(.*?)</a>"#, in: row), link.count == 2 else { return nil }
            let snippet = groups(#"class="result__snippet"[^>]*>(.*?)</a>"#, in: row)?.first ?? ""
            return hit(address: LookupText.plain(link[0]), title: LookupText.plain(link[1]), snippet: LookupText.plain(snippet))
        }
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func clean(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSearchLength))
    }

    private static func lists(_ request: String) -> Bool {
        listMarks.contains { request.lowercased().contains($0) }
    }

    /// The request as its own search: short and listing nothing. It is what gets searched unless
    /// the plan says act, so it can start before the plan is back.
    public static func ownSearch(for request: String) -> String? {
        let own = clean(request)
        return !lists(request) && !own.isEmpty && own.split(whereSeparator: \.isWhitespace).count <= maxOwnWords ? own : nil
    }

    /// The model's searches made safe to run: trimmed, no repeats, at most four, and only one
    /// unless the request itself lists things.
    public static func normalized(_ searches: [String], request: String, kind: LookupKind = .explain) -> [String] {
        var seen = Set<String>()
        var out = searches.map(clean).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        // The request itself is the search when the model gave none.
        if out.isEmpty { out = [clean(request)].filter { !$0.isEmpty } }
        // One search for a short request is the person's own words: a search engine reads them
        // better than the model's rewrite, which drops half of a comparison. Something to get done
        // is the exception: the model's search names the place, and finds its booking page first.
        if kind != .act, let own = ownSearch(for: request) { return [own] }
        return Array(out.prefix(lists(request) ? maxSearches : 1))
    }

    /// Which rows to read: `limit` shared evenly between the searches, a URL once, one page a
    /// host within a search.
    public static func pick(_ hitsBySearch: [[LookupHit]], limit: Int) -> [(hit: LookupHit, search: Int)] {
        guard !hitsBySearch.isEmpty else { return [] }
        let perSearch = max(1, limit / hitsBySearch.count)
        var urls = Set<URL>()
        var picked: [(hit: LookupHit, search: Int)] = []
        for (index, hits) in hitsBySearch.enumerated() {
            var hosts = Set<String>()
            var taken = 0
            for hit in hits where taken < perSearch && picked.count < limit {
                guard let host = hit.url.host?.lowercased(),
                      !skippedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
                      !urls.contains(hit.url), hosts.insert(host).inserted else { continue }
                urls.insert(hit.url)
                picked.append((hit, index))
                taken += 1
            }
        }
        return picked
    }
}
