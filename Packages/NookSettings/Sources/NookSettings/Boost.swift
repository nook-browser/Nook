// Licensed under GPL-3.0. See LICENSE.
//
//  Boost.swift
//  Nook
//

import Foundation

/// A per-site style (and optional script) the user made. Contract: docs/boost-contract.md (local).
public struct Boost: Codable, Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maxCSSBytes = 64 * 1024
    public static let maxScriptBytes = 64 * 1024
    public static let maxCount = 200

    public enum TextCase: String, Codable, CaseIterable, Sendable {
        case none, uppercase, lowercase, capitalize
    }

    public var id: UUID
    public var name: String
    /// Normalized host, no scheme, path or `www.`.
    public var host: String
    public var includeSubdomains: Bool
    public var isEnabled: Bool
    public var brightness: Double
    public var contrast: Double
    /// `#RRGGBB`, or empty for no tint. Blended over the page with `tintStrength`.
    public var tint: String
    public var tintStrength: Double
    /// Dark page: the page inverted to dark by a layer over it, its photos and videos inverted back.
    public var darkPage: Bool
    public var fontFamily: String
    public var fontScale: Double
    public var textCase: TextCase
    public var css: String
    /// Selectors hidden by Zap. Also compiled as `host##selector` into the user cosmetic rule list.
    public var zaps: [String]
    public var script: String
    /// Off by default and forced off on import: a script is code the user must choose to run.
    public var scriptEnabled: Bool
    public var updated: Date

    public static let brightnessRange = 0.5...1.5
    public static let contrastRange = 0.5...1.5
    public static let fontScaleRange = 0.8...2.0
    public static let tintStrengthRange = 0.05...0.8

    public init(
        id: UUID = UUID(), name: String = "", host: String, includeSubdomains: Bool = true, isEnabled: Bool = true,
        brightness: Double = 1, contrast: Double = 1, tint: String = "", tintStrength: Double = 0.35,
        darkPage: Bool = false, fontFamily: String = "", fontScale: Double = 1,
        textCase: TextCase = .none, css: String = "", zaps: [String] = [], script: String = "", scriptEnabled: Bool = false,
        updated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.includeSubdomains = includeSubdomains
        self.isEnabled = isEnabled
        self.brightness = brightness
        self.contrast = contrast
        self.tint = tint
        self.tintStrength = tintStrength
        self.darkPage = darkPage
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.textCase = textCase
        self.css = css
        self.zaps = zaps
        self.script = script
        self.scriptEnabled = scriptEnabled
        self.updated = updated
    }

    // A field added later, or a hand-edited file missing one, must not lose the whole Boost.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            host: try c.decode(String.self, forKey: .host),
            includeSubdomains: try c.decodeIfPresent(Bool.self, forKey: .includeSubdomains) ?? true,
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            brightness: try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1,
            tint: try c.decodeIfPresent(String.self, forKey: .tint) ?? "",
            tintStrength: try c.decodeIfPresent(Double.self, forKey: .tintStrength) ?? 0.35,
            darkPage: try c.decodeIfPresent(Bool.self, forKey: .darkPage) ?? false,
            fontFamily: try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? "",
            fontScale: try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1,
            textCase: (try? c.decodeIfPresent(TextCase.self, forKey: .textCase)) ?? .none,
            css: try c.decodeIfPresent(String.self, forKey: .css) ?? "",
            zaps: try c.decodeIfPresent([String].self, forKey: .zaps) ?? [],
            script: try c.decodeIfPresent(String.self, forKey: .script) ?? "",
            scriptEnabled: try c.decodeIfPresent(Bool.self, forKey: .scriptEnabled) ?? false,
            updated: try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
        )
    }

    // MARK: - Host

    /// "https://www.Example.com/x" -> "example.com". Empty when the result could match too much:
    /// no dot (a bare "com"), a wildcard, or characters a hostname cannot hold.
    public static func normalizeHost(_ input: String) -> String {
        let host = SiteRoutingRule.normalizeDomain(input)
        let ok = host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
            && host.unicodeScalars.allSatisfy { $0.value > 127 || CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "." }
        return ok ? host : ""
    }

    // MARK: - Matching

    /// http(s) pages only. Same host, or a subdomain of it when `includeSubdomains`.
    public func matches(_ url: URL) -> Bool {
        guard isEnabled, !host.isEmpty, url.scheme == "http" || url.scheme == "https",
              let pageHost = url.host?.lowercased()
        else { return false }
        return pageHost == host || (includeSubdomains && pageHost.hasSuffix("." + host))
    }

    /// The stylesheet for a page: every matching Boost's CSS, joined.
    public static func css(for url: URL, in boosts: [Boost]) -> String {
        matching(url, in: boosts).map(\.compiledCSS).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Every match, in list order, so overlapping Boosts stack the same way every time.
    public static func matching(_ url: URL, in boosts: [Boost]) -> [Boost] {
        boosts.filter { $0.matches(url) }
    }

    // MARK: - CSS

    /// Visual controls first, the user's own CSS last so it can override them.
    public var compiledCSS: String {
        var rules: [String] = []
        // No filter goes on the root element (it would make every fixed element position against
        // the page). A fixed layer over the page filters what is painted under it instead.
        var filters: [String] = []
        if darkPage { filters.append("invert(1) hue-rotate(180deg)") }
        if brightness != 1 { filters.append("brightness(\(Self.num(brightness)))") }
        if contrast != 1 { filters.append("contrast(\(Self.num(contrast)))") }
        if !filters.isEmpty {
            let f = filters.joined(separator: " ")
            // The backdrop layer costs a compositing pass while the boosted page scrolls; it is opt-in per site.
            // !important keeps a site's own html::before rule from breaking it.
            rules.append("html::before { content: \"\" !important; display: block !important; position: fixed !important; inset: 0 !important; pointer-events: none !important; z-index: 2147483646 !important; -webkit-backdrop-filter: \(f); backdrop-filter: \(f); }")
        }
        if darkPage {
            // A page with no background of its own shows the canvas; give the layer a color to turn dark.
            // Zero specificity, so any background the site sets still wins.
            rules.append(":where(html) { background-color: #fff; }")
            // Pictures turned back the right way round, except where they sit above the layer
            // (full screen, modal dialogs, popovers) and were never inverted.
            rules.append(":is(img, video, picture, canvas, iframe, embed, object, svg image):not(:fullscreen, :fullscreen *, dialog[open] *, :popover-open *) { filter: invert(1) hue-rotate(180deg) !important; }")
        }
        if Self.isHexColor(tint) {
            // A fixed layer that colours what is under it and takes no clicks.
            let strength = Self.num(min(max(tintStrength, Self.tintStrengthRange.lowerBound), Self.tintStrengthRange.upperBound))
            rules.append("html::after { content: \"\"; position: fixed; inset: 0; pointer-events: none; z-index: 2147483647; background: \(tint); mix-blend-mode: color; opacity: \(strength); }")
        }
        let text = "p, span, a, li, h1, h2, h3, h4, h5, h6, td, th, label, button, input, textarea, blockquote"
        let font = Self.safeFont(fontFamily)
        if !font.isEmpty {
            rules.append("html, body, \(text) { font-family: \(font) !important; }")
        }
        if fontScale != 1 {
            rules.append("html { font-size: \(String(format: "%.0f", min(max(fontScale, 0.5), 3) * 100))% !important; }")
        }
        if textCase != .none {
            rules.append("\(text) { text-transform: \(textCase.rawValue) !important; }")
        }
        for selector in zaps where Self.isAllowedZap(selector) {
            rules.append("\(selector) { display: none !important; }")
        }
        let own = Self.removingBaitRules(css)
        if !own.isEmpty { rules.append(own) }
        return rules.joined(separator: "\n")
    }

    /// A zap selector goes into a stylesheet and a filter list: one plain selector, no braces,
    /// no filter syntax. YouTube's ad-block bait (`#player-ads`) is never hidden: hiding it
    /// brings up "Ad blockers are not allowed".
    public static func isAllowedZap(_ selector: String) -> Bool {
        let s = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.utf8.count <= 500, !s.replacingOccurrences(of: "\\", with: "").lowercased().contains("player-ads") else { return false }
        return !s.contains { "{};\n\r\\".contains($0) } && !s.contains("##") && !s.contains("#@#") && !s.contains("#?#")
    }

    /// CSS without the rules that mention YouTube's `player-ads` bait, in any spelling (id, class, attribute value).
    /// ponytail: splits on `}`, so a rule nested in `@media` loses its block but leaves the wrapper unbalanced.
    public static func removingBaitRules(_ css: String) -> String {
        guard css.replacingOccurrences(of: "\\", with: "").lowercased().contains("player-ads") else { return css }
        let parts = css.components(separatedBy: "}")
        let kept = parts.enumerated().compactMap { i, part -> String? in
            if part.replacingOccurrences(of: "\\", with: "").lowercased().contains("player-ads") { return nil }
            return i < parts.count - 1 ? part + "}" : part
        }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The user cosmetic filter lines for these Boosts, one per allowed zap of each enabled Boost.
    public static func zapFilterLines(_ boosts: [Boost]) -> [String] {
        boosts.filter { $0.isEnabled && !$0.host.isEmpty }.flatMap { b in
            b.zaps.filter(isAllowedZap).map { "\(b.host)##\($0)" }
        }
    }

    public static func isHexColor(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static func num(_ v: Double) -> String { String(format: "%.2f", min(max(v, 0), 10)) }

    /// A font list the user typed goes into a stylesheet: keep names, commas and quotes only.
    private static func safeFont(_ s: String) -> String {
        String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || " ,-'\"".unicodeScalars.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Presets

    /// Starter looks. Plain token values the user can edit afterwards, not special cases.
    public enum Preset: String, CaseIterable, Sendable {
        case dimPage = "Dim page"
        case highContrast = "High contrast"
        case largerType = "Larger type"
    }

    public mutating func apply(_ preset: Preset) {
        brightness = 1; contrast = 1; fontScale = 1; tint = ""
        switch preset {
        case .dimPage: brightness = 0.8
        case .highContrast: contrast = 1.3
        case .largerType: fontScale = 1.2
        }
        updated = Date()
    }

    public mutating func resetVisuals() {
        brightness = 1; contrast = 1; tint = ""; darkPage = false; fontFamily = ""; fontScale = 1; textCase = .none
        updated = Date()
    }
}

// MARK: - Import and export

public enum BoostBundle {
    public struct Failure: Error, Equatable { public let message: String }

    private struct File: Codable { var schema: Int; var boosts: [Boost] }
    public static let maxBytes = 2 * 1024 * 1024

    public static func export(_ boosts: [Boost]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(File(schema: Boost.schemaVersion, boosts: boosts))
    }

    /// Imported CSS may not reach the network: no `@import`, no `url(`. Backslashes go too, since
    /// CSS escapes can spell either one.
    public static func stripRemoteCSS(_ css: String) -> String {
        var out = css.replacingOccurrences(of: "\\", with: "")
        for pattern in ["@import[^;{]*;?", "url\\s*\\([^)]*\\)?"] {
            out = out.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    /// Validated, ready to preview. Scripts arrive disabled, ids are new, bad hosts are refused.
    public static func parse(_ data: Data) throws -> [Boost] {
        guard data.count <= maxBytes else { throw Failure(message: "The file is larger than 2 MB.") }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            throw Failure(message: "This is not a Nook Boost file.")
        }
        guard file.schema <= Boost.schemaVersion else {
            throw Failure(message: "This file was made by a newer version of Nook.")
        }
        guard file.boosts.count <= Boost.maxCount else { throw Failure(message: "Too many Boosts in one file.") }
        return try file.boosts.map { b in
            var b = b
            b.host = Boost.normalizeHost(b.host)
            guard !b.host.isEmpty else { throw Failure(message: "A Boost has an invalid site.") }
            guard b.css.utf8.count <= Boost.maxCSSBytes, b.script.utf8.count <= Boost.maxScriptBytes else {
                throw Failure(message: "A Boost's code is too large.")
            }
            b.id = UUID()
            b.scriptEnabled = false
            b.css = Boost.removingBaitRules(stripRemoteCSS(b.css))
            b.zaps = b.zaps.filter(Boost.isAllowedZap)
            return b
        }
    }
}

/// Decodes a list one element at a time, so a single bad Boost on disk drops only itself.
public struct LossyBoosts: Decodable {
    public let boosts: [Boost]
    private struct Slot: Decodable {
        let boost: Boost?
        init(from decoder: Decoder) throws { boost = try? Boost(from: decoder) }
    }
    public init(from decoder: Decoder) throws {
        boosts = try [Slot](from: decoder).compactMap(\.boost)
    }
}
