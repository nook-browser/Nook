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
    /// The sample's language, or the page's declared `lang` when the text is too ambiguous.
    static func detect(sample: String, declared: String?) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
           language != .undetermined, confidence >= 0.5 {
            return Locale.Language(identifier: language.rawValue)
        }
        guard let declared = declared?.trimmingCharacters(in: .whitespaces), !declared.isEmpty else { return nil }
        return Locale.Language(identifier: declared)
    }

    /// Different language, or the same one in another script (Simplified and Traditional
    /// Chinese). Regional variants (en-GB, en-US) count as the same.
    static func needsTranslation(_ source: Locale.Language, into target: Locale.Language) -> Bool {
        guard let code = source.languageCode, code == target.languageCode else { return true }
        let sourceScript = Locale.Language(identifier: source.maximalIdentifier).script
        let targetScript = Locale.Language(identifier: target.maximalIdentifier).script
        return sourceScript != targetScript
    }

    /// The reader's language: the first preferred language.
    static var reader: Locale.Language {
        Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
    }
}
