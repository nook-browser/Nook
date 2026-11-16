// Licensed under GPL-3.0. See LICENSE.
//
//  LookupReader.swift
//  Nook
//
//  How Look It Up reads a result: a plain fetch first, then a reader page for the ones that
//  come back without text. Every request goes through the link preview gate, so nothing a
//  results page names reaches this network, and reader pages carry no logins.
//

import AppKit
import NookWeb
import OSLog
import WebKit

@MainActor
final class LookupReader {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Lookup")
    private static let maxOpen = 3
    private static let loadSeconds = 12.0
    /// The most a fetch may take in all. The request's own timeout only counts silence.
    private static let fetchSeconds = 10.0
    /// After the load, for a page that draws its text in script.
    private static let settleSeconds = 2.0
    private static let pageSize = NSSize(width: 1100, height: 1500)
    private static let shotWidth: CGFloat = 900
    fileprivate nonisolated static let maxHTMLBytes = 1_500_000

    private let tabs: TabsController
    private weak var host: NSView?
    private let profile: Profile
    private var open: [PageSession] = []
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var ended = false
    private var opened = 0
    private var closed = 0

    /// `host` keeps reader pages rendering out of sight; `profile` is theirs alone.
    init(tabs: TabsController, host: NSView, profile: Profile) {
        self.tabs = tabs
        self.host = host
        self.profile = profile
    }

    // MARK: - Fetching

    /// The page's title, lead image and text from its HTML, or nil when it could not be fetched.
    func fetch(_ url: URL) async -> (title: String?, image: URL?, text: String)? {
        guard let (data, http) = await Self.within(Self.fetchSeconds, {
            await LinkPreviewService.gatedData(
                url, accept: "text/html,application/xhtml+xml", userAgent: PlatformUserAgent.custom,
                limit: Self.maxHTMLBytes, htmlOnly: true)
        }) else { return nil }
        let base = http.url ?? url
        // Off the main actor: scanning a large page would stall the window.
        return await Task.detached {
            LookupText.page(fromHTML: String(decoding: data, as: UTF8.self), baseURL: base)
        }.value
    }

    /// A picture's bytes: nil when it is refused, missing, over `limit` bytes or not an image.
    func data(_ url: URL, limit: Int) async -> Data? {
        guard let (data, _) = await LinkPreviewService.gatedData(url, userAgent: PlatformUserAgent.custom, limit: limit),
              NSImage(data: data) != nil else { return nil }
        return data
    }

    // MARK: - Reader Pages

    /// Loads `url` in a reader page and returns what it shows, ending the page once read. Three at
    /// most are open; a fourth call waits. `booking` adds the page's controls, heading and picture.
    func readInPage(_ url: URL, booking: Bool) async -> LookupReadPage? {
        guard await Self.mayLoad(url) else { return nil }
        let rules = await TabsController.readerRules()
        if rules == nil { Self.log.error("Reader rules did not compile; reader pages run on the gate alone") }
        await takeSlot()
        defer { freeSlot() }
        guard !ended, !Task.isCancelled, let host else { return nil }
        let session = tabs.openReader(url: url, profile: profile, rules: rules) { await Self.mayLoad($0) }
        open.append(session)
        opened += 1
        defer { end(session) }
        guard let view = session.webView else { return nil }
        // Sized once, before it enters the window (see CLAUDE.md on resizing off-window views).
        view.frame = NSRect(origin: .zero, size: Self.pageSize)
        host.addSubview(view)
        await session.finishedLoading(within: Self.loadSeconds)
        try? await Task.sleep(for: .seconds(Self.settleSeconds))
        guard !ended, !Task.isCancelled else { return nil }
        let text = await session.readText()
        guard !text.isEmpty else { return nil }
        var page = LookupReadPage(title: session.title, text: text)
        if booking {
            page.labels = await session.readControlLabels()
            page.heading = await session.readHeading()
            page.shot = await session.snapshotJPEG(width: Self.shotWidth)
        }
        return page
    }

    /// Ends every reader page, and makes any call still waiting return nothing.
    func endAll() {
        ended = true
        open.forEach(end)
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume() }
        if opened > 0 { Self.log.info("Reader pages: opened \(self.opened), ended \(self.closed)") }
    }

    private func end(_ session: PageSession) {
        guard let index = open.firstIndex(where: { $0 === session }) else { return }
        open.remove(at: index)
        closed += 1
        session.webView?.removeFromSuperview()
        tabs.endDetached(session)
    }

    /// `work`'s answer, or nil once `seconds` have passed, when the work is cancelled.
    private nonisolated static func within<T>(_ seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask(operation: work)
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// A reader page loads https only, and only from a public address.
    private nonisolated static func mayLoad(_ url: URL) async -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return await LinkPreviewService.mayReach(url)
    }

    private func takeSlot() async {
        if active < Self.maxOpen {
            active += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    private func freeSlot() {
        if waiting.isEmpty {
            active = max(0, active - 1)
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// MARK: - LookupReading

extension LookupReader: LookupReading {
    private static let maxIconBytes = 200_000

    /// When any lookup last asked the results page. Two requests are kept a second apart: the
    /// endpoint answers a burst by refusing the whole address for half an hour.
    private static var lastSearch = ContinuousClock.now - searchSpacing
    private static let searchSpacing: Duration = .seconds(1)

    /// One request to the results page; nothing comes back when it refuses.
    func search(_ query: String) async -> [LookupHit] {
        let wait = Self.searchSpacing - (ContinuousClock.now - Self.lastSearch)
        Self.lastSearch = ContinuousClock.now + max(wait, .zero)
        if wait > .zero { try? await Task.sleep(for: wait) }
        if Task.isCancelled { return [] }
        guard let (data, _) = await Self.within(Self.fetchSeconds, {
            await LinkPreviewService.gatedData(
                LookupSearch.url(for: query), accept: "text/html", userAgent: PlatformUserAgent.custom, limit: Self.maxHTMLBytes)
        }) else { return [] }
        return await Task.detached {
            LookupSearch.hits(inHTML: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// The icon Nook already has for the site, else the site's own `favicon.ico`.
    func icon(for url: URL) async -> Data? {
        if let key = FaviconCache.key(for: url), let cached = await FaviconCache.shared.cachedImage(for: key) {
            return cached.pngData()
        }
        guard let host = url.host, let address = URL(string: "https://\(host)/favicon.ico") else { return nil }
        return await data(address, limit: Self.maxIconBytes)
    }
}

/// Holds reader pages out of sight so WebKit keeps drawing them: transparent, outside the content
/// area, never the target of a click.
final class LookupReaderHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
}
