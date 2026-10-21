// Licensed under GPL-3.0. See LICENSE.
//
//  LiveParsersCheck.swift
//  Nook
//
//  Live folder parser check. NookWeb has no test target, so this compiles the shipped source
//  directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/LiveParsers.swift \
//           Packages/NookWeb/Checks/LiveParsersCheck.swift -o /tmp/live-check && /tmp/live-check
//

import Foundation

@main
struct LiveParsersCheck {
    static func main() {
        // Feeds: RSS channel title, CDATA, newest first in document order, capped.
        let rss = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>Example &amp; Co</title>
        <atom:link xmlns:atom="http://www.w3.org/2005/Atom" rel="self" href="https://example.com/feed"/>
        <item><title><![CDATA[First <b>post</b>]]></title><link>https://example.com/1</link></item>
        <item><title>Second</title><link> /2 </link></item>
        <item><title>Bad</title><link>javascript:alert(1)</link></item>
        <item><title>Dup</title><link>https://example.com/1</link></item>
        </channel></rss>
        """
        let parsedRSS = LiveParse.feed(Data(rss.utf8), base: URL(string: "https://example.com/feed")!)!
        precondition(parsedRSS.title == "Example & Co")
        precondition(parsedRSS.items.map(\.url.absoluteString) == ["https://example.com/1", "https://example.com/2"])
        precondition(parsedRSS.items.map(\.title) == ["First post", "Second"])
        precondition(LiveParse.feed(Data(rss.utf8), base: URL(string: "https://example.com")!, limit: 1)!.items.count == 1)

        // Atom: alternate or rel-less link wins over enclosure; relative hrefs resolve.
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Atom Blog</title>
        <entry><title>A</title><link rel="enclosure" href="https://cdn.example.org/a.mp3"/><link rel="alternate" href="/a"/></entry>
        <entry><title>B</title><link href="https://example.org/b"/></entry>
        <entry><title></title><link href="https://example.org/c"/></entry>
        </feed>
        """
        let parsedAtom = LiveParse.feed(Data(atom.utf8), base: URL(string: "https://example.org/feed.atom")!)!
        precondition(parsedAtom.title == "Atom Blog")
        precondition(parsedAtom.items.map(\.url.absoluteString) == ["https://example.org/a", "https://example.org/b", "https://example.org/c"])
        precondition(parsedAtom.items[2].title == "https://example.org/c")
        precondition(LiveParse.feed(Data("<html><body>nope</body></html>".utf8), base: URL(string: "https://x.com")!) == nil)
        precondition(LiveParse.feed(Data("not xml".utf8), base: URL(string: "https://x.com")!) == nil)

        // Notifications: thread anchors only, query stripped, markdown-title preferred, deduped.
        let html = """
        <a href="/notifications?query=repo%3Ao%2Fr">Filter</a>
        <a href="/o/r">Repo</a>
        <a class="notification-list-item-link" href="https://github.com/o/r/issues/12?notification_referrer_id=NT_abc&amp;x=1#issuecomment-9">
          <span>o/r #12</span><p class="markdown-title  text-bold">Fix &lt;crash&gt;</p></a>
        <a href="/o/r/pull/3?notification_referrer_id=1"><p class="markdown-title">Add thing</p></a>
        <a href="/o/r/pull/3">Add thing again</a>
        <a href="/o/r/discussions/7">  Talk
          about it </a>
        <a href="/o/r/commit/abc123">Commit</a>
        <a href="/o/r/releases/tag/v1.0">v1.0</a>
        <a href="/o/r/issues/new">New</a>
        <a href="https://evil.com/o/r/issues/1">Evil</a>
        """
        let threads = LiveParse.githubNotifications(html: html)
        precondition(threads.map(\.url.absoluteString) == [
            "https://github.com/o/r/issues/12", "https://github.com/o/r/pull/3", "https://github.com/o/r/discussions/7",
            "https://github.com/o/r/commit/abc123", "https://github.com/o/r/releases/tag/v1.0",
        ])
        precondition(threads.map(\.title) == ["Fix <crash>", "Add thing", "Talk about it", "Commit", "v1.0"])

        // Issues JSON: any object with a title and an issue URL, at any depth.
        let issues = """
        {"payload":{"route":{"results":[
          {"title":"One","permalink":"https://github.com/o/r/issues/1"},
          {"title":"PR","url":"https://github.com/o/r/pull/2"},
          {"node":{"title":"Two","url":"https://github.com/o/r/issues/2"}},
          {"title":"One again","html_url":"https://github.com/o/r/issues/1"}
        ]}}}
        """
        precondition(LiveParse.githubIssues(Data(issues.utf8))!.map(\.title) == ["One", "Two"])
        precondition(LiveParse.githubIssues(Data("<html>".utf8)) == nil)

        // Asana: workspaces, incomplete only, due ascending, undated last, permalink shapes only.
        precondition(LiveParse.asanaWorkspaces(Data(#"{"data":{"gid":"1","workspaces":[{"gid":"10","name":"W"},{"gid":"11"}]}}"#.utf8)) == ["10", "11"])
        let tasks = LiveParse.asanaTasks(Data("""
        {"data":[
          {"gid":"1","name":"Later","permalink_url":"https://app.asana.com/0/0/1001","due_on":"2026-11-02","completed":false},
          {"gid":"2","name":"Undated","permalink_url":"https://app.asana.com/0/0/1002","due_on":null,"completed":false},
          {"gid":"3","name":"Soon","permalink_url":"https://app.asana.com/1/55/project/66/task/1003/f","due_on":"2026-10-21","completed":false},
          {"gid":"4","name":"Done","permalink_url":"https://app.asana.com/0/0/1004","due_on":"2026-10-01","completed":true},
          {"gid":"5","name":"Odd","permalink_url":"https://example.com/0/0/1005","due_on":"2026-10-01"}
        ]}
        """.utf8))!
        precondition(LiveParse.rankAsanaTasks(tasks).map(\.title) == ["Soon", "Later", "Undated"])
        precondition(LiveParse.rankAsanaTasks(tasks, limit: 1).count == 1)
        precondition(!LiveParse.ownsAsanaTask(URL(string: "https://app.asana.com/0/inbox")!))
        precondition(LiveParse.ownsAsanaTask(URL(string: "https://app.asana.com/1/11/project/22/task/33")!))
        precondition(LiveParse.ownsAsanaTask(URL(string: "https://app.asana.com/1/11/task/33/f")!))
        precondition(!LiveParse.ownsAsanaTask(URL(string: "https://app.asana.com/1/11/project/22/list/44")!))

        // Owners.
        precondition(LiveParse.ownsIssue(URL(string: "https://github.com/o/r/issues/5")!))
        precondition(!LiveParse.ownsIssue(URL(string: "https://github.com/o/r/pull/5")!))
        precondition(LiveParse.ownsNotification(URL(string: "https://github.com/o/r/pull/5")!))
        precondition(!LiveParse.ownsNotification(URL(string: "https://github.com/o/r")!))

        print("LiveParsersCheck passed")
    }
}
