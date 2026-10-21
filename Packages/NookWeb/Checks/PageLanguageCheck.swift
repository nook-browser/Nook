// Licensed under GPL-3.0. See LICENSE.
//
//  PageLanguageCheck.swift
//  Nook
//
//  When a page counts as foreign to the reader. Compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/PageLanguage.swift \
//           Packages/NookWeb/Checks/PageLanguageCheck.swift -o /tmp/page-language-check && /tmp/page-language-check
//

import Foundation

@main
struct PageLanguageCheck {
    static func main() {
        func lang(_ id: String) -> Locale.Language { Locale.Language(identifier: id) }
        for (a, b) in [("en-GB", "en-US"), ("en", "en-US"), ("zh-Hans", "zh-CN"), ("pt-BR", "pt-PT"), ("de", "de-CH")] {
            precondition(!PageLanguage.needsTranslation(lang(a), into: lang(b)), "\(a) reads as \(b)")
        }
        for (a, b) in [("fr", "en-US"), ("zh-Hans", "zh-Hant"), ("ja", "en"), ("sr-Latn", "sr-Cyrl")] {
            precondition(PageLanguage.needsTranslation(lang(a), into: lang(b)), "\(a) needs translating into \(b)")
        }

        let german = "Die Bundesregierung hat am Mittwoch neue Maßnahmen beschlossen, die den Ausbau der erneuerbaren Energien beschleunigen sollen."
        precondition(PageLanguage.detect(sample: german, declared: "en")?.languageCode == "de", "text wins over a wrong lang attribute")
        precondition(PageLanguage.detect(sample: "", declared: "ja")?.languageCode == "ja", "empty text falls back to lang")
        precondition(PageLanguage.detect(sample: "", declared: " ") == nil, "nothing to go on")
        print("PageLanguageCheck passed")
    }
}
