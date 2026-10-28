// Licensed under GPL-3.0. See LICENSE.
// swiftc Nook/Managers/DownloadManager/DownloadHistoryStore.swift scripts/tests/DownloadHistoryCheck.swift -o /tmp/dlhist && /tmp/dlhist

import Foundation

@main
struct DownloadHistoryCheck {
    static func snap(_ path: String, _ age: TimeInterval, url: String = "https://example.com/a.pdf",
                     done: Bool = true, isPrivate: Bool = false, profile: UUID? = nil) -> DownloadSnapshot {
        DownloadSnapshot(originalURL: URL(string: url)!, path: path, date: Date(timeIntervalSince1970: 1_000_000 - age),
                         size: 1, renamedFrom: nil, profileID: profile, isCompleted: done, isPrivate: isPrivate)
    }

    static func main() {
        // A private-window (or Agent space) download never reaches the file.
        let kept = DownloadHistoryStore.records(from: [snap("/a", 0), snap("/p", 1, isPrivate: true)])
        precondition(kept.map(\.path) == ["/a"], "private download persisted")

        // Unfinished downloads are not history.
        precondition(DownloadHistoryStore.records(from: [snap("/x", 0, done: false)]).isEmpty)

        // Signed tokens live in the query and fragment; credentials in the userinfo.
        let signed = DownloadHistoryStore.records(from: [
            snap("/s", 0, url: "https://user:pw@cdn.example.com/f.zip?X-Amz-Signature=abc&token=1#frag"),
        ])
        precondition(signed[0].originalURL.absoluteString == "https://cdn.example.com/f.zip",
                     signed[0].originalURL.absoluteString)

        // Newest first, capped at the limit.
        let many = (0..<(DownloadHistoryStore.limit + 20)).map { snap("/f\($0)", TimeInterval($0)) }
        let capped = DownloadHistoryStore.records(from: many.reversed())
        precondition(capped.count == DownloadHistoryStore.limit)
        precondition(capped.first?.path == "/f0" && capped.last?.path == "/f\(DownloadHistoryStore.limit - 1)")

        // The profile rides along.
        let profile = UUID()
        precondition(DownloadHistoryStore.records(from: [snap("/q", 0, profile: profile)])[0].profileID == profile)

        // Records written before profiles existed still decode.
        let old = #"[{"originalURL":"https:\/\/a.com\/x","path":"\/x","date":0}]"#.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: old)
        precondition(decoded?.first?.profileID == nil && decoded?.count == 1, "old record failed to decode")

        print("DownloadHistoryCheck passed")
    }
}
