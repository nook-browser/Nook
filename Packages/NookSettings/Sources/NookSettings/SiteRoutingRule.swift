//
//  SiteRoutingRule.swift
//  Nook
//

import Foundation

public struct SiteRoutingRule: Codable, Identifiable, Equatable {
    public let id: UUID
    public var domain: String
    public var pathPrefix: String?
    public var targetSpaceId: UUID
    public var isEnabled: Bool
    /// Only set on rules written before spaces owned their data, where the target was a space
    /// inside a profile. `SiteRoutingManager.dropMergedProfileTargets()` resolves and clears it.
    public var legacyProfileId: UUID?

    public init(
        id: UUID = UUID(),
        domain: String,
        pathPrefix: String? = nil,
        targetSpaceId: UUID,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.domain = SiteRoutingRule.normalizeDomain(domain)
        self.pathPrefix = pathPrefix
        self.targetSpaceId = targetSpaceId
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, domain, pathPrefix, targetSpaceId, isEnabled
        case legacyProfileId = "targetProfileId"
    }

    public static func normalizeDomain(_ input: String) -> String {
        var d = input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] {
            if d.hasPrefix(prefix) { d = String(d.dropFirst(prefix.count)) }
        }
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        if let slashIndex = d.firstIndex(of: "/") { d = String(d[..<slashIndex]) }
        return d
    }
}
