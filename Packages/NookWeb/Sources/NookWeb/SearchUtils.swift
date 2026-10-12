// Licensed under GPL-3.0. See LICENSE.
import Foundation

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
  return beforeQuery.split(separator: "#", maxSplits: 1).first.map(String.init) ?? beforeQuery
}

/// True when schemeless input names a host: localhost, an IP address, or dotted labels ending in
/// a top-level domain. "3.14", "what." and "asp.net core" are searches.
private func looksLikeHost(_ input: String) -> Bool {
  if isLocalhost(input) { return true }
  guard !input.contains(where: \.isWhitespace) else { return false }
  let host = hostPortion(input)
  if isIPAddress(host) { return true }
  return host.wholeMatch(of: #/([\p{L}\p{N}-]+\.)+\p{L}[\p{L}\p{N}-]+(:\d+)?/#) != nil
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

  if looksLikeHost(trimmed) {
    // Local/private IP addresses default to http:// since they rarely serve HTTPS
    if isIPAddress(hostPortion(trimmed)) {
      return "http://\(trimmed)"
    }
    return "https://\(trimmed)"
  }

  let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
  // Not String(format:): the template is user-editable, and a stray %d or %n reads past the arguments.
  let urlString = queryTemplate.replacingOccurrences(of: "%@", with: encoded)
  return urlString
}

public func isLikelyURL(_ text: String) -> Bool {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }

  // The same test normalizeURL navigates on, so the row shown is what Return does.
  return looksLikeHost(trimmed)
}
