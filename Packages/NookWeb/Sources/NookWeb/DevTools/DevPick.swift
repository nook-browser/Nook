// Licensed under GPL-3.0. See LICENSE.
//
//  DevPick.swift
//  Nook
//
//  What the element picker hands an agent: the picked element, or a console line or request,
//  as Markdown, plus a screenshot path. Goes to the clipboard and to DevMCP's `selection`.
//

import CoreGraphics
import Foundation

/// The current handoff for a page; DevMCP `selection` returns it.
public struct DevPick {
    public var markdown: String
    public var imagePath: String?
    public var date = Date()

    public init(markdown: String, imagePath: String? = nil) {
        self.markdown = markdown
        self.imagePath = imagePath
    }
}

/// One picked element, parsed from the picker's message plus page-world framework hints.
public struct DevPickedElement {
    public var url: String
    public var selector: String
    public var tag: String
    public var role: String?
    public var name: String?
    /// Viewport coordinates in CSS pixels.
    public var rect: CGRect
    public var html: String
    public var styles: [(String, String)]
    public var source: String?
    public var components: [String] = []

    /// Nil unless the body has the picker's shape.
    public init?(message body: Any) {
        guard let m = body as? [String: Any],
              let url = m["url"] as? String, let selector = m["selector"] as? String,
              let tag = m["tag"] as? String, let r = m["rect"] as? [String: Any] else { return nil }
        func num(_ k: String) -> Double { (r[k] as? NSNumber)?.doubleValue ?? 0 }
        self.url = url
        self.selector = selector
        self.tag = tag
        self.role = (m["role"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.name = (m["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.rect = CGRect(x: num("x"), y: num("y"), width: num("w"), height: num("h"))
        self.html = m["html"] as? String ?? ""
        self.styles = (m["styles"] as? [[String]] ?? []).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        self.source = m["source"] as? String
    }

    /// Merges what only the page world can see: React and Vue component names, source location.
    public mutating func apply(hints: Any?) {
        guard let h = hints as? [String: Any] else { return }
        if source == nil, let s = h["source"] as? String, !s.isEmpty { source = s }
        // Production builds minify names to one or two characters, which tell an agent nothing.
        if let names = h["react"] as? [String] ?? h["vue"] as? [String] {
            components = names.filter { $0.count >= 3 && $0.first?.isUppercase == true }.reversed()
        }
    }
}

public enum DevHandoff {
    public static func markdown(
        element e: DevPickedElement,
        errors: [DevConsoleEntry],
        failed: [DevNetworkEntry],
        imagePath: String?
    ) -> String {
        var lines = ["## Element `\(e.selector)`", "", "- Page: \(e.url)", "- Selector: `\(e.selector)`"]
        if let role = e.role {
            lines.append("- Role: \(role)" + (e.name.map { " \"\(oneLine($0, 120))\"" } ?? ""))
        } else if let name = e.name {
            lines.append("- Text: \"\(oneLine(name, 120))\"")
        }
        lines.append("- Box: \(Int(e.rect.width))×\(Int(e.rect.height)) at (\(Int(e.rect.minX)), \(Int(e.rect.minY))) in the viewport")
        if let source = e.source { lines.append("- Source: `\(source)`") }
        if !e.components.isEmpty { lines.append("- Components: " + e.components.joined(separator: " > ")) }
        if let imagePath { lines.append("- Screenshot: \(imagePath)") }
        lines += ["", "### HTML", "", "```html", e.html, "```"]
        if !e.styles.isEmpty {
            lines += ["", "### Styles that differ from the defaults", "", "```css"]
            lines += e.styles.map { "\($0.0): \($0.1);" }
            lines.append("```")
        }
        lines += context(errors: errors, failed: failed)
        return lines.joined(separator: "\n")
    }

    public static func markdown(console e: DevConsoleEntry, pageURL: String?) -> String {
        var lines = ["## Console \(e.level) on \(pageURL ?? "page")", "", "```", e.message, "```"]
        if let at = e.location { lines.append("- At: `\(at)`") }
        if let frame = e.frameURL { lines.append("- Frame: \(frame)") }
        if e.repeatCount > 1 { lines.append("- Repeated \(e.repeatCount) times") }
        return lines.joined(separator: "\n")
    }

    public static func markdown(network e: DevNetworkEntry, pageURL: String?) -> String {
        let status = e.error ?? e.status.map(String.init) ?? e.state.rawValue
        var lines = ["## Request on \(pageURL ?? "page")", "", "- \(e.method) \(e.url)", "- Result: \(status)", "- Kind: \(e.kind)"]
        if let ms = e.duration { lines.append("- Time: \(Int(ms.rounded())) ms") }
        if e.hasDetail {
            lines += ["", "```sh", e.curl, "```"]
            if let body = e.responseBody, !body.isEmpty {
                lines += ["", "### Response", "", "```", String(body.prefix(4_000)), "```"]
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The page's last 20 errors and every failed request, so the agent sees what went wrong around the element.
    static func context(errors: [DevConsoleEntry], failed: [DevNetworkEntry]) -> [String] {
        var lines: [String] = []
        if !errors.isEmpty {
            lines += ["", "### Console errors"]
            lines += errors.suffix(20).map { e in
                "- \(e.level): \(oneLine(e.message, 300))" + (e.location.map { " (\($0))" } ?? "")
            }
        }
        if !failed.isEmpty {
            lines += ["", "### Failed requests"]
            lines += failed.map { "- \($0.error ?? $0.status.map(String.init) ?? "failed") \($0.method) \($0.url)" }
        }
        return lines
    }

    /// Lines removed and added between two snapshots, so a polling agent reads only the change.
    public static func snapshotDiff(old: String, new: String) -> String {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false)
        let changes = b.difference(from: a)
        guard !changes.isEmpty else { return "No change since the last snapshot." }
        var lines = ["\(changes.removals.count) lines removed, \(changes.insertions.count) added since the last snapshot:"]
        for case let .remove(_, line, _) in changes.removals { lines.append("-" + line) }
        for case let .insert(_, line, _) in changes.insertions { lines.append("+" + line) }
        return lines.joined(separator: "\n")
    }

    static func oneLine(_ s: String, _ limit: Int) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
