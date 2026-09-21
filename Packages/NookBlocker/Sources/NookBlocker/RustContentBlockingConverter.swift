// Licensed under GPL-3.0. See LICENSE.
//
//  RustContentBlockingConverter.swift
//  Nook
//
//  Converts ABP/uBlock filter rules into WKContentRuleList JSON via
//  adblock-rust (MPL-2.0). Replaces AdGuard's SafariConverterLib, which is
//  GPL-3.0 and so cannot carry Nook's App Store exception.
//
//  Foundation only; nothing here is AppKit-specific.
//

import Foundation
import NookAdblockFFI
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

enum RustContentBlockingConverter {

    struct Output {
        let entries: [[String: Any]]
        let ruleCount: Int
        /// Lines skipped on purpose: cosmetic exceptions and `$badfilter`, which
        /// cancel other rules and have no standalone content-blocking form.
        let skippedCount: Int
        /// Lines with no Safari equivalent. Not lost: procedural cosmetic filters
        /// are answered per-URL by BlockerEngine, and `$removeparam` by
        /// TrackingParamStripper.
        let unconvertedCount: Int
    }

    /// Convert filter rules to WKContentRuleList entries.
    /// Safe to call off the main actor; holds no shared state.
    nonisolated static func convert(rules: [String]) -> Output {
        var text = rules.joined(separator: "\n")
        var ruleCount = 0
        var skipped = 0
        var unconverted = 0

        // Pass the byte count, not strlen: a NUL in one list would otherwise
        // cut off every list after it.
        let json: String? = text.withUTF8 { buf -> String? in
            guard let raw = nook_adblock_convert_to_content_blocking(
                UnsafeRawPointer(buf.baseAddress)?.assumingMemoryBound(to: CChar.self), buf.count,
                &ruleCount, &skipped, &unconverted
            ) else { return nil }
            defer { nook_adblock_string_free(raw) }
            return String(cString: raw)
        }

        guard let json, let data = json.data(using: .utf8) else {
            log.error("adblock-rust conversion returned nothing")
            return Output(entries: [], ruleCount: 0, skippedCount: 0, unconvertedCount: rules.count)
        }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            log.error("adblock-rust conversion produced unparseable JSON")
            return Output(entries: [], ruleCount: 0, skippedCount: 0, unconvertedCount: rules.count)
        }
        return Output(entries: entries, ruleCount: ruleCount,
                      skippedCount: skipped, unconvertedCount: unconverted)
    }
}
