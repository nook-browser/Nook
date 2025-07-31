//
//  Utils.swift
//  Pulse
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI
import Foundation


public func isValidURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

    // Reject empty strings or strings with spaces
    if trimmed.isEmpty || trimmed.contains(" ") {
        return false
    }

    // First check if it's already a complete URL with scheme
    if let url = URL(string: trimmed),
       let scheme = url.scheme,
       ["http", "https", "file", "ftp"].contains(scheme.lowercased()),
       let host = url.host,
       !host.isEmpty {
        return true
    }

    // For strings without scheme, validate as domain-like patterns
    return false
}

/// Normalizes a URL by adding protocol if missing
public func normalizeURL(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // If it already has a protocol, return as-is
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return trimmed
    }
    
    // If it looks like a URL (has dots), add https://
    if trimmed.contains(".") && !trimmed.contains(" ") {
        return "https://\(trimmed)"
    }
    
    // Otherwise, treat as search query
    let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
    return "https://www.google.com/search?q=\(encodedQuery)"
}

public func isLikelyURL(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.contains(".") &&
           (trimmed.hasPrefix("http://") ||
            trimmed.hasPrefix("https://") ||
            trimmed.contains(".com") ||
            trimmed.contains(".org") ||
            trimmed.contains(".net") ||
            trimmed.contains(".io") ||
            trimmed.contains(".co") ||
            trimmed.contains(".dev"))
}
