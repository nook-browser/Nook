// Licensed under GPL-3.0. See LICENSE.
//
//  URLSkipper.swift
//  Nook
//
//  uBlock Origin's `urlskip=`: a navigation to a known redirector goes straight to the URL it
//  carries. Matching and the extraction steps run in adblock-rust (urlskip_ffi.rs); this holds
//  the handle. Applied beside $removeparam in PageSession.decidePolicyFor.
//
//  Foundation only; nothing here is AppKit-specific.
//

import Foundation
import NookAdblockFFI

/// Built off the main actor, then used only on it: the engine inside is Send but not Sync.
final class URLSkipper: @unchecked Sendable {
    private let skipper: UnsafeMutableRawPointer?
    let ruleCount: Int

    init(rules lines: [String]) {
        var text = lines.filter { $0.contains("urlskip=") }.joined(separator: "\n")
        var count = 0
        skipper = text.withUTF8 { buf in
            nook_adblock_urlskip_new(
                UnsafeRawPointer(buf.baseAddress)?.assumingMemoryBound(to: CChar.self), buf.count, &count)
        }
        ruleCount = count
    }

    deinit { nook_adblock_urlskip_free(skipper) }

    /// Where a navigation to `url` from a page at `source` should go instead, or nil.
    func target(for url: URL, from source: URL?) -> URL? {
        guard let skipper, Self.isWeb(url) else { return nil }
        let from = source.flatMap { Self.isWeb($0) ? $0 : nil } ?? url
        guard let raw = nook_adblock_urlskip_target(skipper, url.absoluteString, from.absoluteString) else { return nil }
        defer { nook_adblock_string_free(raw) }
        return URL(string: String(cString: raw))
    }

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
    }
}
