// Licensed under GPL-3.0. See LICENSE.
//
//  DevCaptureCheck.swift
//  Nook
//
//  Ring buffers, cursors, batch parsing and the per-frame rate cap behind the DevPanel and DevMCP.
//
//    swiftc -parse-as-library Packages/NookWeb/Sources/NookWeb/DevTools/DevLog.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevEntries.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevCapture.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevPick.swift \
//           Packages/NookWeb/Sources/NookWeb/DevTools/DevPerf.swift \
//           Packages/NookWeb/Checks/DevCaptureCheck.swift -o /tmp/devcapture && /tmp/devcapture
//

import Foundation

@main
struct DevCaptureCheck {
    @MainActor static func main() {
        // Ring buffer: oldest go first, the drop is counted, ids stay stable.
        var log = DevLog<DevConsoleEntry>(capacity: 3)
        for i in 0..<5 { log.append(DevConsoleEntry(level: "log", message: "m\(i)")) }
        precondition(log.items.map(\.message) == ["m2", "m3", "m4"])
        precondition(log.dropped == 2)
        precondition(log.lastSeq == 5)
        precondition(log.since(3).map(\.message) == ["m3", "m4"])
        precondition(log.since(5).isEmpty)

        // An update moves the entry past the cursor so a poller sees it again.
        var net = DevLog<DevNetworkEntry>(capacity: 10)
        net.append(DevNetworkEntry(key: "r1", kind: "fetch", method: "GET", url: "https://a.test/x"))
        let firstID = net.items[0].id
        let cursor = net.lastSeq
        net.update(key: "r1") { $0.status = 200 }
        precondition(net.since(cursor).first?.status == 200)
        precondition(net.items[0].id == firstID, "id survives an update")
        net.update(key: "missing") { $0.status = 500 }
        precondition(net.items.count == 1)

        var clock = 100.0
        let capture = DevCapture(now: { clock })

        // Malformed bodies change nothing.
        capture.ingest("nope", frameURL: nil)
        capture.ingest([["k": 3]], frameURL: nil)
        capture.ingest([["k": "c"]], frameURL: nil)
        precondition(capture.console.items.isEmpty && capture.network.items.isEmpty)

        // Console entries, repeats collapse, errors counted.
        capture.ingest([
            ["k": "c", "level": "log", "msg": "hello"],
            ["k": "c", "level": "log", "msg": "hello"],
            ["k": "c", "level": "error", "msg": "boom", "at": "app.js:4"],
        ], frameURL: "https://a.test/")
        precondition(capture.console.items.count == 2)
        precondition(capture.console.items[0].repeatCount == 2)
        precondition(capture.errorCount == 1)
        precondition(capture.console.items[1].location == "app.js:4")

        // A fetch start and end merge into one row.
        capture.ingest([
            ["k": "n", "id": "f1", "phase": "start", "kind": "fetch", "method": "POST", "url": "https://a.test/api",
             "reqH": ["content-type": "application/json"], "reqB": "{}"],
            ["k": "n", "id": "f1", "phase": "end", "status": 201, "dur": 12.5],
            ["k": "n", "id": "f1", "phase": "body", "resB": "{\"ok\":true}"],
            ["k": "n", "id": "r9", "phase": "res", "kind": "script", "url": "https://cdn.test/a.js", "dur": 3, "size": 900],
            ["k": "n", "id": "f2", "phase": "start", "kind": "xhr", "method": "GET", "url": "https://a.test/b"],
            ["k": "n", "id": "f2", "phase": "fail", "err": "TypeError: Load failed"],
        ], frameURL: nil)
        precondition(capture.network.items.count == 3)
        let post = capture.network.items[0]
        precondition(post.status == 201 && post.method == "POST" && post.responseBody == "{\"ok\":true}")
        precondition(post.requestHeaders["content-type"] == "application/json")
        precondition(capture.network.items[2].error == "TypeError: Load failed")
        precondition(capture.errorCount == 2, "a failed request counts as an error")

        // Per-frame rate cap: 200 a second, the rest counted, a new second resets it.
        let flood = (0..<250).map { ["k": "c", "level": "log", "msg": "x\($0)"] as [String: Any] }
        capture.ingest(flood, frameURL: "https://spam.test/")
        precondition(capture.droppedMessages == 50)
        clock += 1.5
        capture.ingest([["k": "c", "level": "log", "msg": "after"]], frameURL: "https://spam.test/")
        precondition(capture.console.items.last?.message == "after")

        // The script reports what its own queue refused.
        capture.ingest([["k": "d", "n": 99_000]], frameURL: "https://other.test/")
        precondition(capture.droppedMessages == 99_050)

        // Blocker log and per-host counts.
        capture.recordBlock(DevBlockEntry(action: .blocked, url: "https://ads.test/a.js"))
        capture.recordBlock(DevBlockEntry(action: .blocked, url: "https://ads.test/b.js"))
        capture.recordBlock(DevBlockEntry(action: .blocked, url: "https://ads.test/b.js"))
        precondition(capture.blocked.items.count == 2 && capture.blocked.items[1].count == 2, "a repeat raises the count")
        precondition(capture.network.items.filter { $0.kind == "blocked" }.count == 2, "each blocked URL once in Network")
        capture.recordBlock(DevBlockEntry(action: .blocked, url: "https://px.test/p.gif"))
        capture.recordBlock(DevBlockEntry(action: .madeHTTPS, url: "http://px.test/x"))
        precondition(capture.blockedHosts.map(\.host) == ["ads.test", "px.test"])
        precondition(capture.blockedHosts.first?.count == 2)

        let rules = DevPageRules(procedural: ["{}"], scriptletCode: """
        function setConstant(a, b) { if (x) { safe.uboLog(a); } }
        out.push(1)
        try {
        setConstant("ytInitialPlayerResponse.adPlacements", "undefined")
        } catch ( e ) { }
        try {
        jsonPrune("a", "b")
        } catch ( e ) { }
        try {
        setConstant("other", "1")
        } catch ( e ) { }
        """)
        precondition(rules.scriptlets == ["setConstant", "jsonPrune"], "\(rules.scriptlets)")
        capture.pageRules = rules

        // Perf: interactions keep their longest entry; INP is the worst under 50 interactions.
        capture.ingest([
            ["k": "p", "t": "event", "id": 7, "name": "click", "start": 100, "dur": 120, "ps": 130, "pe": 190, "target": "button.save"],
            ["k": "p", "t": "event", "id": 7, "name": "pointerup", "start": 100, "dur": 80, "ps": 101, "pe": 150],
            ["k": "p", "t": "event", "id": 8, "name": "keydown", "start": 400, "dur": 40, "ps": 405, "pe": 420],
            ["k": "p", "t": "event", "id": 0, "name": "mousemove", "start": 1, "dur": 300, "ps": 1, "pe": 2],
            ["k": "p", "t": "event", "id": 9, "name": "broken"],
            ["k": "p", "t": "lcp", "time": 812.4, "size": 50_000, "target": "img.hero", "url": ""],
            ["k": "p", "t": "fcp", "time": 300],
            ["k": "p", "t": "nav", "ttfb": 90, "dcl": 500, "load": 900],
        ], frameURL: nil)
        let worst = capture.perf.inp!
        precondition(capture.perf.interactionCount == 2, "id 0 and malformed entries ignored")
        precondition(worst.id == 7 && worst.duration == 120 && worst.name == "click")
        precondition(worst.inputDelay == 30 && worst.processing == 60 && worst.presentationDelay == 30)
        precondition(capture.perf.lcp == 812.4 && capture.perf.lcpURL == nil)
        precondition(capture.perf.summary.contains("Largest contentful paint: 812 ms (good) on img.hero"))
        precondition(capture.perf.inpRating == .good)
        precondition(DevPerf.rating(201, good: 200, poor: 500) == .needsImprovement)
        precondition(DevPerf.rating(500, good: 200, poor: 500) == .needsImprovement)
        precondition(DevPerf.rating(501, good: 200, poor: 500) == .poor)
        precondition(capture.perf.summary.contains("input delay 30 ms, processing 60 ms, presentation delay 30 ms"))
        precondition(capture.perf.advice == ["Every measured number is good."])
        var slow = DevPerf()
        slow.ingest(["t": "nav", "ttfb": 2100, "dcl": 0, "load": 0])
        slow.ingest(["t": "fcp", "time": 3300])
        slow.ingest(["t": "lcp", "time": 5200, "target": "img.hero", "url": "https://cdn.test/h.jpg"])
        slow.ingest(["t": "event", "id": 1, "name": "keydown", "start": 0, "dur": 264, "ps": 88, "pe": 268, "target": "input#q"])
        let advice = slow.advice
        precondition(advice.count == 4, "\(advice)")
        precondition(advice[0].hasPrefix("The server took 2100 ms"))
        precondition(advice[1].contains("waiting on the first byte"), "slow FCP after slow TTFB blames the first byte")
        precondition(advice[2].contains("https://cdn.test/h.jpg"))
        precondition(advice[3].hasPrefix("The keydown handlers on input#q ran for 180 ms"), "processing dominates")
        var empty = DevPerf()
        precondition(empty.advice.isEmpty, "nothing measured, nothing said")
        empty.ingest(["t": "fcp", "time": 100])
        precondition(empty.advice.isEmpty)
        var many = DevPerf()
        for i in 1...100 { many.ingest(["t": "event", "id": i, "name": "click", "start": 0, "dur": Double(i), "ps": 0, "pe": 0]) }
        precondition(many.inp?.duration == 98, "98th percentile past 50 interactions")

        // A rewrite logged after the navigation began survives that navigation's commit.
        capture.markNavigationStart()
        capture.recordBlock(DevBlockEntry(action: .strippedParams, url: "https://a.test/?utm_source=x", target: "https://a.test/"))
        capture.markNavigationStart()
        capture.reset()
        precondition(capture.blocked.items.map(\.action) == [.strippedParams], "\(capture.blocked.items.map(\.action))")

        capture.reset()
        precondition(capture.blocked.items.isEmpty && capture.pageRules == nil && capture.perf.isEmpty)
        precondition(capture.console.items.isEmpty && capture.network.items.isEmpty)
        precondition(capture.errorCount == 0 && capture.droppedMessages == 0)

        print("DevCaptureCheck passed")
    }
}
