//
//  CookieModels.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit

// MARK: - Cookie Data Models

struct CookieInfo: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String
    let size: Int
    
    init(from httpCookie: HTTPCookie) {
        self.id = UUID()
        self.name = httpCookie.name
        self.value = httpCookie.value
        self.domain = httpCookie.domain
        self.path = httpCookie.path
        self.expiresDate = httpCookie.expiresDate
        self.isSecure = httpCookie.isSecure
        self.isHTTPOnly = httpCookie.isHTTPOnly
        self.sameSitePolicy = httpCookie.sameSitePolicy?.rawValue ?? "None"
        self.size = (httpCookie.name.count + httpCookie.value.count)
    }
    
    var displayDomain: String {
        return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
    
    var isSessionCookie: Bool {
        return expiresDate == nil
    }
    
    var expirationStatus: String {
        guard let expiresDate = expiresDate else {
            return "Session"
        }
        
        if expiresDate < Date() {
            return "Expired"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: expiresDate)
    }
    
    var sizeDescription: String {
        if size < 1024 {
            return "\(size) bytes"
        } else {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        }
    }
    
    // MARK: - Privacy & Security Compliance
    
    var privacyRisk: PrivacyRisk {
        // Assess privacy risk based on cookie attributes
        var score = 0
        
        // High risk: Not secure and not HTTPOnly
        if !isSecure && !isHTTPOnly {
            score += 3
        } else if !isSecure || !isHTTPOnly {
            score += 1
        }
        
        // Medium risk: SameSite None without Secure
        if sameSitePolicy == "None" && !isSecure {
            score += 2
        }
        
        // Low risk: Persistent cookies with long expiration
        if let expiry = expiresDate, expiry.timeIntervalSinceNow > 31536000 { // > 1 year
            score += 1
        }
        
        // High risk: Large cookie values (potential fingerprinting)
        if size > 4096 { // > 4KB
            score += 2
        }
        
        switch score {
        case 0...1: return .low
        case 2...3: return .medium
        default: return .high
        }
    }
    
    var isThirdParty: Bool {
        // Basic heuristic: domain starts with dot indicates third-party
        return domain.hasPrefix(".")
    }
    
    var isExpired: Bool {
        guard let expiresDate = expiresDate else { return false }
        return expiresDate < Date()
    }
    
    var shouldRetain: Bool {
        // Apply data minimization: don't retain expired or high-risk cookies
        return !isExpired && privacyRisk != .high
    }
    
    var complianceIssues: [String] {
        var issues: [String] = []
        
        if !isSecure && sameSitePolicy == "None" {
            issues.append("SameSite=None requires Secure flag")
        }
        
        if !isHTTPOnly && !isSecure {
            issues.append("Cookie lacks security flags (Secure, HttpOnly)")
        }
        
        if size > 4096 {
            issues.append("Cookie size exceeds recommended 4KB limit")
        }
        
        if let expiry = expiresDate, expiry.timeIntervalSinceNow > 31536000 {
            issues.append("Cookie expiration exceeds 1 year (GDPR concern)")
        }
        
        if isThirdParty && sameSitePolicy == "None" {
            issues.append("Third-party cookie with SameSite=None")
        }
        
        return issues
    }
}

struct DomainCookieGroup: Identifiable, Hashable, Codable {
    let id: UUID
    let domain: String
    let cookies: [CookieInfo]
    
    var displayDomain: String {
        return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
    
    var cookieCount: Int {
        return cookies.count
    }
    
    var totalSize: Int {
        return cookies.reduce(0) { $0 + $1.size }
    }
    
    var totalSizeDescription: String {
        if totalSize < 1024 {
            return "\(totalSize) bytes"
        } else if totalSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(totalSize) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(totalSize) / (1024.0 * 1024.0))
        }
    }
    
    var hasExpiredCookies: Bool {
        return cookies.contains { cookie in
            guard let expiresDate = cookie.expiresDate else { return false }
            return expiresDate < Date()
        }
    }
}

// MARK: - Privacy Risk Assessment

enum PrivacyRisk: String, CaseIterable {
    case low = "Low Risk"
    case medium = "Medium Risk" 
    case high = "High Risk"
    
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.shield"
        case .high: return "xmark.shield"
        }
    }
}

// MARK: - Cookie Filter Options

enum CookieFilter: String, CaseIterable {
    case all = "All Cookies"
    case session = "Session Only"
    case persistent = "Persistent Only"
    case secure = "Secure Only"
    case expired = "Expired"
    case thirdParty = "Third-Party"
    case highRisk = "High Privacy Risk"
    case nonCompliant = "Non-Compliant"
    
    func matches(_ cookie: CookieInfo) -> Bool {
        switch self {
        case .all:
            return true
        case .session:
            return cookie.isSessionCookie
        case .persistent:
            return !cookie.isSessionCookie
        case .secure:
            return cookie.isSecure
        case .expired:
            return cookie.isExpired
        case .thirdParty:
            return cookie.isThirdParty
        case .highRisk:
            return cookie.privacyRisk == .high
        case .nonCompliant:
            return !cookie.complianceIssues.isEmpty
        }
    }
}

enum CookieSortOption: String, CaseIterable {
    case domain = "Domain"
    case name = "Name"
    case size = "Size"
    case expiration = "Expiration"
    
    var displayName: String {
        return rawValue
    }
}
