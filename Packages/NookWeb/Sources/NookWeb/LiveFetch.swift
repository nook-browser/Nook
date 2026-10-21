// Licensed under GPL-3.0. See LICENSE.
//
//  LiveFetch.swift
//  Nook
//
//  Network side of the live folder sources other than pull requests (GitHubPulls.swift). Each
//  reads with the space's own cookies for the source's domain only; feeds send none.
//

import Foundation
import NookTabsCore

enum LiveFetch {
    enum Failure: Error { case signedOut, failed }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Same as `session` but follows redirects, for feeds, which carry no cookies.
    private static let feedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    /// A signed-out request redirects to the login page; following it would carry the cookies on.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }

    /// GET with only the cookies set for `domains`. Signed out (no cookies) throws before any request.
    static func get(_ url: URL, cookies: [HTTPCookie], domains: Set<String>, headers: [String: String] = [:]) async throws -> (Data, Int) {
        let ours = cookies.filter { domains.contains($0.domain) }
        guard !ours.isEmpty else { throw Failure.signedOut }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: ours).merging(headers) { $1 }
        if let agent = PlatformUserAgent.custom { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.failed }
        return (data, status)
    }

    private static let gitHubDomains: Set<String> = ["github.com", ".github.com"]

    /// What github.com's own pages send with a JSON route request.
    static let gitHubJSONHeaders = [
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "GitHub-Verified-Fetch": "true",
    ]

    // MARK: - Sources

    /// Open issues assigned to the person, newest activity first. Same JSON route family as the
    /// pull request list; unverified.
    static func githubIssues(cookies: [HTTPCookie]) async throws -> [LivePage] {
        var components = URLComponents(string: "https://github.com/issues")!
        components.queryItems = [URLQueryItem(name: "q", value: "is:issue is:open assignee:@me sort:updated-desc")]
        let (data, status) = try await get(components.url!, cookies: cookies, domains: gitHubDomains, headers: gitHubJSONHeaders)
        if (300..<400).contains(status) || status == 401 || status == 404 { throw Failure.signedOut }
        guard status == 200, let entries = LiveParse.githubIssues(data) else { throw Failure.failed }
        return entries.prefix(25).map { LivePage(url: $0.url, title: $0.title) }
    }

    /// Unread notification threads, read from the server-rendered inbox.
    static func githubNotifications(cookies: [HTTPCookie]) async throws -> [LivePage] {
        let url = URL(string: "https://github.com/notifications?query=is%3Aunread")!
        let (data, status) = try await get(url, cookies: cookies, domains: gitHubDomains, headers: ["Accept": "text/html"])
        if (300..<400).contains(status) || status == 401 || status == 404 { throw Failure.signedOut }
        guard status == 200 else { throw Failure.failed }
        return LiveParse.githubNotifications(html: String(decoding: data, as: UTF8.self))
            .prefix(25).map { LivePage(url: $0.url, title: $0.title) }
    }

    /// Incomplete tasks assigned to the person across their workspaces, soonest due first.
    static func asanaTasks(cookies: [HTTPCookie]) async throws -> [LivePage] {
        let domains: Set<String> = ["app.asana.com", ".app.asana.com", ".asana.com"]
        func json(_ string: String) async throws -> Data {
            let (data, status) = try await get(URL(string: "https://app.asana.com/api/1.0" + string)!, cookies: cookies, domains: domains, headers: ["Accept": "application/json"])
            if (300..<400).contains(status) || status == 401 || status == 403 { throw Failure.signedOut }
            guard status == 200 else { throw Failure.failed }
            return data
        }
        guard let workspaces = LiveParse.asanaWorkspaces(try await json("/users/me?opt_fields=workspaces")) else { throw Failure.failed }
        var tasks: [LiveParse.AsanaTask] = []
        for workspace in workspaces {
            let data = try await json("/tasks?assignee=me&workspace=\(workspace)&completed_since=now&opt_fields=name,permalink_url,due_on,completed")
            guard let more = LiveParse.asanaTasks(data) else { throw Failure.failed }
            tasks += more
        }
        return LiveParse.rankAsanaTasks(tasks).map { LivePage(url: $0.url, title: $0.title) }
    }

    /// A feed's own title and newest items. No cookies are sent.
    static func feed(_ url: URL) async throws -> (title: String?, pages: [LivePage]) {
        var request = URLRequest(url: url)
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let agent = PlatformUserAgent.custom { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await feedSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = LiveParse.feed(data, base: response.url ?? url) else { throw Failure.failed }
        return (parsed.title, parsed.items.map { LivePage(url: $0.url, title: $0.title) })
    }
}
