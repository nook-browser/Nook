// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+Lookup.swift
//  NookWeb
//
//  What Look It Up needs from the tab model: reader pages, which load a result in the
//  background so its text can be read, and the test for one of its own answer pages.
//

import Foundation
import WebKit

extension TabsController {
    /// True for the `page.html` of a lookup under the app's support folder.
    public func isLookupPage(_ url: URL) -> Bool {
        guard let lookupSupport else { return false }
        return LookupStore.lookupID(ofPage: url, in: lookupSupport) != nil
    }

    /// The lookups some tab, open page, archive entry or reopen entry still points at. Every other
    /// lookup's folder can go. Nil when the tab files could not be read: the tree in memory is
    /// then a stand-in, and nothing may be deleted on its word.
    public func referencedLookupIDs() -> Set<UUID>? {
        guard let lookupSupport, !isReadOnly else { return nil }
        var urls = tree.items.values.compactMap(\.url) + device.openPages.values.map(\.url)
        for entry in device.closed {
            urls += entry.items.compactMap(\.url)
            if let page = entry.endedPage { urls.append(page.url) }
        }
        for entry in archive.entries { urls += entry.items.compactMap(\.url) }
        return Set(urls.compactMap { LookupStore.lookupID(ofPage: $0, in: lookupSupport) })
    }

    /// A quiet page outside the tree that loads `url` at once. `mayLoad` is asked before every
    /// http(s) load in any frame, and `rules` are in its view before the first request. End it
    /// with `endDetached(_:)`.
    public func openReader(url: URL, profile: Profile, rules: WKContentRuleList?, mayLoad: @escaping @Sendable (URL) async -> Bool) -> PageSession {
        let session = PageSession(
            itemID: UUID(), url: url, title: url.host ?? url.absoluteString,
            isPrivate: profile.isEphemeral, controller: self)
        session.detachedProfile = profile
        session.isQuiet = true
        session.navigationGate = mayLoad
        session.readerRules = rules
        session.loadWebViewIfNeeded()
        return session
    }

    /// Marks a tab as one Look It Up opened to act on (`PageSession.guardsCommits`). The mark is
    /// kept in device.json, so it outlives a relaunch, and goes when the tab is gone for good.
    public func markGuarded(_ itemID: UUID) {
        guard !isGuarded(itemID) else { return }
        device.guarded = (device.guarded ?? []).union([itemID])
        save()
    }

    public func isGuarded(_ itemID: UUID) -> Bool {
        device.guarded?.contains(itemID) == true
    }

    /// A tab opened from a guarded tab is guarded too, so a new tab is no way around the line.
    func inheritGuard(_ itemID: UUID, from opener: UUID?) {
        if let opener, isGuarded(opener) { markGuarded(itemID) }
    }

    // MARK: - Reader Rules

    private static var compiledReaderRules: WKContentRuleList?

    /// Blocks every request a reader page makes to this machine or this network, in any form a
    /// navigation gate cannot see: images, scripts, fetch, sockets. Names that resolve to a
    /// private address are the gate's job, and only for navigations.
    /// ponytail: one rule a range, since WebKit's rule syntax has no alternation.
    public static func readerRules() async -> WKContentRuleList? {
        if let compiledReaderRules { return compiledReaderRules }
        let hosts = [
            "localhost[:/]", "[^/:]*\\.localhost[:/]", "[^/:]*\\.local[:/]", "[^/:]*\\.lan[:/]", "[^/:]*\\.internal[:/]",
            "[^/:]*\\.home\\.arpa[:/]", "0\\.", "10\\.", "127\\.", "169\\.254\\.", "192\\.168\\.", "172\\.1[6-9]\\.", "172\\.2[0-9]\\.",
            "172\\.3[01]\\.", "\\[", "[^./:]+[:/]",
        ]
        let patterns = hosts.map { "^[a-z]+://" + $0 } + ["^http://", "^ws://"]
        let rules = patterns.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { return nil }
        compiledReaderRules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nook-lookup-reader-1", encodedContentRuleList: json)
        return compiledReaderRules
    }
}

extension PageSession {
    private static let maxReadCharacters = 200_000

    /// True on a tab Look It Up opened to press a time, or one opened from it: the chat's tools
    /// leave any control there that signs in, pays or confirms to the person (`GuardedTools`).
    public var guardsCommits: Bool { controller?.isGuarded(itemID) == true }

    /// The page's visible text, line breaks kept. A page too busy to answer within `seconds`
    /// reads as nothing.
    public func readText(within seconds: Double = 3) async -> String {
        let script = "document.body ? document.body.innerText.slice(0, \(Self.maxReadCharacters)) : ''"
        return LookupText.tidy(innerText: await answer(to: script, within: seconds) as? String ?? "")
    }

    // One line a result: address, title, snippet, tab-separated. The selectors are DuckDuckGo's.
    private static let searchRowsScript = """
        (() => {
          const clean = t => (t || '').replace(/\\s+/g, ' ').trim();
          return [...document.querySelectorAll('article')].map(row => {
            const link = row.querySelector('a[data-testid="result-title-a"]');
            if (!link) return null;
            const snippet = row.querySelector('[data-result="snippet"]');
            return [link.href, clean(link.innerText).slice(0, 300), clean(snippet && snippet.innerText).slice(0, 500)].join('\\t');
          }).filter(Boolean).slice(0, 30).join('\\n');
        })()
        """

    /// The results the ordinary search page shows, for `LookupSearch.hits(inRows:)`.
    public func readSearchRows(within seconds: Double = 3) async -> String {
        await answer(to: Self.searchRowsScript, within: seconds) as? String ?? ""
    }

    /// Returns when the load under way ends, well or badly, or after `seconds`.
    /// ponytail: checks the load state every 150 ms, only while Look It Up waits on a page; an
    /// observation of `loadingState` would do it without the loop.
    public func finishedLoading(within seconds: Double) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            switch loadingState {
            case .didFinish, .didFail, .didFailProvisionalNavigation: return
            default: try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// What `script` returns, or nil once `seconds` have passed. Runs in an isolated world, so
    /// the page cannot stand in for what the script reads.
    func answer(to script: String, within seconds: Double) async -> Any? {
        guard let webView else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
            var answered = false
            func answer(_ value: Any?) {
                guard !answered else { return }
                answered = true
                continuation.resume(returning: value)
            }
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { answer(try? $0.get()) }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { answer(nil) }
        }
    }
}
