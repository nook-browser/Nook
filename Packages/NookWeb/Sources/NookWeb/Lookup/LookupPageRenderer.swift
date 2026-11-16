// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPageRenderer.swift
//  NookWeb
//
//  The page a lookup becomes: static HTML with no script, every string from the web escaped,
//  every link an https result URL and every image a file in the lookup's own folder.
//  Foundation only, so `Checks/LookupPageCheck.swift` can compile it.
//

import Foundation

public enum LookupPageRenderer {
    private static let maxTitle = 200
    private static let maxPhotos = 5

    public static func html(_ record: LookupRecord) -> String {
        let answerTitle = record.answer?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: String
        var title = record.request
        switch record.outcome {
        case .running, .stopped:
            body = face("💤") + heading(record.request) + searchInstead(record)
        case .nothingFound:
            body = nothing(record)
        case .failed:
            body = notesBody(record) ?? nothing(record)
        case .done:
            if record.sources.contains(where: { $0.prefilledURL != nil }) {
                body = heading(record.request) + placesBody(record)
            } else if let answer = record.answer, !answer.isEmpty {
                if !answerTitle.isEmpty { title = answerTitle }
                body = answerBody(answer, title: title, record)
            } else {
                body = notesBody(record) ?? nothing(record)
            }
        }
        return document(title: title, accent: record.accentHex, body: body)
    }

    // MARK: - Layouts

    private static func answerBody(_ answer: LookupAnswer, title: String, _ record: LookupRecord) -> String {
        let ask = "<p class=\"ask\">\(magnifier)\(escaped(record.request))</p>"
        if answer.options.isEmpty {
            let photos = record.sources.compactMap { image($0.imageFile) }.prefix(maxPhotos).joined()
            return (photos.isEmpty ? "" : "<div class=\"photos\">\(photos)</div>")
                + ask + heading(title) + points(answer.points, record) + sources(record, numbered: true)
                + answer.sections.map { "<h2>\(escaped($0.heading))</h2>" + points($0.points, record) }.joined()
        }
        let intro = answer.intro.trimmingCharacters(in: .whitespacesAndNewlines)
        return ask + heading(title) + (intro.isEmpty ? "" : "<p class=\"intro\">\(escaped(intro))</p>")
            + "<div class=\"cards\">" + cards(answer.options, record) + "</div>" + sources(record)
    }

    private static func points(_ points: [LookupPoint], _ record: LookupRecord) -> String {
        guard !points.isEmpty else { return "" }
        return "<ul class=\"points\">" + zip(points, glyphs(for: points.map(\.label))).enumerated().map { index, pair in
            let mark = cite(pair.0.source, record)
            return "<li style=\"--i:\(index)\">\(tile(pair.1))<p><b>\(escaped(pair.0.label))</b>\(escaped(pair.0.sentence))\(mark.isEmpty ? "" : "&#160;" + mark)</p></li>"
        }.joined() + "</ul>"
    }

    /// The source's number, linked to its page when that page is https.
    private static func cite(_ number: Int, _ record: LookupRecord) -> String {
        guard record.sources.indices.contains(number - 1) else { return "" }
        guard let href = link(record.sources[number - 1].hit.url) else { return "<span class=\"cite\">\(number)</span>" }
        return "<a class=\"cite\" href=\"\(href)\">\(number)</a>"
    }

    /// The choices, each with its page's picture, or a glyph tile where the page gave none.
    private static func cards(_ options: [LookupOption], _ record: LookupRecord) -> String {
        let sources = options.map { record.sources.indices.contains($0.source - 1) ? record.sources[$0.source - 1] : nil }
        let pictures = sources.map { $0.flatMap { image($0.imageFile, class: "pic") } }
        var spare = glyphs(for: zip(options, pictures).filter { $1 == nil }.map(\.0.name)).makeIterator()
        return zip(options, zip(sources, pictures)).map { option, found in
            let open = found.0.flatMap { source in
                link(source.hit.url).map { "<a class=\"open\" href=\"\($0)\">Open on \(escaped(host(source.hit.url)))</a>" }
            } ?? ""
            return "<article class=\"card\">\(found.1 ?? tile(spare.next() ?? "", class: "pic"))<div><h3>\(escaped(option.name))</h3>"
                + "<p>\(escaped(option.detail))</p>\(open)</div></article>"
        }.joined()
    }

