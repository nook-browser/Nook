// Licensed under GPL-3.0. See LICENSE.
import Foundation
import NookTabsCore

/// The person's open pull requests, read from github.com's own pull request list with a space's
/// session cookies. No token and no API app; the list's JSON shape is GitHub's to change.
enum GitHubPulls {
    enum Failure: Error { case signedOut, failed }

    /// Open pull requests the person wrote or was asked to review, newest activity first.
    private static let listURL: URL = {
        var components = URLComponents(string: "https://github.com/pulls")!
        components.queryItems = [URLQueryItem(name: "q", value: "is:pr is:open (author:@me OR review-requested:@me) sort:updated-desc")]
        return components.url!
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// A signed-out request redirects to the login page; following it would carry the cookies on.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }

    private struct Response: Decodable {
        struct Payload: Decodable { let pullsDashboardSurfaceContentRoute: Route }
        struct Route: Decodable { let results: [PullRequest] }
        struct PullRequest: Decodable {
            let permalink: URL
            let title: String
        }
        let payload: Payload
    }

    /// A pull request page: github.com/<owner>/<repo>/pull/<number>.
    static func owns(_ url: URL) -> Bool {
        let parts = url.path.split(separator: "/")
        return url.host == "github.com" && parts.count == 4 && parts[2] == "pull" && Int(parts[3]) != nil
    }

    /// The first page of the list (25), which is all a sidebar folder shows.
    static func fetch(cookies: [HTTPCookie]) async throws -> [LivePage] {
        let ours = cookies.filter { $0.domain == "github.com" || $0.domain == ".github.com" }
        guard !ours.isEmpty else { throw Failure.signedOut }
        var request = URLRequest(url: listURL)
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: ours)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // What github.com's own pages send with this request.
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("true", forHTTPHeaderField: "GitHub-Verified-Fetch")
        if let agent = PlatformUserAgent.custom { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.failed }
        // Signed out, the JSON list answers 404 and the HTML one redirects to the login page.
        if (300..<400).contains(status) || status == 401 || status == 404 { throw Failure.signedOut }
        guard status == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.failed }
        return decoded.payload.pullsDashboardSurfaceContentRoute.results
            .filter { owns($0.permalink) }
            .map { LivePage(url: $0.permalink, title: $0.title) }
    }
}
