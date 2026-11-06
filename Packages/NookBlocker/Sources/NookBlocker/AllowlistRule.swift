// Licensed under GPL-3.0. See LICENSE.
//
//  AllowlistRule.swift
//  Nook
//

import Foundation

public enum AllowlistRule {
    /// The entry that exempts `host`: the host itself or the longest parent domain in the list.
    public static func covering(_ host: String, in entries: [String]) -> String? {
        let h = host.lowercased()
        return entries.map { $0.lowercased() }
            .filter { h == $0 || h.hasSuffix("." + $0) }
            .max { $0.count < $1.count }
    }
}