    /// A booking: one card a place. Nothing here was written across pages.
    private static func placesBody(_ record: LookupRecord) -> String {
        "<div class=\"cards\">" + record.sources.enumerated().map { place($1, number: $0 + 1, record) }.joined() + "</div>" + sources(record)
    }

    /// A place's card: its booking page's picture, a line about it, what it offers at the asked time
    /// and its address set to the party and day. `#do/<number>` asks Nook to press that time.
    private static func place(_ source: LookupSource, number: Int, _ record: LookupRecord) -> String {
        let target = source.prefilledURL ?? source.hit.url
        let href = link(target)
        let name = String((source.name.isEmpty ? (source.title.isEmpty ? source.hit.title : source.title) : source.name).prefix(maxTitle))
        let shot = image(source.shotFile, class: "shot").map { picture in
            href.map { "<a class=\"window\" href=\"\($0)\">\(picture)</a>" } ?? "<div class=\"window\">\(picture)</div>"
        } ?? ""
        let about = source.about.isEmpty ? "" : "<p>\(escaped(source.about))</p>"
        let times: String
        if source.prefilledURL != nil, !source.wasRead {
            times = "<p class=\"times\">\(tile("🙈"))This site would not load in the background.</p>"
        } else {
            times = LookupTimes.line(place: name, asked: record.booking?.time, times: source.times).map { "<p class=\"times\">\(tile("🕘"))\(escaped($0))</p>" } ?? ""
        }
        let open = href.map { "<a class=\"open\" href=\"\($0)\">Open on \(escaped(host(target)))</a>" } ?? ""
        var pick = ""
        if source.prefilledURL != nil, source.wasRead, let asked = record.booking?.time, LookupTimes.offers(asked, in: source.times),
           let shown = LookupTimes.display(asked) {
            pick = "<a class=\"open go\" href=\"#do/\(number)\">Pick \(escaped(shown)) for Me</a>"
        }
        return "<article class=\"card place\">\(shot)<div><h3>\(escaped(name))</h3>\(about)\(times)<p class=\"acts\">\(pick)\(open)</p></div></article>"
    }

    /// The pages as a panel of rows. `numbered` shows the number a point cites a page by.
    private static func sources(_ record: LookupRecord, numbered: Bool = false) -> String {
        guard !record.sources.isEmpty else { return "" }
        return "<section class=\"panel sources\"><h2>Pages Read</h2>" + record.sources.enumerated().map { index, source in
            row(source, number: numbered ? index + 1 : nil, unread: !source.wasRead)
        }.joined() + "</section>"
    }

    /// One page: its icon, or its site's first letter, then its title and site.
    private static func row(_ source: LookupSource, number: Int? = nil, unread: Bool = false) -> String {
        let name = escaped(String((source.title.isEmpty ? source.hit.title : source.title).prefix(maxTitle)))
        let site = host(source.hit.url)
        let icon = image(source.iconFile) ?? escaped(String(site.prefix(1)).uppercased())
        let inner = "<span class=\"fav\" aria-hidden=\"true\">\(icon)</span><span class=\"what\"><b>\(name)</b><small>\(escaped(site))</small>"
            + (unread ? "<small>This site would not load in the background.</small>" : "") + "</span>"
            + (number.map { "<span class=\"cite\">\($0)</span>" } ?? "")
        return link(source.hit.url).map { "<a class=\"row\" href=\"\($0)\">\(inner)</a>" } ?? "<div class=\"row\">\(inner)</div>"
    }

    /// Each page's notes under its title, for when the answer could not be written.
    private static func notesBody(_ record: LookupRecord) -> String? {
        let noted = record.sources.filter { source in
            let notes = source.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return !notes.isEmpty && notes.uppercased() != "NONE"
        }
        guard !noted.isEmpty else { return nil }
        return face("🗒️") + heading(record.request) + "<h2>What Each Page Says</h2>" + noted.map { source in
            let lines = source.notes.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t")) }
                .filter { !$0.isEmpty && $0.uppercased() != "NONE" }
            return "<section class=\"panel says\">\(row(source))<ul class=\"notes\">" + lines.map { "<li>\(escaped($0))</li>" }.joined() + "</ul></section>"
        }.joined() + searchInstead(record)
    }

