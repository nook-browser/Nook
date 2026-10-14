// Licensed under GPL-3.0. See LICENSE.
//
//  DevPerf.swift
//  Nook
//
//  The page's load timings, LCP and interactions, from the capture script's PerformanceObservers.
//  WebKit has no layout-shift or long-animation-frame entries, so there is no CLS and no script
//  attribution for slow interactions.
//

import Foundation

public struct DevInteraction: Equatable {
    public var id: Int
    public var name: String
    public var duration: Double
    /// Event start to the first handler.
    public var inputDelay: Double
    /// The handlers themselves.
    public var processing: Double
    /// Last handler to the next paint.
    public var presentationDelay: Double
    public var target: String
    /// Unique selector for highlighting.
    public var path: String
}

public struct DevPerf: Equatable {
    public var ttfb: Double?
    public var fcp: Double?
    public var domContentLoaded: Double?
    public var load: Double?
    public var lcp: Double?
    public var lcpSize: Int?
    public var lcpTarget: String?
    public var lcpPath: String?
    public var lcpURL: String?
    /// Longest entry per interaction id.
    public private(set) var interactions: [Int: DevInteraction] = [:]

    public init() {}

    public var isEmpty: Bool { self == DevPerf() }

    /// INP as Chrome defines it: the worst interaction, or the 98th percentile past 50 of them.
    public var inp: DevInteraction? {
        let sorted = interactions.values.sorted { $0.duration > $1.duration }
        guard !sorted.isEmpty else { return nil }
        return sorted[min(sorted.count / 50, sorted.count - 1)]
    }

    public var interactionCount: Int { interactions.count }

    mutating func ingest(_ m: [String: Any]) {
        func num(_ k: String) -> Double? { (m[k] as? NSNumber)?.doubleValue }
        switch m["t"] as? String {
        case "event":
            guard let id = (m["id"] as? NSNumber)?.intValue, id > 0,
                  let start = num("start"), let duration = num("dur"),
                  let ps = num("ps"), let pe = num("pe") else { return }
            let next = DevInteraction(
                id: id, name: m["name"] as? String ?? "", duration: duration,
                inputDelay: max(0, ps - start), processing: max(0, pe - ps),
                presentationDelay: max(0, start + duration - pe),
                target: m["target"] as? String ?? "", path: m["path"] as? String ?? "")
            if let old = interactions[id], old.duration >= duration { return }
            interactions[id] = next
        case "lcp":
            lcp = num("time")
            lcpSize = (m["size"] as? NSNumber)?.intValue
            lcpTarget = m["target"] as? String
            lcpPath = m["path"] as? String
            lcpURL = (m["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        case "fcp":
            fcp = num("time")
        case "nav":
            ttfb = num("ttfb")
            domContentLoaded = num("dcl")
            load = num("load")
        default:
            return
        }
    }

    public enum Rating: String { case good, needsImprovement = "needs improvement", poor }

    /// Google's Web Vitals thresholds. Rated here, not by a model: the on-device model misjudged 800 < 2500.
    public static func rating(_ value: Double?, good: Double, poor: Double) -> Rating? {
        guard let value else { return nil }
        return value <= good ? .good : value <= poor ? .needsImprovement : .poor
    }

    public var ttfbRating: Rating? { Self.rating(ttfb, good: 800, poor: 1800) }
    public var fcpRating: Rating? { Self.rating(fcp, good: 1800, poor: 3000) }
    public var lcpRating: Rating? { Self.rating(lcp, good: 2500, poor: 4000) }
    public var inpRating: Rating? { Self.rating(inp?.duration, good: 200, poor: 500) }

    /// What to look at, one line per measurement that is not good. Written in code: the on-device model
    /// blamed input delay on the server and slow first paint on input delay.
    public var advice: [String] {
        func ms(_ v: Double) -> String { "\(Int(v.rounded())) ms" }
        var lines: [String] = []
        if let ttfb, ttfbRating != .good {
            lines.append("The server took \(ms(ttfb)) to start answering. Look at server time, redirects, and cache or CDN misses.")
        }
        if let fcp, fcpRating != .good {
            lines.append(ttfbRating == .good
                ? "Nothing drew until \(ms(fcp)). Stylesheets, scripts or web fonts in the head usually hold the first paint."
                : "Nothing drew until \(ms(fcp)), much of it waiting on the first byte.")
        }
        if let lcp, lcpRating != .good {
            if let lcpURL {
                lines.append("The largest element, an image (\(lcpURL)), drew at \(ms(lcp)). Preload it or give it fetchpriority=\"high\", and serve it smaller.")
            } else {
                lines.append("The largest element, \(lcpTarget ?? "a text block"), drew at \(ms(lcp)). It is waiting on fonts, stylesheets or the script that renders it.")
            }
        }
        if let worst = inp, inpRating != .good {
            let parts = [worst.inputDelay, worst.processing, worst.presentationDelay]
            switch parts.firstIndex(of: parts.max()!) {
            case 0: lines.append("The page was busy with other work for \(ms(worst.inputDelay)) before the \(worst.name) handlers ran. Break up long tasks on the main thread.")
            case 1: lines.append("The \(worst.name) handlers on \(worst.target) ran for \(ms(worst.processing)). Move work out of the handler, or yield before the slow part.")
            default: lines.append("Drawing after the \(worst.name) handlers took \(ms(worst.presentationDelay)). A large DOM change or the layout it causes is the usual reason.")
            }
        }
        if lines.isEmpty, ttfb != nil || lcp != nil || inp != nil { lines.append("Every measured number is good.") }
        return lines
    }

    /// Plain text for an agent.
    public var summary: String {
        func ms(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) ms" } ?? "not measured" }
        func rated(_ r: Rating?) -> String { r.map { " (\($0.rawValue))" } ?? "" }
        var lines = [
            "Time to first byte: \(ms(ttfb))\(rated(ttfbRating))",
            "First contentful paint: \(ms(fcp))\(rated(fcpRating))",
            "Largest contentful paint: \(ms(lcp))\(rated(lcpRating))" + (lcpTarget.map { " on \($0)" } ?? "") + (lcpURL.map { " (\($0))" } ?? ""),
            "DOMContentLoaded: \(ms(domContentLoaded))",
            "Load: \(ms(load))",
        ]
        if let worst = inp {
            lines.append("Interaction to next paint: \(ms(worst.duration))\(rated(inpRating)) over \(interactionCount) interactions; worst was "
                + "\(worst.name) on \(worst.target): input delay \(ms(worst.inputDelay)), processing \(ms(worst.processing)), "
                + "presentation delay \(ms(worst.presentationDelay))")
        } else {
            lines.append("Interaction to next paint: no interactions yet")
        }
        return lines.joined(separator: "\n")
    }
}
