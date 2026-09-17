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
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

enum RustContentBlockingConverter {

    struct Output {
        let entries: [[String: Any]]
        let ruleCount: Int
        let errorCount: Int
    }

    /// Convert filter rules to WKContentRuleList entries.
    /// Safe to call off the main actor; holds no shared state.
    nonisolated static func convert(rules: [String]) -> Output {
        let text = rules.joined(separator: "\n")
        var ruleCount = 0
        var errorCount = 0

        let json: String? = text.withCString { ptr -> String? in
            guard let raw = nook_adblock_convert_to_content_blocking(
                ptr, strlen(ptr), &ruleCount, &errorCount
            ) else { return nil }
            defer { nook_adblock_string_free(raw) }
            return String(cString: raw)
        }

        guard let json, let data = json.data(using: .utf8) else {
            log.error("adblock-rust conversion returned nothing")
            return Output(entries: [], ruleCount: 0, errorCount: rules.count)
        }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            log.error("adblock-rust conversion produced unparseable JSON")
            return Output(entries: [], ruleCount: 0, errorCount: rules.count)
        }
        return Output(entries: entries, ruleCount: ruleCount, errorCount: errorCount)
    }
}
