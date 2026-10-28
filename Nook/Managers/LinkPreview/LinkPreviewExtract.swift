// Licensed under GPL-3.0. See LICENSE.
//
//  LinkPreviewExtract.swift
//  Nook
//
//  What a link preview reads from a page's HTML: title, description, lead image and body
//  text. Foundation only, so `scripts/tests/LinkPreviewExtractCheck.swift` can compile it.
//  ponytail: regular expressions over the source, not a parser; pages that render their text
//  in script show only their title and description.
//

import Foundation

struct LinkPreviewPage: Equatable {
    var title: String?
    var description: String?
    var imageURL: URL?
    /// The site's own name (`og:site_name`), for the shared card's footer.
    var siteName: String? = nil
    /// Where the link landed after redirects (a search result's link goes through the engine
    /// first); the card names this site, not the redirector.
    var landedURL: URL? = nil
    /// Paragraph text, at most `LinkPreviewExtract.maxText` characters, for the summary.
    var text: String
}

enum LinkPreviewExtract {
    static let maxText = 2500

    static func page(fromHTML html: String, baseURL: URL) -> LinkPreviewPage {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.upperBound]) } ?? String(html.prefix(60_000))
        let title = meta(head, "og:title") ?? firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: head).map(clean)
        let description = meta(head, "og:description") ?? meta(head, "description")
        let image = (meta(head, "og:image") ?? meta(head, "twitter:image")).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }

        let body = html.replacingOccurrences(of: #"<(script|style|noscript|svg|nav|footer|header)\b[\s\S]*?</\1>"#, with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        var text = ""
        for paragraph in allMatches(#"<p\b[^>]*>([\s\S]*?)</p>"#, in: body) {
            let line = clean(paragraph)
            // Short paragraphs are bylines, captions and buttons.
            guard line.count >= 40 else { continue }
            text += line + "\n"
            if text.count >= maxText { break }
        }
        return LinkPreviewPage(
            title: title.flatMap { $0.isEmpty ? nil : $0 },
            description: description.flatMap { $0.isEmpty ? nil : $0 },
            imageURL: image.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil },
            siteName: meta(head, "og:site_name").flatMap { $0.isEmpty ? nil : $0 },
            text: String(text.prefix(maxText)))
    }

    /// A `<meta>` tag's content by `property` or `name`, in either attribute order.
    private static func meta(_ head: String, _ key: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta[^>]+(?:property|name)\s*=\s*["']"# + escaped + #"["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']"# + escaped + #"["']"#,
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern, in: head) { return clean(value) }
        }
        return nil
    }

    /// Tags out, entities decoded, whitespace collapsed.
    static func clean(_ fragment: String) -> String {
        var text = fragment.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
                                    ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
                                    ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&hellip;", "…")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text, limit: 1).first
    }

    private static func allMatches(_ pattern: String, in text: String, limit: Int = .max) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var results: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            if let match, match.numberOfRanges > 1, let r = Range(match.range(at: match.numberOfRanges - 1), in: text) {
                results.append(String(text[r]))
            }
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }
}
