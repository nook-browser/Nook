// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/SearchPage.swift Packages/NookWeb/Checks/SearchPageCheck.swift -o /tmp/sp && /tmp/sp

import Foundation

@main
struct SearchPageCheck {
    static func main() {
        let google = SearchPage.query(in: URL(string: "https://www.google.com/search?q=arc&sourceid=chrome&ie=UTF-8")!)
        precondition(google?.query == "arc" && google?.site == "google.com")
        precondition(SearchPage.query(in: URL(string: "https://www.google.co.uk/search?q=hello%20world")!)?.query == "hello world")
        precondition(SearchPage.query(in: URL(string: "https://duckduckgo.com/?q=nook+browser")!)?.query == "nook browser")
        precondition(SearchPage.query(in: URL(string: "https://search.yahoo.com/search?p=swift")!)?.site == "search.yahoo.com")
        precondition(SearchPage.query(in: URL(string: "https://www.google.com/search?q=c%2B%2B+tutorial")!)?.query == "c++ tutorial")
        // Not results pages.
        precondition(SearchPage.query(in: URL(string: "https://www.google.com/maps?q=paris")!) == nil)
        precondition(SearchPage.query(in: URL(string: "https://notgoogle.com/search?q=x")!) == nil)
        precondition(SearchPage.query(in: URL(string: "https://www.google.com/search")!) == nil)
        precondition(SearchPage.query(in: URL(string: "https://github.com/search?q=nook")!) == nil)
        print("SearchPageCheck passed")
    }
}
