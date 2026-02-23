import Foundation
import SwiftUI

public func isValidURL(_ string: String) -> Bool {
  let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.isEmpty || trimmed.contains(" ") {
    return false
  }

  guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
    return false
  }

  switch scheme {
  case "http", "https", "ftp":
    if let host = url.host, !host.isEmpty { return true }
    return false
  case "file":
    return url.path.isEmpty == false
  case "chrome-extension", "moz-extension", "webkit-extension", "safari-web-extension":
    return (url.host?.isEmpty == false)
  default:
    return false
  }
}

public func normalizeURL(_ input: String, provider: SearchProvider) -> String {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
    trimmed.hasPrefix("file://") || trimmed.hasPrefix("chrome-extension://") ||
    trimmed.hasPrefix("moz-extension://") || trimmed.hasPrefix("webkit-extension://") ||
    trimmed.hasPrefix("safari-web-extension://")
  {
    return trimmed
  }

  if trimmed.contains(".") && !trimmed.contains(" ") {
    return "https://\(trimmed)"
  }

  let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
  let urlString = String(format: provider.queryTemplate, encoded)
  return urlString
}

public func isLikelyURL(_ text: String) -> Bool {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.contains(".") &&
    (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
      trimmed.contains(".com") || trimmed.contains(".org") ||
      trimmed.contains(".net") || trimmed.contains(".io") ||
      trimmed.contains(".co") || trimmed.contains(".dev"))
}

public protocol SearchProvider: Codable, Identifiable, Sendable {
    var displayName: String { get }
    var host: String { get }
    var queryTemplate: String { get }
    var id: String { get }
}

public enum DefaultSearchProvider: String, CaseIterable, SearchProvider {
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

  public var displayName: String {
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

  public var host: String {
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

  public var queryTemplate: String {
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

public struct CustomSearchProvider: SearchProvider {
    public var displayName: String
    
    public var host: String
    
    public var queryTemplate: String
    
    public var id: String {
        return "\(host)_\(queryTemplate)"
    }
}
