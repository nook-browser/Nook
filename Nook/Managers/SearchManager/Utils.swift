import Foundation
import SwiftUI

/// Returns true if the host portion of the input looks like an IP address (v4 or v6).
private func isIPAddress(_ host: String) -> Bool {
  // IPv4: 1-3 digits separated by dots (e.g. 192.168.1.140)
  let ipv4 = #/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$/#
  if host.wholeMatch(of: ipv4) != nil { return true }

  // IPv6 bare or bracketed (e.g. [::1], ::1)
  if host.hasPrefix("[") || host.contains("::") { return true }

  return false
}

/// Returns true if the input looks like localhost (with optional port).
private func isLocalhost(_ input: String) -> Bool {
  let host = hostPortion(input)
  return host == "localhost" || host.hasPrefix("localhost:")
}

/// Extracts the host (and optional port) from a schemeless input string.
/// e.g. "192.168.1.140:8080/path" → "192.168.1.140:8080"
private func hostPortion(_ input: String) -> String {
  // Strip any path or query
  let beforePath = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? input
  let beforeQuery = beforePath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? beforePath
  return beforeQuery
}

public func normalizeURL(_ input: String, queryTemplate: String) -> String {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

  // Explicit scheme — respect it as-is (including http://)
  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
    trimmed.hasPrefix("file://") || trimmed.hasPrefix("chrome-extension://") ||
    trimmed.hasPrefix("moz-extension://") || trimmed.hasPrefix("webkit-extension://") ||
    trimmed.hasPrefix("safari-web-extension://")
  {
    return trimmed
  }

  // localhost always gets http://
  if isLocalhost(trimmed) {
    return "http://\(trimmed)"
  }

  if trimmed.contains(".") && !trimmed.contains(" ") {
    // Local/private IP addresses default to http:// since they rarely serve HTTPS
    if isIPAddress(hostPortion(trimmed)) {
      return "http://\(trimmed)"
    }
    return "https://\(trimmed)"
  }

  let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
  let urlString = String(format: queryTemplate, encoded)
  return urlString
}

public func isLikelyURL(_ text: String) -> Bool {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }

  // localhost and IP addresses are URLs, not search queries
  if isLocalhost(trimmed) { return true }

  guard trimmed.contains(".") else { return false }

  if isIPAddress(hostPortion(trimmed)) { return true }

  return trimmed.contains(".com") || trimmed.contains(".org") ||
    trimmed.contains(".net") || trimmed.contains(".io") ||
    trimmed.contains(".co") || trimmed.contains(".dev")
}

public enum SearchProvider: String, CaseIterable, Identifiable, Codable, Sendable {
  case google
  case duckDuckGo
  case bing
  case brave
  case yahoo
  case perplexity
  case unduck
  case ecosia
  case kagi

  public var id: String { rawValue }

  var displayName: String {
    switch self {
    case .google: return "Google"
    case .duckDuckGo: return "DuckDuckGo"
    case .bing: return "Bing"
    case .brave: return "Brave"
    case .yahoo: return "Yahoo"
    case .perplexity: return "Perplexity"
    case .unduck: return "Unduck"
    case .ecosia: return "Ecosia"
    case .kagi: return "Kagi"
    }
  }

  var host: String {
    switch self {
    case .google: return "www.google.com"
    case .duckDuckGo: return "duckduckgo.com"
    case .bing: return "www.bing.com"
    case .brave: return "search.brave.com"
    case .yahoo: return "search.yahoo.com"
    case .perplexity: return "www.perplexity.ai"
    case .unduck: return "duckduckgo.com"
    case .ecosia: return "www.ecosia.org"
    case .kagi: return "kagi.com"
    }
  }

  var queryTemplate: String {
    switch self {
    case .google:
      return "https://www.google.com/search?q=%@"
    case .duckDuckGo:
      return "https://duckduckgo.com/?q=%@"
    case .bing:
      return "https://www.bing.com/search?q=%@"
    case .brave:
      return "https://search.brave.com/search?q=%@"
    case .yahoo:
      return "https://search.yahoo.com/search?p=%@"
    case .perplexity:
      return "https://www.perplexity.ai/search?q=%@"
    case .unduck:
      return "https://unduck.link?q=%@"
    case .ecosia:
      return "https://www.ecosia.org/search?q=%@"
    case .kagi:
      return "https://kagi.com/search?q=%@"
    }
  }
}
