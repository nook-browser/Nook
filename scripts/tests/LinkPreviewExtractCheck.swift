// Licensed under GPL-3.0. See LICENSE.
// swiftc Nook/Managers/LinkPreview/LinkPreviewExtract.swift scripts/tests/LinkPreviewExtractCheck.swift -o /tmp/lp && /tmp/lp

import Foundation

@main
struct LinkPreviewExtractCheck {
    static func main() {
        let base = URL(string: "https://example.com/posts/1")!
        let html = """
        <html><head>
        <title>Fallback &amp; Title</title>
        <meta content="An article about &quot;things&quot;" name="description">
        <meta property="og:title" content="The Real Title">
        <meta property="og:image" content="/img/lead.jpg">
        <script>var p = "<p>not text, this is inside a script and must never be read</p>";</script>
        </head><body>
        <nav><p>Navigation paragraph that is long enough to count but must be dropped</p></nav>
        <p>Short.</p>
        <p>The first real paragraph is long enough to be <b>kept</b> in the summary text.</p>
        <p>A second paragraph&nbsp;also long enough to be kept, with an entity &mdash; here.</p>
        </body></html>
        """
        let page = LinkPreviewExtract.page(fromHTML: html, baseURL: base)
        precondition(page.title == "The Real Title", "og:title wins: \(String(describing: page.title))")
        precondition(page.description == "An article about \"things\"", "content-first meta: \(String(describing: page.description))")
        precondition(page.imageURL?.absoluteString == "https://example.com/img/lead.jpg")
        let iconed = LinkPreviewExtract.page(fromHTML: "<head><link href='/i.png' rel='shortcut icon'></head>", baseURL: base)
        precondition(iconed.iconURL?.absoluteString == "https://example.com/i.png")
        precondition(LinkPreviewExtract.page(fromHTML: "<head><link rel='stylesheet' href='/a.css'></head>", baseURL: base).iconURL == nil)
        precondition(page.text.contains("first real paragraph is long enough to be kept"))
        precondition(page.text.contains("also long enough to be kept, with an entity — here."))
        precondition(!page.text.contains("inside a script") && !page.text.contains("Navigation") && !page.text.contains("Short."))

        let bare = LinkPreviewExtract.page(fromHTML: "<title> Only  a\ntitle </title>", baseURL: base)
        precondition(bare.title == "Only a title" && bare.description == nil && bare.imageURL == nil && bare.text.isEmpty)

        let script = LinkPreviewExtract.page(fromHTML: #"<meta property="og:image" content="javascript:alert(1)">"#, baseURL: base)
        precondition(script.imageURL == nil, "only web images")

        let long = "<p>" + String(repeating: "word ", count: 2000) + "</p>"
        precondition(LinkPreviewExtract.page(fromHTML: long, baseURL: base).text.count <= LinkPreviewExtract.maxText)
        print("LinkPreviewExtractCheck passed")
    }
}
