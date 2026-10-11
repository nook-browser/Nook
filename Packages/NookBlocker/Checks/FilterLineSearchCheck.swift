// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc Packages/NookBlocker/Sources/NookBlocker/FilterLineSearch.swift \
//         Packages/NookBlocker/Checks/FilterLineSearchCheck.swift -o /tmp/x && /tmp/x [list-directory]
//
//  With a directory of filter lists, also compares against the per-line filter it replaced.

import Foundation

/// What `ContentBlockerManager` did before: split, trim, drop empties, ask each line.
private func perLine(_ needle: String, _ texts: [String]) -> [String] {
    texts.flatMap { $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        .filter { $0.contains(needle) }
}

@main
struct FilterLineSearchCheck {
    static func main() throws {
        let cases: [[String]] = [
            ["a$removeparam=x"],
            ["a$removeparam=x\n"],
            ["first\n  b$removeparam=y  \nlast"],
            ["removeparam\nremoveparam"],
            ["x$removeparam=a,removeparam=b\nplain"],
            ["crlf$removeparam=1\r\nnext\r\n"],
            ["", "no match here", "tail$removeparam"],
            ["é$removeparam=ü\n日本$removeparam=語"],
        ]
        for texts in cases {
            precondition(FilterLineSearch.lines(containing: "removeparam", in: texts) == perLine("removeparam", texts),
                         "differs from the per-line filter for \(texts)")
        }
        precondition(FilterLineSearch.lines(containing: "urlskip=", in: ["a\nb"]).isEmpty)

        if CommandLine.arguments.count > 1 {
            let dir = URL(fileURLWithPath: CommandLine.arguments[1])
            let texts = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }.sorted { $0.path < $1.path }
                .map { try String(contentsOf: $0, encoding: .utf8) }
            for needle in ["removeparam", "urlskip="] {
                let found = FilterLineSearch.lines(containing: needle, in: texts)
                precondition(found == perLine(needle, texts), "\(needle) differs on the real lists")
                print("\(needle): \(found.count) lines, same as the per-line filter")
            }
        }
        print("FilterLineSearch ok")
    }
}
