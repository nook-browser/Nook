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

    /// The page's visible text, line breaks kept. Read in an isolated world, so the page cannot
    /// stand in for `innerText`. A page too busy to answer within `seconds` reads as nothing.
    public func readText(within seconds: Double = 3) async -> String {
        guard let webView else { return "" }
        let script = "document.body ? document.body.innerText.slice(0, \(Self.maxReadCharacters)) : ''"
        let text: String = await withCheckedContinuation { continuation in
            var answered = false
            func answer(_ text: String) {
                guard !answered else { return }
                answered = true
                continuation.resume(returning: text)
            }
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                answer((try? result.get()) as? String ?? "")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { answer("") }
        }
        return LookupText.tidy(innerText: text)
    }
}
