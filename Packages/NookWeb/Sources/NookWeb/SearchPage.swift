// Licensed under GPL-3.0. See LICENSE.
//
//  SearchPage.swift
//  NookWeb
//
//  Recognizes a search engine's results page and reads the query out of it.
//

import Foundation

public enum SearchPage {
    /// Engines by host suffix: the results path and the query parameter.
    private static let engines: [(host: String, path: String, parameter: String)] = [
        ("google.", "/search", "q"),
        ("bing.com", "/search", "q"),
        ("duckduckgo.com", "/", "q"),
        ("search.brave.com", "/search", "q"),
        ("kagi.com", "/search", "q"),
        ("ecosia.org", "/search", "q"),
        ("search.yahoo.com", "/search", "p"),
    ]

    /// The query and the site's short name (`google.com`), or nil when `url` is not a results page.
    public static func query(in url: URL) -> (query: String, site: String)? {
        guard let host = url.host?.lowercased(), url.scheme?.hasPrefix("http") == true,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for engine in engines {
            let matchesHost = engine.host.hasSuffix(".")
                ? host.split(separator: ".").contains(Substring(engine.host.dropLast()))
                : host == engine.host || host.hasSuffix("." + engine.host)
            guard matchesHost, url.path == engine.path || (engine.path != "/" && url.path.hasPrefix(engine.path)) else { continue }
            // Forms encode spaces as `+`; a real plus arrives as %2B and survives.
            guard let raw = components.percentEncodedQueryItems?.first(where: { $0.name == engine.parameter })?.value,
                  let query = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return nil }
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return (query, site)
        }
        return nil
    }
}
