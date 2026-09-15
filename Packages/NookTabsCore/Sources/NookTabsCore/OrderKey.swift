import Foundation

/// A sort position that always has room for another key between two neighbors.
///
/// Keys are base-62 fractions (`"V"` is 0.5) with no trailing zero digit, compared as
/// plain strings. Inserting between two siblings writes only the moved item.
public struct OrderKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }

    public static func < (lhs: OrderKey, rhs: OrderKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = alphabet.count
    private static let values: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    /// A key strictly between `lower` and `upper`. nil means the open end of the list.
    /// Returns nil when `lower >= upper` or either key is malformed; callers renumber the siblings.
    public static func between(_ lower: OrderKey?, _ upper: OrderKey?) -> OrderKey? {
        guard let a = digits(lower), let b = digits(upper) else { return nil }
        if let lower, let upper, lower >= upper { return nil }
        let result = midpoint(a ?? [], b)
        return OrderKey(String(result.map { alphabet[$0] }))
    }

    /// `count` evenly spread keys, used when siblings must be renumbered.
    public static func sequence(count: Int) -> [OrderKey] {
        var keys: [OrderKey] = []
        var last: OrderKey?
        for _ in 0..<count {
            let next = between(last, nil)!
            keys.append(next)
            last = next
        }
        return keys
    }

    /// nil key -> .some(nil); malformed -> nil.
    private static func digits(_ key: OrderKey?) -> [Int]?? {
        guard let key else { return .some(nil) }
        var out: [Int] = []
        for ch in key.rawValue {
            guard let v = values[ch] else { return nil }
            out.append(v)
        }
        guard let last = out.last, last != 0 else { return nil }
        return .some(out)
    }

    /// Midpoint of two base-62 fractions `a < b`; `b == nil` is 1.0. Linear in key length.
    private static func midpoint(_ lowerDigits: [Int], _ upperDigits: [Int]?) -> [Int] {
        var out: [Int] = []
        var a = lowerDigits[...]
        var b = upperDigits.map { $0[...] }
        if let upper = b {
            var n = 0
            while n < upper.count, (n < a.count ? a[a.startIndex + n] : 0) == upper[upper.startIndex + n] { n += 1 }
            out.append(contentsOf: upper.prefix(n))
            a = a.dropFirst(n)
            b = upper.dropFirst(n)
        }
        while true {
            let da = a.first ?? 0
            let db = b?.first ?? base
            if db - da > 1 {
                out.append((da + db) / 2)
                return out
            }
            if let upper = b, upper.count > 1 {
                out.append(upper[upper.startIndex])
                return out
            }
            out.append(da)
            a = a.dropFirst()
            b = nil
        }
    }
}
