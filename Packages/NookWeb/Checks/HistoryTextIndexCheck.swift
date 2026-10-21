// Licensed under GPL-3.0. See LICENSE.
//
//  HistoryTextIndexCheck.swift
//  Nook
//
//  Page text index check. NookWeb has no test target, so this compiles the shipped source directly:
//
//    swiftc -parse-as-library Packages/NookWeb/Sources/NookWeb/HistoryTextIndex.swift \
//           Packages/NookWeb/Checks/HistoryTextIndexCheck.swift -o /tmp/text-index-check && /tmp/text-index-check
//

import Foundation

@main
struct HistoryTextIndexCheck {
    static func main() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let index = HistoryTextIndex(fileURL: dir.appendingPathComponent("History/page-text.sqlite"))

        // Nothing is created by a read or a delete.
        do { let r = await index.search("anything", limit: 3); precondition(r.isEmpty) }
        await index.delete(url: "https://a.example/")
        precondition(!FileManager.default.fileExists(atPath: index.fileURL.path))

        let old = Date(timeIntervalSince1970: 1_700_000_000)
        await index.record(url: "https://a.example/", title: "Kettle review", body: "The thermostat holds water at eighty degrees. Café crème.", visitedAt: old)
        await index.record(url: "https://b.example/", title: "Bikes", body: "Gear ratios and the thermostat of nothing.", visitedAt: old.addingTimeInterval(60))

        // Every word is a prefix term, in any order, diacritics folded.
        do { let r = await index.search("thermo", limit: 5); precondition(r.count == 2) }
        do { let r = await index.search("eigh therm", limit: 5); precondition(r.map(\.url) == ["https://a.example/"]) }
        do { let r = await index.search("cafe creme", limit: 5); precondition(r.map(\.url) == ["https://a.example/"]) }
        do { let r = await index.search("kett", limit: 5); precondition(r.first?.snippet.contains("Kettle") == true) }
        do { let r = await index.search("thermostat", limit: 1); precondition(r.count == 1) }

        // FTS syntax in the query is literal text, never an error.
        for hostile in ["foo\" OR", "\"", "* NEAR(", "AND OR NOT", "a:b", "(-^)", "thermo\""] {
            _ = await index.search(hostile, limit: 5)
        }
        do { let r = await index.search("thermo\"", limit: 5); precondition(r.count == 2) }
        precondition(HistoryTextIndex.matchExpression(for: "  \" * ") == nil)

        // A revisit replaces the row.
        await index.record(url: "https://a.example/", title: "Kettle review", body: "Now about teapots.", visitedAt: old.addingTimeInterval(120))
        do { let r = await index.search("eighty", limit: 5); precondition(r.isEmpty) }
        do { let r = await index.search("teapot", limit: 5); precondition(r.map(\.url) == ["https://a.example/"]) }
        do { let r = await index.search("thermo", limit: 5); precondition(r.map(\.url) == ["https://b.example/"]) }

        // Deletion, by URL and by what history still holds.
        await index.delete(url: "https://b.example/")
        do { let r = await index.search("gear", limit: 5); precondition(r.isEmpty) }
        await index.record(url: "https://c.example/", title: "C", body: "Gear again", visitedAt: old)
        await index.retain(only: ["https://c.example/"])
        do { let r = await index.search("teapot", limit: 5); precondition(r.isEmpty) }
        do { let r = await index.search("gear", limit: 5); precondition(r.map(\.url) == ["https://c.example/"]) }

        await index.erase()
        precondition(!FileManager.default.fileExists(atPath: index.fileURL.path))
        do { let r = await index.search("gear", limit: 5); precondition(r.isEmpty) }
        // A write after erase starts a fresh file.
        await index.record(url: "https://d.example/", title: "D", body: "fresh", visitedAt: old)
        do { let r = await index.search("fresh", limit: 5); precondition(r.count == 1) }

        print("HistoryTextIndexCheck passed")
    }
}
