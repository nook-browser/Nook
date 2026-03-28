//
//  SiteRoutingRule.swift
//  Nook
//

import Foundation

struct SiteRoutingRule: Codable, Identifiable, Equatable {
    let id: UUID
    var domain: String
    var pathPrefix: String?
    var targetSpaceId: UUID
    var targetProfileId: UUID
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        domain: String,
        pathPrefix: String? = nil,
        targetSpaceId: UUID,
        targetProfileId: UUID,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.domain = SiteRoutingRule.normalizeDomain(domain)
        self.pathPrefix = pathPrefix
        self.targetSpaceId = targetSpaceId
        self.targetProfileId = targetProfileId
        self.isEnabled = isEnabled
    }

    static func normalizeDomain(_ input: String) -> String {
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
