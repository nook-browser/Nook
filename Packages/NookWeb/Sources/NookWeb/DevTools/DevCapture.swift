// Licensed under GPL-3.0. See LICENSE.
//
//  DevCapture.swift
//  Nook
//
//  One page's console and network log while Developer Mode is on. The capture script posts
//  batches to PageSession, which hands them here; the DevPanel and DevMCP read from it.
//

import Foundation
import Observation

@MainActor
@Observable
public final class DevCapture {
    public private(set) var console = DevLog<DevConsoleEntry>(capacity: 1_000)
    public private(set) var network = DevLog<DevNetworkEntry>(capacity: 1_000)
    public private(set) var blocked = DevLog<DevBlockEntry>(capacity: 2_000)
    /// Set at each main-frame commit.
    public var pageRules: DevPageRules?
    public private(set) var perf = DevPerf()
    /// Messages refused by the per-frame rate cap.
    public private(set) var droppedMessages = 0
    /// Errors and failed requests since the last page load.
    public private(set) var errorCount = 0
    /// The last element or entry handed to an agent. Survives navigation; it carries its own URL.
    public var lastPick: DevPick?

    /// The handler is in the page world, so any frame can post; one frame gets this many a second.
    static let perFrameLimit = 200
    /// The blocker log's position when the pending main-frame navigation began; nil between loads.
    @ObservationIgnored private var navigationMark: Int?
    @ObservationIgnored private var frameWindows: [String: (start: Double, count: Int)] = [:]
    @ObservationIgnored private let now: () -> Double

    public init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// A main-frame navigation began. The first call wins until the commit, so a rewrite that
    /// restarts the navigation keeps its own entry.
    // ponytail: a navigation that never commits leaves its mark, so the next commit keeps a few stale entries.
    public func markNavigationStart() {
        if navigationMark == nil { navigationMark = blocked.lastSeq }
    }

    public func reset() {
        console.clear()
        network.clear()
        if let mark = navigationMark { blocked.clear(through: mark) } else { blocked.clear() }
        navigationMark = nil
        pageRules = nil
        perf = DevPerf()
        droppedMessages = 0
        errorCount = 0
        frameWindows.removeAll()
    }

    public func clearConsole() {
        console.clear()
        errorCount = 0
    }

    /// WebKit reports one load once per rule list that matched it; repeats raise the count.
    public func recordBlock(_ entry: DevBlockEntry) {
        if let key = entry.key, blocked.items.contains(where: { $0.key == key }) {
            blocked.update(key: key) { $0.count += 1 }
        } else {
            blocked.append(entry)
            // Blocked loads never reach the page's own Resource Timing, so Network learns of them here.
            if entry.action == .blocked {
                var row = DevNetworkEntry(key: nil, kind: "blocked", method: "GET", url: entry.url)
                row.state = .failed
                row.error = "Blocked"
                network.append(row)
            }
        }
    }

    /// Blocked counts per host, most first.
    public var blockedHosts: [(host: String, count: Int)] {
        var counts: [String: Int] = [:]
        for e in blocked.items where e.action == .blocked { counts[e.host, default: 0] += 1 }
        // ponytail: counts distinct URLs per host; repeats of one URL do not add.
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.host < $1.host }
    }

    /// For lines Nook writes itself: the evaluate field's input and result.
    public func appendLocal(level: String, _ text: String) {
        console.append(DevConsoleEntry(level: level, message: text))
    }

    /// Takes one posted batch. Anything that is not the expected shape is ignored.
    public func ingest(_ body: Any, frameURL: String?) {
        guard let batch = body as? [[String: Any]] else { return }
        let allowed = admit(batch.count, frame: frameURL ?? "")
        for message in batch.prefix(allowed) {
            switch message["k"] as? String {
            case "c": ingestConsole(message, frameURL: frameURL)
            case "n": ingestNetwork(message, frameURL: frameURL)
            case "p": perf.ingest(message)
            case "d": droppedMessages += (message["n"] as? NSNumber)?.intValue ?? 0
            default: continue
            }
        }
    }

    private func admit(_ count: Int, frame: String) -> Int {
        let t = now()
        var window = frameWindows[frame] ?? (t, 0)
        if t - window.start >= 1 { window = (t, 0) }
        let allowed = max(0, min(count, Self.perFrameLimit - window.count))
        window.count += allowed
        frameWindows[frame] = window
        droppedMessages += count - allowed
        return allowed
    }

    private func ingestConsole(_ m: [String: Any], frameURL: String?) {
        guard let level = m["level"] as? String, let text = m["msg"] as? String else { return }
        let location = m["at"] as? String
        if let last = console.items.last, last.level == level, last.message == text, last.location == location {
            console.updateLast { $0.repeatCount += 1 }
        } else {
            console.append(DevConsoleEntry(level: level, message: text, location: location, frameURL: frameURL))
        }
        if console.items.last?.isError == true { errorCount += 1 }
    }

    private func ingestNetwork(_ m: [String: Any], frameURL: String?) {
        guard let id = m["id"] as? String, let phase = m["phase"] as? String else { return }
        let status = (m["status"] as? NSNumber)?.intValue
        let duration = (m["dur"] as? NSNumber)?.doubleValue
        switch phase {
        case "start", "res":
            guard let url = m["url"] as? String else { return }
            var entry = DevNetworkEntry(key: id, kind: m["kind"] as? String ?? "other",
                                        method: m["method"] as? String ?? "GET", url: url)
            entry.requestHeaders = m["reqH"] as? [String: String] ?? [:]
            entry.requestBody = m["reqB"] as? String
            entry.frameURL = frameURL
            if phase == "res" {
                entry.state = .done
                entry.duration = duration
                entry.size = (m["size"] as? NSNumber)?.intValue
                entry.status = status
            }
            network.append(entry)
        case "end":
            network.update(key: id) { e in
                e.state = .done
                e.status = status
                e.duration = duration
                e.size = (m["size"] as? NSNumber)?.intValue ?? e.size
                e.responseHeaders = m["resH"] as? [String: String] ?? [:]
                e.responseBody = m["resB"] as? String
            }
        // A body arrives on its own, so a stream that never ends cannot hold back the status.
        case "body":
            network.update(key: id) { $0.responseBody = m["resB"] as? String }
        case "fail":
            network.update(key: id) { e in
                e.state = .failed
                e.duration = duration
                e.error = m["err"] as? String ?? "Failed"
            }
            errorCount += 1
        default:
            return
        }
    }
}
