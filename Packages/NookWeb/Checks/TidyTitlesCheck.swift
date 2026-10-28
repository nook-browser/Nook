// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/TidyTitles.swift Packages/NookWeb/Checks/TidyTitlesCheck.swift -o /tmp/tt && /tmp/tt

import Foundation

@main
struct TidyTitlesCheck {
    static func tidy(_ title: String, _ url: String) -> String {
        TidyTitles.tidy(title: title, url: URL(string: url)!)
    }

    static func expect(_ title: String, _ url: String, _ want: String, line: UInt = #line) {
        let got = tidy(title, url)
        precondition(got == want, "line \(line): \(title) on \(url) gave \(got), wanted \(want)")
    }

    static func main() {
        // Gmail: counter, address and product name go; the fragment names the folder.
        expect("(3) Inbox - Gmail", "https://mail.google.com/mail/u/0/#inbox", "Inbox")
        expect("Inbox (3) - me@example.com - Gmail", "https://mail.google.com/mail/u/0/#inbox", "Inbox")
        expect("Sent Mail - me@example.com - Gmail", "https://mail.google.com/mail/u/0/#sent", "Sent Mail")
        expect("Lunch on Friday? - me@example.com - Gmail", "https://mail.google.com/mail/u/0/#inbox/FMfcgzGx", "Lunch on Friday?")
        expect("Receipts - me@example.com - Gmail", "https://mail.google.com/mail/u/1/#label/Receipts", "Receipts")

        expect("Inbox - me@my-company.com - Gmail", "https://mail.google.com/mail/u/0/#inbox", "Inbox")
        expect("Invoice (2)", "https://mail.google.com/mail/u/0/#inbox/FMfcgzGx", "Invoice (2)")
        expect("Invoice (2) - me@example.com - Gmail", "https://mail.google.com/mail/u/0/#inbox/FMfcgzGx", "Invoice (2)")

        // X and Twitter.
        expect("Home / X", "https://x.com/home", "Home")
        expect("(2) Notifications / X", "https://x.com/notifications", "Notifications")
        expect("Jane Doe (@jane) / X", "https://twitter.com/jane", "Jane Doe (@jane)")
        expect("Jane on X: \"hello there\" / X", "https://x.com/jane/status/1", "Jane on X: \"hello there\"")

        // Wikipedia, YouTube, GitHub, LinkedIn, Reddit, Slack, Notion.
        expect("Swift (programming language) - Wikipedia", "https://en.wikipedia.org/wiki/Swift_(programming_language)", "Swift (programming language)")
        expect("Arc - Wikipedia", "https://fr.wikipedia.org/wiki/Arc", "Arc")
        expect("Cool video - YouTube", "https://www.youtube.com/watch?v=abc", "Cool video")
        expect("(5) Cool video - YouTube", "https://www.youtube.com/watch?v=abc", "Cool video")
        expect("GitHub - nook-browser/Nook: A fast browser", "https://github.com/nook-browser/Nook", "nook-browser/Nook: A fast browser")
        expect("Fix the sidebar by someone · Pull Request #12 · nook-browser/Nook · GitHub", "https://github.com/nook-browser/Nook/pull/12", "Fix the sidebar by someone · Pull Request #12 · nook-browser/Nook")
        expect("Feed | LinkedIn", "https://www.linkedin.com/feed/", "Feed")
        expect("(4) Messaging | LinkedIn", "https://www.linkedin.com/messaging/", "Messaging")
        expect("Reddit - The heart of the internet", "https://www.reddit.com/", "Reddit")
        expect("A fine post : swift - Reddit", "https://www.reddit.com/r/swift/comments/1/a_fine_post/", "A fine post : swift")
        expect("general - Acme - 3 new items - Slack", "https://app.slack.com/client/T1/C1", "general - Acme")
        expect("* general - Acme - Slack", "https://app.slack.com/client/T1/C1", "general - Acme")
        expect("Roadmap | Notion", "https://www.notion.so/Roadmap-123", "Roadmap")

        // Google Docs family: the path names the product.
        expect("Budget - Google Docs", "https://docs.google.com/document/d/1/edit", "Budget")
        expect("Budget - Google Sheets", "https://docs.google.com/spreadsheets/d/1/edit", "Budget")
        expect("Pitch - Google Slides", "https://docs.google.com/presentation/d/1/edit", "Pitch")

        // Stack Overflow, Amazon.
        expect("swift - How do I sort? - Stack Overflow", "https://stackoverflow.com/questions/1", "swift - How do I sort?")
        expect("Amazon.com: Echo Dot (5th Gen) : Electronics", "https://www.amazon.com/dp/B09", "Echo Dot (5th Gen)")
        expect("Amazon.co.uk: Kettle : Home & Kitchen", "https://www.amazon.co.uk/dp/B09", "Kettle")

        // Search results show the query.
        expect("arc browser - Google Search", "https://www.google.com/search?q=arc+browser&sourceid=chrome", "arc browser")
        expect("c++ tutorial - Google Search", "https://www.google.co.uk/search?q=c%2B%2B+tutorial", "c++ tutorial")
        expect("nook browser at DuckDuckGo", "https://duckduckgo.com/?q=nook+browser&ia=web", "nook browser")
        expect("swift - Search", "https://www.bing.com/search?q=swift%20lang", "swift lang")
        expect("hello - Kagi Search", "https://kagi.com/search?q=hello", "hello")
        precondition(TidyTitles.result(title: "x", url: URL(string: "https://www.google.com/search?q=arc")!).showsSite)
        precondition(TidyTitles.result(title: "x", url: URL(string: "https://www.google.com/search?q=arc")!).siteName == "Google")

        // Left alone.
        expect("Maps", "https://www.google.com/maps?q=paris", "Maps")
        expect("arc - Google Search", "https://www.google.com/search", "arc - Google Search")
        expect("Hello - Gmail", "https://google.evil.com/search?q=x", "Hello - Gmail")
        expect("Inbox - Gmail", "https://mail.google.com.evil.com/#inbox", "Inbox - Gmail")
        expect("Home / X", "https://notx.com/home", "Home / X")
        expect("Home / X", "https://fakex.com/", "Home / X")
        expect("Some Page", "https://example.com/", "Some Page")
        expect("(7) Some Page", "https://example.com/", "Some Page")
        expect("(draft) notes", "https://example.com/", "(draft) notes")
        expect("2024 (3) results", "https://example.com/", "2024 (3) results")
        expect("(3)", "https://example.com/", "(3)")
        expect("- YouTube", "https://www.youtube.com/", "- YouTube")
        expect("", "https://example.com/", "")
        expect("Swift - Wikipedia", "https://wikipedia.org.evil.com/", "Swift - Wikipedia")
        print("TidyTitlesCheck passed")
    }
}
