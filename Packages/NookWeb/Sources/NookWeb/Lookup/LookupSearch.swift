// Licensed under GPL-3.0. See LICENSE.
//
//  LookupSearch.swift
//  NookWeb
//
//  The search step of Look It Up: the request URL, the rows read from the results page, and
//  which rows get read. Foundation only, so `Checks/LookupSearchCheck.swift` can compile it.
//  ponytail: DuckDuckGo's HTML endpoint, read by regular expression. It has no contract; when
//  the markup changes this returns nothing and the tab offers an ordinary search.
//

import Foundation

public enum LookupSearch {
    /// Hosts whose pages are video or a feed, which give the model nothing to read.
    public static let skippedHosts = ["youtube.com", "instagram.com", "facebook.com", "tiktok.com", "x.com", "twitter.com", "pinterest.com"]

    private static let maxSearches = 4
    private static let maxSearchLength = 200
    private static let maxOwnWords = 12
    /// One row of a results page is a title, an address and a snippet: a few hundred characters.
    private static let maxRow = 6_000
    /// A request that lists things may run a search for each. "and" and "vs" are left out: they
    /// join the two halves of one comparison more often than they separate two things.
    private static let listMarks = [",", " or "]

    public static func url(for query: String) -> URL {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // URLComponents leaves "+" as written, and a form endpoint reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
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
            guard let link = groups(#"^class="result__a"[^>]*?href="([^"]+)"[^>]*>(.*?)</a>"#, in: row), link.count == 2,
                  let url = URL(string: LookupText.plain(link[0])), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), host != "duckduckgo.com", !host.hasSuffix(".duckduckgo.com") else { return nil }
            let snippet = groups(#"class="result__snippet"[^>]*>(.*?)</a>"#, in: row)?.first ?? ""
            return LookupHit(url: url, title: LookupText.plain(link[1]), snippet: LookupText.plain(snippet))
        }
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    /// The model's searches made safe to run: trimmed, no repeats, at most four, and only one
    /// unless the request itself lists things.
    public static func normalized(_ searches: [String], request: String) -> [String] {
        func clean(_ text: String) -> String {
            String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSearchLength))
        }
        var seen = Set<String>()
        var out = searches.map(clean).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        // The request itself is the search when the model gave none.
        if out.isEmpty { out = [clean(request)].filter { !$0.isEmpty } }
        let lists = listMarks.contains { request.lowercased().contains($0) }
        // One search for a short request is the person's own words: a search engine reads them
        // better than the model's rewrite, which drops half of a comparison.
        let own = clean(request)
        if !lists, !own.isEmpty, own.split(whereSeparator: \.isWhitespace).count <= maxOwnWords { return [own] }
        return Array(out.prefix(lists ? maxSearches : 1))
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
