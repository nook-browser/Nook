import Foundation

/// Decides whether one `externally_connectable` match pattern is safe to honor.
enum ExternallyConnectableMatch {
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]"]
    private static let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or", "go"]
    // Shared-hosting suffixes, where one wildcard would cover unrelated tenants. Not the full PSL.
    private static let sharedHosts: Set<String> = [
        "github.io", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app",
        "firebaseapp.com", "appspot.com", "herokuapp.com", "azurewebsites.net", "cloudfront.net",
        "s3.amazonaws.com", "blogspot.com", "glitch.me", "onrender.com", "fly.dev", "surge.sh",
        "ngrok.io", "ngrok-free.app", "repl.co", "replit.dev",
    ]

    /// True for a suffix a wildcard must not cover: a bare TLD, a `co.uk`-style pair or a shared host.
    static func isBroadSuffix(_ suffix: String) -> Bool {
        let labels = suffix.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 1 { return true }
        if labels.count == 2, secondLevel.contains(String(labels[0])), labels[1].count == 2 { return true }
        return sharedHosts.contains(suffix)
    }

    static func isAcceptable(_ pattern: String) -> Bool {
        guard let schemeEnd = pattern.range(of: "://") else { return false }
        let scheme = pattern[..<schemeEnd.lowerBound]
        var host = String(pattern[schemeEnd.upperBound...].prefix { $0 != "/" }).lowercased()
        if host.hasPrefix("[") {
            host = String(host.prefix { $0 != "]" }) + "]"
        } else {
            host = String(host.prefix { $0 != ":" })
        }
        if host.hasSuffix(".") { return false }
        if localHosts.contains(host) { return scheme == "http" || scheme == "https" }
        guard scheme == "https", !host.isEmpty, !host.hasSuffix(".") else { return false }
        if host.hasPrefix("*.") {
            let suffix = String(host.dropFirst(2))
            return !suffix.contains("*") && !isBroadSuffix(suffix)
        }
        return !host.contains("*") && host.contains(".")
    }
}
