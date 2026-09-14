//
//  RequestStatsEngine.swift
//  Nook
//
//  Counts the requests a page tried to make that the filter lists block, so the UI can show a
//  per-tab number. WebKit's content rule lists do not report matches, so the same lists are also
//  loaded into Brave's adblock-rust (Nook/ThirdParty/AdblockRustFFI, MPL-2.0) and every URL the
//  page-side hook (nook-request-stats.js) observes is checked against it. Counting only; blocking
//  is still done by WKContentRuleList.
//
//  The engine pointer is not thread-safe: every call goes through `queue`.
//

import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "RequestStats")

final class RequestStatsEngine: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.baingurley.nook.request-stats", qos: .utility)
    private var engine: UnsafeMutableRawPointer?

    private static var cacheDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("io.browsewithnook.nook/ContentBlocker/RequestStats", isDirectory: true)
    }

    deinit {
        if let e = engine { nook_adblock_engine_free(e) }
    }

    /// Build the engine from the filter rules, or load the serialized copy cached for this rules hash.
    func build(rules: [String], hash: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let start = CFAbsoluteTimeGetCurrent()
                if let old = self.engine { nook_adblock_engine_free(old); self.engine = nil }

                let dir = Self.cacheDir
                let cacheFile = dir.appendingPathComponent("engine-\(hash.prefix(24)).bin")

                if let data = try? Data(contentsOf: cacheFile),
                   let e = data.withUnsafeBytes({ (buf: UnsafeRawBufferPointer) -> UnsafeMutableRawPointer? in
                       guard let base = buf.bindMemory(to: UInt8.self).baseAddress else { return nil }
                       return nook_adblock_engine_deserialize(base, buf.count)
                   }) {
                    self.engine = e
                    log.info("Request stats engine loaded from cache in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
                } else {
                    let text = rules.joined(separator: "\n")
                    let e = text.withCString { nook_adblock_engine_from_rules($0, strlen($0)) }
                    self.engine = e
                    guard let e else {
                        log.error("adblock-rust engine build failed")
                        cont.resume(); return
                    }
                    var len = 0
                    if let bytes = nook_adblock_engine_serialize(e, &len) {
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        // ponytail: one cache file per rules hash; drop the others so the dir does not grow.
                        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                            .filter { $0.lastPathComponent != cacheFile.lastPathComponent }
                            .forEach { try? FileManager.default.removeItem(at: $0) }
                        try? Data(bytes: bytes, count: len).write(to: cacheFile, options: .atomic)
                        nook_adblock_buffer_free(bytes, len)
                    }
                    log.info("Request stats engine built from \(rules.count, privacy: .public) rules in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
                }
                cont.resume()
            }
        }
    }

    /// Number of `requests` (url + adblock-rust request type) that would be blocked when made from `sourceURL`.
    func blockedCount(of requests: [(url: String, type: String)], sourceURL: String) async -> Int {
        await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            queue.async {
                guard let e = self.engine else { cont.resume(returning: 0); return }
                var n = 0
                for r in requests where nook_adblock_engine_matches(e, r.url, sourceURL, r.type) { n += 1 }
                cont.resume(returning: n)
            }
        }
    }
}
