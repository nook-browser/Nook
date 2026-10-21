// Licensed under GPL-3.0. See LICENSE.
import Foundation
import NookTabsCore

/// The person's open pull requests, read from github.com's own pull request list with a space's
/// session cookies. No token and no API app; the list's JSON shape is GitHub's to change.
enum GitHubPulls {
    typealias Failure = LiveFetch.Failure

    /// Open pull requests the person wrote or was asked to review, newest activity first.
    private static let listURL: URL = {
        var components = URLComponents(string: "https://github.com/pulls")!
        components.queryItems = [URLQueryItem(name: "q", value: "is:pr is:open (author:@me OR review-requested:@me) sort:updated-desc")]
        return components.url!
    }()

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
        let (data, status) = try await LiveFetch.get(listURL, cookies: cookies, domains: ["github.com", ".github.com"], headers: LiveFetch.gitHubJSONHeaders)
        // Signed out, the JSON list answers 404 and the HTML one redirects to the login page.
        if (300..<400).contains(status) || status == 401 || status == 404 { throw Failure.signedOut }
        guard status == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.failed }
        return decoded.payload.pullsDashboardSurfaceContentRoute.results
            .filter { owns($0.permalink) }
            .map { LivePage(url: $0.permalink, title: $0.title) }
    }
}
