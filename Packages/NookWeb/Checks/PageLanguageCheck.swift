// Licensed under GPL-3.0. See LICENSE.
//
//  PageLanguageCheck.swift
//  Nook
//
//  Which language a page is in and when it counts as foreign to the reader. Compiles the shipped
//  source directly and runs the shipped sampling script in an off-screen web view, from the repo root:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/PageLanguage.swift \
//           Packages/NookWeb/Checks/PageLanguageCheck.swift -o /tmp/page-language-check && /tmp/page-language-check
//

import AppKit
import WebKit

@main
struct PageLanguageCheck {
    @MainActor static func main() async {
        func lang(_ id: String) -> Locale.Language { Locale.Language(identifier: id) }
        for (a, b) in [("en-GB", "en-US"), ("en", "en-US"), ("zh-Hans", "zh-CN"), ("pt-BR", "pt-PT"), ("de", "de-CH")] {
            precondition(!PageLanguage.needsTranslation(lang(a), into: lang(b)), "\(a) reads as \(b)")
        }
        for (a, b) in [("fr", "en-US"), ("zh-Hans", "zh-Hant"), ("ja", "en"), ("sr-Latn", "sr-Cyrl")] {
            precondition(PageLanguage.needsTranslation(lang(a), into: lang(b)), "\(a) needs translating into \(b)")
        }

        func code(_ sample: String, _ declared: String?) -> String? {
            PageLanguage.detect(sample: sample, declared: declared)?.languageCode?.identifier
        }
        func many(_ sentence: String) -> String { String(repeating: sentence + " ", count: 12) }
        let german = "Die Bundesregierung hat am Mittwoch neue Maßnahmen beschlossen, die den Ausbau der erneuerbaren Energien beschleunigen sollen."
        let english = "The committee announced on Wednesday that the new measures would speed up the building of wind farms across the country."
        precondition(code(german, "en") == "de", "text wins over a wrong lang attribute")
        precondition(code("", "ja") == "ja", "empty text falls back to lang")
        precondition(PageLanguage.detect(sample: "", declared: " ") == nil, "nothing to go on")

        // The recognizer judges a string by its first hundred characters or so: a menu in another
        // language ahead of the page's text once named the page.
        let opening = String(german.prefix(60)) + " " + many(english)
        precondition(code(opening, "en") == "en" && code(opening, nil) == "en", "a foreign opening does not name the page")
        precondition(code(many(english), "zh-CN") == "en", "English under a foreign lang attribute")

        // With no model for a language the recognizer names a neighbour; the page knows better.
        let malay = "Malaysia ialah sebuah negara raja berperlembagaan persekutuan di Asia Tenggara yang terdiri daripada tiga belas negeri dan tiga wilayah persekutuan."
        let afrikaans = "Suid-Afrika is 'n land aan die suidpunt van Afrika wat aan Namibië, Botswana en Zimbabwe grens, en sy kuslyn strek oor twee oseane."
        let persian = "ایران کشوری در غرب آسیا است که با مساحت یک میلیون و ششصد و چهل و هشت هزار کیلومتر مربع، هفدهمین کشور بزرگ جهان است."
        for (text, declared) in [(malay, "ms"), (afrikaans, "af"), (persian, "fa")] {
            precondition(code(many(text), declared) == declared, "\(declared) keeps its declared name")
        }

        // A lang that names no language, or one whose script the text is not in, is ignored.
        let japanese = "政府は水曜日、再生可能エネルギーの拡大を加速させる新たな措置を決定した。"
        let korean = "정부는 수요일에 재생 에너지 확대를 가속화하기 위한 새로운 조치를 결정했다고 발표했습니다."
        precondition(code(many(japanese), "jp") == "ja", "jp is a country")
        precondition(code(many(korean), "kr") == "ko", "kr is Kanuri, which is not written in Hangul")
        let traditional = PageLanguage.detect(sample: many("政府週三宣布了新的措施，以加快全國各地再生能源的發展與建設。"), declared: "zh")
        precondition(traditional.map { !PageLanguage.needsTranslation($0, into: lang("zh-Hant")) } == true, "the recognizer supplies the script")

        // A page's own language holds while part of the text is in it, whatever names sit beside it.
        let names = String(repeating: english + " Michał Polański, Wojciech Szczęsny, Łukasz Żółć. ", count: 8)
        precondition(code(names, "en") == "en", "Polish names on an English page")
        precondition(code(many(german) + many(english), nil) == nil, "two languages and no lang attribute name neither")

        // End to end: the sample holds what the page shows, so a hidden menu does not name the page.
        _ = NSApplication.shared
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let loaded = Loaded()
        web.navigationDelegate = loaded
        let menu = "<ul style='display:none'>" + String(repeating: "<li>\(german)</li>", count: 4) + "</ul>"
        await loaded.load("<html><body>\(menu)<p style='visibility:hidden'>\(german)</p><p>\(many(english))</p></body></html>", in: web)
        let script = try! String(contentsOfFile: "Packages/NookWeb/Sources/NookWeb/Resources/page-translate.js", encoding: .utf8)
        let sample = try! await web.callAsyncJavaScript(
            script + "\nreturn window.__nookTranslate.sample();", arguments: [:], in: nil, contentWorld: .world(name: "NookTranslate")
        ) as! [String: Any]
        let text = sample["text"] as! String
        precondition(!text.contains("Bundesregierung") && text.contains("committee"), "hidden text stays out of the sample")
        precondition(code(text, sample["lang"] as? String) == "en", "the page reads as English")

        print("PageLanguageCheck passed")
        exit(0)
    }
}

@MainActor
final class Loaded: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, in web: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            web.loadHTMLString(html, baseURL: URL(string: "https://example.test/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}
