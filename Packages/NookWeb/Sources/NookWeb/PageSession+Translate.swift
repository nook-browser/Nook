// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Translate.swift
//  Nook
//
//  Whole-page translation on the Mac with the Translation framework. The script and its
//  handler live in the NookTranslate world, so a page can neither read nor feed them.
//

import Foundation
import Translation
import WebKit

extension PageSession {
    static let translateWorld = WKContentWorld.world(name: "NookTranslate")
    static let translateHandlerName = "nookTranslate"

    /// Hosts that got "Not Now" this session.
    private static var declinedTranslationHosts: Set<String> = []
    private static let minimumTextForOffer = 200
    private static let translationBatchSize = 40

    private static let translateScript: String = {
        guard let url = Bundle.module.url(forResource: "page-translate", withExtension: "js", subdirectory: "Resources"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    /// An ordinary web page that is not a PDF.
    public var canTranslate: Bool {
        guard !isDisplayingPDF, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The one entry point for menus and the palette: translate, or show the original.
    public func toggleTranslation() {
        if isTranslated { showOriginal() } else { Task { await translatePage() } }
    }

    public func showOriginal() {
        resetTranslation()
        Task { _ = await callTranslateScript("restore()") }
    }

    public func declineTranslationOffer() {
        if let host = url.host?.lowercased() { Self.declinedTranslationHosts.insert(host) }
        translationOffer = nil
    }

    /// Ends any translation in flight. The page's text stays as it is.
    func resetTranslation() {
        translationGeneration &+= 1
        translationFeed?.finish()
        translationFeed = nil
        installedTranslation?.cancel()
        installedTranslation = nil
        translationRequest = nil
        translationOffer = nil
        translationSource = nil
        isTranslated = false
    }

    // MARK: - Offer

    /// After a main-frame load: reads a 2 KB sample and offers translation when the page is
    /// in another language the system can translate.
    func offerTranslationIfNeeded() {
        guard canTranslate, !isTranslated,
              let host = url.host?.lowercased(), !Self.declinedTranslationHosts.contains(host)
        else { return }
        let generation = translationGeneration
        Task {
            guard let source = await detectSourceLanguage(minimumLength: Self.minimumTextForOffer),
                  generation == translationGeneration,
                  PageLanguage.needsTranslation(source, into: PageLanguage.reader)
            else { return }
            let status = await LanguageAvailability().status(from: source, to: PageLanguage.reader)
            guard status != .unsupported, generation == translationGeneration, !isTranslated else { return }
            translationSource = source
            translationOffer = source
        }
    }

    // MARK: - Translate

    private func translatePage() async {
        guard canTranslate, !isTranslated else { return }
        let generation = translationGeneration
        let target = PageLanguage.reader
        var source = translationSource
        if source == nil { source = await detectSourceLanguage(minimumLength: 1) }
        guard let source, generation == translationGeneration,
              PageLanguage.needsTranslation(source, into: target)
        else { return }
        let status = await LanguageAvailability().status(from: source, to: target)
        guard generation == translationGeneration, !isTranslated else { return }
        translationOffer = nil
        switch status {
        case .installed, .supported:
            isTranslated = true
            if status == .installed, #available(macOS 26, iOS 26, *) {
                let session = TranslationSession(installedSource: source, target: target)
                installedTranslation = Task { await runTranslation(with: session) }
            } else {
                // The host view's .translationTask hands back a session that can show the download
                // sheet; Sequoia has no other way to make one.
                translationRequest = TranslationSession.Configuration(source: source, target: target)
            }
        default:
            return
        }
    }

    /// Translates the page's text, then whatever the page adds, until the translation is reset or
    /// the caller's task ends. Safe to call again for the same page: only untranslated text is sent.
    public func runTranslation(with translator: TranslationSession) async {
        let generation = translationGeneration
        guard isTranslated else { return }
        let (stream, feed) = AsyncStream.makeStream(of: [[String: Any]].self)
        translationFeed?.finish()
        translationFeed = feed
        if let first = await callTranslateScript("start()") as? [[String: Any]] { feed.yield(first) }

        for await nodes in stream {
            guard generation == translationGeneration else { return }
            let requests = nodes.compactMap { node -> TranslationSession.Request? in
                guard let id = node["id"] as? String, let text = node["text"] as? String else { return nil }
                return TranslationSession.Request(sourceText: text, clientIdentifier: id)
            }
            for start in stride(from: 0, to: requests.count, by: Self.translationBatchSize) {
                let batch = Array(requests[start..<min(start + Self.translationBatchSize, requests.count)])
                do {
                    let responses = try await translator.translations(from: batch)
                    guard generation == translationGeneration else { return }
                    let pairs = responses.compactMap { response in
                        response.clientIdentifier.map { [$0, response.targetText] }
                    }
                    _ = await callTranslateScript("apply(pairs)", arguments: ["pairs": pairs])
                } catch {
                    // Cancelled download sheet, missing model, or the task ended: put the page back.
                    guard generation == translationGeneration, !Task.isCancelled else { return }
                    Self.log.error("Translation failed: \(error.localizedDescription, privacy: .public)")
                    showOriginal()
                    return
                }
            }
        }
    }

    // MARK: - Script

    private func detectSourceLanguage(minimumLength: Int) async -> Locale.Language? {
        guard let sample = await callTranslateScript("sample()") as? [String: Any],
              let text = sample["text"] as? String, text.count >= minimumLength
        else { return nil }
        return PageLanguage.detect(sample: text, declared: sample["lang"] as? String)
    }

    /// Installs the script in the main frame's NookTranslate world if needed, then runs `call`.
    private func callTranslateScript(_ call: String, arguments: [String: Any] = [:]) async -> Any? {
        guard let webView = primaryWebView, !Self.translateScript.isEmpty else { return nil }
        let body = Self.translateScript + "\nreturn window.__nookTranslate.\(call);"
        do {
            return try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.translateWorld)
        } catch {
            Self.log.error("Translate script failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