    /// The one line for a lookup with nothing to show, then whatever pages it did find.
    private static func nothing(_ record: LookupRecord) -> String {
        face("🪹") + heading(record.request) + "<p class=\"intro\">Nothing came back for this.</p>" + searchInstead(record) + sources(record)
    }

    /// The same text as an ordinary search. The address is the person's own search engine, not
    /// something a page supplied, so plain http is allowed: a local engine has no certificate.
    private static func searchInstead(_ record: LookupRecord) -> String {
        guard let url = record.searchURL, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return "" }
        return "<p class=\"end\"><a class=\"open go\" href=\"\(escaped(url.absoluteString))\">\(magnifier)Search the Web Instead</a></p>"
    }

    /// The page's title and the squiggle under it.
    private static func heading(_ text: String) -> String {
        "<h1\(text.count > 60 ? " class=\"long\"" : "")>\(escaped(String(text.prefix(maxTitle))))</h1>"
            + "<svg class=\"squig\" viewBox=\"0 0 64 12\" aria-hidden=\"true\"><path pathLength=\"1\" d=\"M2 6q5-8 10 0t10 0 10 0 10 0 10 0 10 0\"/></svg>"
    }

    // MARK: - Glyphs

    private static let magnifier = "<svg class=\"mag\" viewBox=\"0 0 16 16\" aria-hidden=\"true\"><circle cx=\"7\" cy=\"7\" r=\"4.5\"/><path d=\"M10.5 10.5 14 14\"/></svg>"

    /// A small rounded square holding one glyph. Callers pass glyphs from this file only.
    private static func tile(_ glyph: String, class name: String = "") -> String {
        "<span class=\"tile\(name.isEmpty ? "" : " " + name)\" aria-hidden=\"true\">\(glyph)</span>"
    }

    /// The large tile that opens a page with nothing to read.
    private static func face(_ glyph: String) -> String { tile(glyph, class: "face") }

    /// Words a label may hold and the glyph each gets. A word of five letters or more also
    /// matches longer words that start with it.
    private static let glyphTable: [(glyph: String, words: [String])] = [
        ("📜", "histor origin heritage legacy ancient tradition past founding"),
        ("🏛️", "architect landmark monument museum"),
        ("🎨", "style design art aesthetic color decor"),
        ("🎬", "film movie cinema scene"),
        ("🎵", "music song album sound audio concert"),
        ("📍", "locat where address neighborhood area map place nearby direction"),
        ("🚪", "close closed closing closure exit"),
        ("🕘", "hour time schedule when duration wait"),
        ("📅", "date year timeline calendar period decade season"),
        ("🏷️", "name renam brand label title"),
        ("💰", "price pricing cost fee budget money afford value deal saving"),
        ("⭐", "rating review verdict reputation award quality"),
        ("👍", "pros benefit advantage strength upside"),
        ("👎", "cons drawback downside weakness disadvantage"),
        ("⚠️", "risk warning danger caution safety concern issue problem limitation"),
        ("🪧", "sign signage billboard"),
        ("🏢", "building office tower"),
        ("🛠️", "construct build built renovat repair install maintenance restor setup"),
        ("🌳", "park nature tree garden outdoor forest trail"),
        ("💧", "pond water lake river pool ocean beach"),
        ("🍲", "soup stew broth bean lentil chili curry"),
        ("🍜", "ramen noodle pasta"),
        ("🍗", "chicken turkey wings"),
        ("🍅", "tomato vegetable veggie"),
        ("🥗", "salad bowl"),
        ("🍕", "pizza"),
        ("🍔", "burger sandwich"),
        ("🌮", "taco burrito"),
        ("🍣", "sushi seafood"),
        ("🍰", "cake dessert cookie sweet bakery"),
        ("🍷", "wine cocktail bar beer brewery"),
        ("☕", "coffee cafe tea drink"),
        ("🍽️", "food menu dining restaurant dish cuisine kitchen meal recipe"),
        ("💻", "laptop computer macbook desktop"),
        ("🎧", "headphone earbud speaker"),
        ("📷", "camera photo lens"),
        ("👟", "shoe sneaker running boot"),
        ("🎮", "game gaming console"),
        ("🏨", "hotel stay lodging resort"),
        ("✈️", "flight airline airport"),
        ("👥", "people community audience crowd visitor team staff who famil"),
        ("🚀", "performance speed fast launch"),
        ("⚡", "power electric voltage charging"),
        ("🔋", "battery energy efficien"),
        ("🌡️", "climate weather temperature heat cold"),
        ("🌍", "environment world global planet country"),
        ("📐", "size dimension scale measure spec weight"),
        ("📱", "display screen phone app software device"),
        ("🧪", "science research study test experiment"),
        ("🩺", "health medical symptom treatment care"),
        ("🎟️", "ticket admission event booking reserv"),
        ("🚗", "travel transport parking driving car route getting"),
        ("🔮", "future upcoming next outlook"),
        ("🟢", "current today now status active"),
        ("🏠", "home house housing residential"),
        ("🧰", "use usage tool method process how"),
        ("🏆", "winner champion achievement success"),
        ("💼", "business company career industry market economy job work"),
        ("📚", "book reading learn education school guide lesson"),
        ("⚖️", "legal rule policy comparison versus difference"),
        ("🎭", "culture cultural theater theatre festival"),
        ("🐾", "animal wildlife pet dog cat bird"),
        ("💡", "idea tip fact summary overview key takeaway insight"),
    ].map { ($0.0, $0.1.split(separator: " ").map(String.init)) }

    private static let spareGlyphs = ["✨", "🌱", "🧩", "🎈", "🍀", "🔖", "🪄", "🌟", "🫧", "🧭"]

    /// The glyph for a label: the first of its words the table knows, else a spare picked by a
    /// hash of the label, so a label always gets the same one. Nothing of the label comes out.
    static func glyph(for label: String) -> String {
        for word in label.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let row = glyphTable.first(where: { $0.words.contains { word == $0 || word == $0 + "s" || ($0.count > 4 && word.hasPrefix($0)) } }) {
                return row.glyph
            }
        }
        return spareGlyphs[spare(label, 0)]
    }

    private static func spare(_ label: String, _ step: Int) -> Int {
        Int((label.unicodeScalars.reduce(UInt(5381)) { ($0 &* 33) ^ UInt($1.value) } &+ UInt(step)) % UInt(spareGlyphs.count))
    }

    /// A glyph a label, none twice in one list while the spares last.
    static func glyphs(for labels: [String]) -> [String] {
        var used = Set<String>()
        return labels.map { label in
            var glyph = glyph(for: label), step = 0
            while used.contains(glyph), step < spareGlyphs.count {
                glyph = spareGlyphs[spare(label, step)]
                step += 1
            }
            used.insert(glyph)
            return glyph
        }
    }

    // MARK: - Safety

    /// The escaped address of an https page, the only kind this page links to.
    private static func link(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return escaped(url.absoluteString)
    }

    /// An image tag for a file in the lookup's folder. A name with a path or a scheme is refused.
    private static func image(_ file: String?, class name: String? = nil) -> String? {
        guard let file, !file.isEmpty, !file.contains("/"), !file.contains(":"), !file.contains("\\"), !file.hasPrefix(".") else { return nil }
        return "<img\(name.map { " class=\"\($0)\"" } ?? "") src=\"\(escaped(file))\" alt=\"\">"
    }

    private static func host(_ url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Document

    // `--ink` is the accent held to a lightness that reads on the page in each appearance.
    private static func document(title: String, accent: String, body: String) -> String {
        let isColor = accent.count == 7 && accent.hasPrefix("#") && accent.dropFirst().allSatisfy(\.isHexDigit)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file:; style-src 'unsafe-inline'">
        <title>\(escaped(String(title.prefix(maxTitle))))</title><style>
        :root{--accent:\(isColor ? accent : LookupRecord.defaultAccent)}
        :root{color-scheme:light dark;--bg:light-dark(#f5f5f7,#121214);--fg:light-dark(#1d1d21,#f3f3f5);--soft:light-dark(#3d3d45,#cfcfd6);--dim:light-dark(#6c6c75,#9b9ba4);--panel:light-dark(#fff,#1c1c20);--line:light-dark(#0000000f,#ffffff12);--ink:color-mix(in srgb,var(--accent) 70%,var(--fg))}
        @supports(color:oklch(from red clamp(0,l,1) c h)){:root{--ink:light-dark(oklch(from var(--accent) clamp(.4,l,.54) c h),oklch(from var(--accent) clamp(.74,l,.88) c h))}}
        :root{--tile:color-mix(in srgb,var(--ink) 14%,var(--panel));--wash:color-mix(in srgb,var(--ink) 7%,var(--panel))}
        html{background:var(--bg)}
        body{margin:0;color:var(--fg);font:17px/1.55 ui-rounded,-apple-system,system-ui,sans-serif;overflow-wrap:anywhere;overflow-x:hidden;-webkit-font-smoothing:antialiased;background:linear-gradient(color-mix(in srgb,var(--accent) 16%,var(--bg)),var(--bg)) top/100% 420px no-repeat}
        ::selection{background:color-mix(in srgb,var(--ink) 30%,transparent)}
        main{--pad:24px;--edge:max(50vw - 336px,var(--pad));max-width:672px;margin:0 auto;padding:44px var(--pad) 96px}
        a{color:var(--ink)}a:focus-visible{outline:2px solid var(--ink);outline-offset:3px}
        .photos{display:flex;gap:14px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;margin:0 calc(-1*var(--edge)) 30px;padding:0 var(--edge);scroll-padding:0 var(--edge)}
        .photos::-webkit-scrollbar{display:none}
        .photos img{flex:none;width:84%;aspect-ratio:3/2;object-fit:cover;border-radius:28px;scroll-snap-align:start;outline:1px solid var(--line);outline-offset:-1px}
        .photos img:only-child{width:100%}
        .ask{text-align:center;margin:0 0 12px;color:var(--dim);font-size:14px;font-weight:600}
        .mag{flex:none;width:1em;height:1em;margin-right:.4em;vertical-align:-.12em;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round}
        h1{font-size:clamp(30px,6vw,44px);font-weight:800;line-height:1.1;letter-spacing:-.015em;text-align:center;text-wrap:balance;color:var(--ink);margin:0}
        h1.long{font-size:clamp(22px,4vw,30px);line-height:1.2}
        .squig{display:block;width:64px;height:12px;margin:22px auto 36px;overflow:visible;fill:none;stroke:var(--ink);stroke-width:3;stroke-linecap:round}
        .squig path{stroke-dasharray:1;animation:draw .7s .15s ease-out backwards}
        h2{font-size:22px;font-weight:800;letter-spacing:-.01em;color:var(--ink);margin:52px 0 20px}
        .squig+h2{margin-top:16px}
        .intro{font-size:19px;text-align:center;text-wrap:balance;color:var(--soft);margin:-10px 0 30px}
        .tile{flex:none;display:grid;place-items:center;width:40px;height:40px;border-radius:12px;background:var(--tile);font-size:20px;line-height:1;rotate:-4deg;transition:rotate .25s,scale .25s}
        .points{list-style:none;margin:0;padding:0;display:grid;gap:22px}
        .points li{display:grid;grid-template-columns:40px 1fr;gap:16px}
        .points .tile{animation:pop .5s calc(var(--i)*70ms + .3s) cubic-bezier(.3,1.5,.5,1) backwards}
        .points li:nth-child(even) .tile,.card:nth-child(even) .tile{rotate:4deg}
        .points li:hover .tile,.card:hover .tile{rotate:0deg;scale:1.08}
        .points p{margin:0;color:var(--soft)}
        .points b{display:block;font-weight:700;color:var(--fg)}
        .cite{flex:none;padding:2px 6px;border-radius:10px;background:var(--tile);color:var(--ink);font-size:11px;font-weight:700;line-height:1.3;text-decoration:none;vertical-align:2px}
        a.cite:hover{background:var(--ink);color:var(--bg)}
        .panel{background:var(--panel);border-radius:24px;padding:10px;margin:14px 0 0;box-shadow:0 0 0 1px var(--line)}
        .sources{margin-top:44px}
        .panel h2{font-size:13px;font-weight:600;letter-spacing:0;color:var(--dim);margin:6px 10px 4px}
        .row{display:flex;gap:12px;align-items:center;padding:9px 10px;border-radius:16px;color:inherit;text-decoration:none}
        a.row:hover{background:var(--wash)}
        .fav{flex:none;display:grid;place-items:center;width:36px;height:36px;border-radius:11px;background:var(--tile);color:var(--ink);font-size:16px;font-weight:800}
        .fav img{width:20px;height:20px;border-radius:5px}
        .what{flex:1;display:grid;min-width:0;line-height:1.3}
        .what b{font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .what small{font-size:13px;color:var(--dim)}
        .says .what b{white-space:normal}
        .notes{list-style:none;margin:4px 12px 10px 58px;padding:0;display:grid;gap:8px;font-size:16px;line-height:1.45;color:var(--soft)}
        .notes li{position:relative;padding-left:18px}
        .notes li::before{content:"";position:absolute;left:2px;top:.55em;width:6px;height:6px;border-radius:50%;background:var(--ink);opacity:.75}
        .cards{display:grid;gap:14px}
        .card{display:grid;grid-template-columns:96px 1fr;gap:18px;background:var(--panel);border-radius:24px;padding:16px;box-shadow:0 0 0 1px var(--line);transition:translate .2s}
        .card:hover{translate:0 -2px}
        .pic{width:96px;height:96px;border-radius:20px;object-fit:cover;font-size:44px}
        .card h3{font-size:19px;font-weight:800;line-height:1.25;margin:2px 0 6px}
        .card p{margin:0 0 12px;color:var(--soft)}
        .card.place{grid-template-columns:1fr}
        .window{display:block;border-radius:16px;overflow:hidden;background:var(--tile);align-self:start}
        .window::before{content:"";display:block;width:39px;height:22px;margin-left:9px;background:radial-gradient(circle,var(--dim) 3px,#0000 3.8px) 0/13px 100%;opacity:.6}
        .shot{display:block;width:100%;aspect-ratio:4/3;object-fit:cover;object-position:top}
        .card .times{display:flex;gap:10px;font-weight:600;color:var(--fg)}
        .times .tile{width:30px;height:30px;margin-top:-2px;border-radius:9px;font-size:15px}
        .card .acts{display:flex;flex-wrap:wrap;gap:8px;margin:0}
        .end{margin:34px 0 0;text-align:center}
        .open{display:inline-flex;align-items:center;text-decoration:none;font-weight:700;font-size:15px;line-height:1.3;padding:8px 15px;border-radius:99px;background:var(--tile);color:var(--ink);transition:scale .15s}
        .open:hover{background:color-mix(in srgb,var(--ink) 24%,var(--panel))}
        .open:active{scale:.97}
        .go,.go:hover{background:var(--ink);color:var(--bg)}
        .go:hover{filter:brightness(1.08)}
        .face{width:104px;height:104px;border-radius:32px;font-size:52px;background:color-mix(in srgb,var(--ink) 24%,var(--panel));margin:28px auto 30px;rotate:-6deg;animation:pop .6s cubic-bezier(.3,1.5,.5,1) backwards}
        @keyframes draw{from{stroke-dashoffset:1}}
        @keyframes pop{from{opacity:0;scale:.5}}
        @media(min-width:680px){.card.place:has(.window):not(:only-child){grid-template-columns:2fr 3fr}}
        @media(max-width:560px){body{font-size:16px}main{--pad:18px;padding:28px var(--pad) 72px}.card{grid-template-columns:72px 1fr;gap:14px}.pic{width:72px;height:72px;border-radius:16px;font-size:34px}.notes{margin-left:12px}}
        @media print,(prefers-reduced-motion:reduce){*,::before{animation:none!important;transition:none!important}}
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}
