// Licensed under GPL-3.0. See LICENSE.
//
//  LookupText.swift
//  NookWeb
//
//  The text Look It Up reads from a page: from fetched HTML, and from a reader page's innerText.
//  Foundation only, so `Checks/LookupTextCheck.swift` can compile it.
//  ponytail: a scan over the source, not a parser; a page that builds its text in script comes
//  back thin and is read in a reader page instead. Every scan moves forward only, so a tag
//  that never closes costs one pass (as regular expressions these took seconds on 300 KB).
//

import Foundation

public enum LookupText {
    /// Fewer characters than this and a fetched page counts as unread.
    public static let thin = 800

    private static let maxHTML = 1_500_000
    /// How far into a page its title and meta tags are looked for.
    private static let maxHead = 200_000
    private static let maxFragment = 2_000
    private static let dropped = ["head", "script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe"]
    /// Elements that start and end on their own line.
    private static let blocks: Set<String> = ["p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "div", "tr", "section", "blockquote", "dd", "dt", "ul", "ol", "table"]

    // MARK: - Fetched HTML

    public static func page(fromHTML html: String, baseURL: URL) -> (title: String?, image: URL?, text: String) {
        let source = String(html.prefix(maxHTML)) as NSString
        let head = source.substring(to: min(source.length, maxHead)) as NSString
        let title = elements(["title"], in: head, first: true).first.map(plain)
        return (title?.isEmpty == false ? title : nil, image(in: head, baseURL: baseURL), text(in: source))
    }

    /// The article or main element when it holds real text, else the body; lists and headings kept.
    private static func text(in source: NSString) -> String {
        var body = source
        for tag in dropped { body = removing(tag, from: body) }
        if let main = elements(["article", "main"], in: body, first: false).max(by: { $0.count < $1.count }), main.count > 2000 {
            body = main as NSString
        }
        return tidy(innerText: decoded(withoutTags(body, blockBreaks: true)))
    }

    /// The page's `og:image`, https only.
    private static func image(in head: NSString, baseURL: URL) -> URL? {
        var cursor = 0
        while let open = find("<meta", in: head, from: cursor), let close = find(">", in: head, from: open.upperBound) {
            cursor = close.upperBound
            let tag = head.substring(with: NSRange(location: open.lowerBound, length: min(close.upperBound - open.lowerBound, maxFragment)))
            guard tag.range(of: #"property\s*=\s*["']og:image["']"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let content = tag.range(of: #"content\s*=\s*["'][^"']+["']"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let quoted = tag[content].drop { $0 != "\"" && $0 != "'" }.dropFirst().dropLast()
            guard let url = URL(string: decoded(String(quoted)), relativeTo: baseURL)?.absoluteURL, url.scheme?.lowercased() == "https" else { return nil }
            return url
        }
        return nil
    }

    // MARK: - Fragments

    /// A title or snippet as one line of plain text.
    public static func plain(_ fragment: String) -> String {
        let text = decoded(withoutTags(String(fragment.prefix(maxFragment * 4)) as NSString, blockBreaks: false))
        return String(text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").prefix(maxFragment))
    }

    /// A web view's innerText with its line breaks kept: a list of times stays a list.
    public static func tidy(innerText: String) -> String {
        innerText.components(separatedBy: .newlines)
            .map { $0.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func excerpt(_ text: String, characters: Int) -> String {
        String(text.prefix(characters))
    }

    // MARK: - Scanning

    /// Where `needle` next occurs at or after `from`, case-insensitive.
    private static func find(_ needle: String, in text: NSString, from: Int) -> Range<Int>? {
        guard from < text.length else { return nil }
        let found = text.range(of: needle, options: .caseInsensitive, range: NSRange(location: from, length: text.length - from))
        return found.location == NSNotFound ? nil : found.location..<(found.location + found.length)
    }

    /// The next opening tag of `name` at or after `from`: `<name` followed by a space, `>` or `/`.
    private static func opening(_ name: String, in text: NSString, from: Int) -> Range<Int>? {
        var cursor = from
        while let found = find("<" + name, in: text, from: cursor) {
            guard found.upperBound < text.length else { return nil }
            let next = text.character(at: found.upperBound)
            if next == 0x3E || next == 0x2F || next == 0x20 || next == 0x0A || next == 0x09 || next == 0x0D { return found }
            cursor = found.upperBound
        }
        return nil
    }

    /// `text` without every closed `name` element. One left open stays, as text.
    private static func removing(_ name: String, from text: NSString) -> NSString {
        let out = NSMutableString()
        var cursor = 0
        while let open = opening(name, in: text, from: cursor), let close = find("</\(name)>", in: text, from: open.upperBound) {
            out.append(text.substring(with: NSRange(location: cursor, length: open.lowerBound - cursor)))
            out.append(" ")
            cursor = close.upperBound
        }
        guard cursor > 0 else { return text }
        out.append(text.substring(from: cursor))
        return out
    }

    /// What sits inside each closed element named in `names`, in page order.
    private static func elements(_ names: [String], in text: NSString, first: Bool) -> [String] {
        var found: [String] = []
        var cursor = 0
        while cursor < text.length {
            let opens = names.compactMap { opening($0, in: text, from: cursor) }
            guard let open = opens.min(by: { $0.lowerBound < $1.lowerBound }), let start = find(">", in: text, from: open.upperBound) else { break }
            let closes = names.compactMap { find("</\($0)>", in: text, from: start.upperBound) }
            guard let close = closes.min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            found.append(text.substring(with: NSRange(location: start.upperBound, length: close.lowerBound - start.upperBound)))
            if first { break }
            cursor = close.upperBound
        }
        return found
    }

    /// `text` with its tags gone. With `blockBreaks`, a block element's tags and a `<br>` become
    /// a line break and any other tag a space.
    private static func withoutTags(_ text: NSString, blockBreaks: Bool) -> String {
        let out = NSMutableString()
        var cursor = 0
        while let open = find("<", in: text, from: cursor) {
            guard let close = find(">", in: text, from: open.upperBound) else { break }
            out.append(text.substring(with: NSRange(location: cursor, length: open.lowerBound - cursor)))
            if blockBreaks {
                let inside = text.substring(with: NSRange(location: open.upperBound, length: min(close.lowerBound - open.upperBound, 12))).lowercased()
                let name = String(inside.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber })
                out.append(name == "br" || blocks.contains(name) ? "\n" : " ")
            }
            cursor = close.upperBound
        }
        out.append(text.substring(from: cursor))
        return out as String
    }

    // MARK: - Character References

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "rsquo": "\u{2019}", "lsquo": "\u{2018}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}",
        "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}", "middot": "\u{B7}", "bull": "\u{2022}", "deg": "\u{B0}",
    ]

    /// Named and numeric character references; one it does not know is left as written.
    static func decoded(_ text: String) -> String {
        guard text.contains("&"), let re = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});") else { return text }
        var out = ""
        var last = text.startIndex
        for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[inner])
            let value: String?
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let code = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                value = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                value = named[name]
            }
            out += text[last..<whole.lowerBound]
            out += value ?? String(text[whole])
            last = whole.upperBound
        }
        return out + text[last...]
    }
}
