// Licensed under GPL-3.0. See LICENSE.
//
//  PageLanguage.swift
//  Nook
//
//  The language of a page's text sample, and whether it needs translating for the reader.
//

import Foundation
import NaturalLanguage

enum PageLanguage {
    /// The share of the text a language needs to stand without the page's `lang`, or against it.
    private static let strongShare = 0.75
    /// The page's `lang` stands while this share of the text reads as that language.
    private static let supportShare = 0.1
    private static let pieceLength = 100

    /// The sample's language. The page's declared `lang` holds unless the text is plainly in
    /// another language the recognizer can tell from it.
    static func detect(sample: String, declared: String?) -> Locale.Language? {
        let shares = votes(in: sample)
        let page = language(declared: declared)
        guard let top = shares.max(by: { $0.value < $1.value }) else { return page }
        let winner = Locale.Language(identifier: top.key)
        let confident = top.value >= strongShare ? winner : nil
        guard let page, let code = page.languageCode else { return confident }
        // Same language: the recognizer's answer carries the script (zh-Hans, zh-Hant).
        if winner.languageCode == code { return winner }
        let support = shares.filter { Locale.Language(identifier: $0.key).languageCode == code }.values.reduce(0, +)
        if support >= supportShare { return page }
        // With no model for a language the recognizer names a neighbour: Afrikaans reads as Dutch.
        if !recognizes(page, in: sample), script(of: page) == script(of: winner) { return page }
        return confident ?? page
    }

    /// Each language's share of the sample. The recognizer judges a string by about its first
    /// hundred characters, so the sample is read a piece at a time.
    static func votes(in sample: String) -> [String: Double] {
        var shares: [String: Double] = [:]
        var total = 0.0
        let recognizer = NLLanguageRecognizer()
        for piece in pieces(of: sample) {
            recognizer.reset()
            recognizer.processString(piece)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 3).filter { $0.key != .undetermined }
            guard !hypotheses.isEmpty else { continue }
            let length = Double(piece.count)
            for (language, confidence) in hypotheses { shares[language.rawValue, default: 0] += confidence * length }
            total += length
        }
        return shares.mapValues { $0 / total }
    }

    /// Whole words up to `pieceLength` characters a piece; text with no spaces is cut at that length.
    private static func pieces(of text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            var word = word
            while word.count > pieceLength {
                pieces.append(String(word.prefix(pieceLength)))
                word = word.dropFirst(pieceLength)
            }
            if !current.isEmpty, current.count + word.count >= pieceLength {
                pieces.append(current)
                current = ""
            }
            if !current.isEmpty { current += " " }
            current += word
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// The page's `lang` when it names a language: "jp", "x-default" and "und" do not.
    private static func language(declared: String?) -> Locale.Language? {
        guard let declared = declared?.trimmingCharacters(in: .whitespaces), !declared.isEmpty else { return nil }
        let language = Locale.Language(identifier: declared)
        guard let code = language.languageCode?.identifier, !["und", "mul", "zxx"].contains(code),
              Locale(identifier: "en").localizedString(forLanguageCode: code) != nil
        else { return nil }
        // Old codes become current ones: iw is he, in is id.
        return Locale.Language(identifier: language.minimalIdentifier)
    }

    /// Whether the recognizer has a model for the language: limited to one it has none for, it
    /// answers nothing. Persian has a model that loses to Arabic on every text.
    private static func recognizes(_ language: Locale.Language, in sample: String) -> Bool {
        guard let code = language.languageCode, code.identifier != "fa" else { return false }
        let recognizer = NLLanguageRecognizer()
        // Chinese is known to it only with a script: zh-Hans, zh-Hant.
        let withScript = [code.identifier, script(of: language)?.identifier].compactMap { $0 }.joined(separator: "-")
        recognizer.languageConstraints = [code.identifier, withScript].map { NLLanguage(rawValue: $0) }
        recognizer.processString(sample)
        return recognizer.languageHypotheses(withMaximum: 2).keys.contains { Locale.Language(identifier: $0.rawValue).languageCode == code }
    }

    private static func script(of language: Locale.Language) -> Locale.Script? {
        Locale.Language(identifier: language.maximalIdentifier).script
    }

    /// Different language, or the same one in another script (Simplified and Traditional
    /// Chinese). Regional variants (en-GB, en-US) count as the same.
    static func needsTranslation(_ source: Locale.Language, into target: Locale.Language) -> Bool {
        guard let code = source.languageCode, code == target.languageCode else { return true }
        return script(of: source) != script(of: target)
    }

    /// The reader's language: the first preferred language.
    static var reader: Locale.Language {
        Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
    }
}
