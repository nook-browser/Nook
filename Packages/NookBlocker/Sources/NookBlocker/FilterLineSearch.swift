// Licensed under GPL-3.0. See LICENSE.
import Foundation

enum FilterLineSearch {
    /// The lines of `texts` holding `needle`, trimmed, by a byte search over each text. Asking
    /// each of 430K lines with `String.contains` took 0.3 s, and launch waited on it.
    static func lines(containing needle: String, in texts: [String]) -> [String] {
        let needle = Array(needle.utf8)
        var found: [String] = []
        for var text in texts {
            text.withUTF8 { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count,
                      let hit = memmem(base + offset, bytes.count - offset, needle, needle.count) {
                    let at = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                    var start = at, end = at
                    while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
                    while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                    let line = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
                    found.append(line.trimmingCharacters(in: .whitespaces))
                    offset = end
                }
            }
        }
        return found
    }
}
