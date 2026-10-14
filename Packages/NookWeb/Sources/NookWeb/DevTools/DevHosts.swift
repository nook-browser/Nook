// Licensed under GPL-3.0. See LICENSE.
//
//  DevHosts.swift
//  Nook
//
//  Which hosts are a developer's own: loopback, .localhost, .test, .local and private networks.
//

import Foundation

public enum DevHosts {
    public static func isDevHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host == "0.0.0.0" || host == "::1" || host == "[::1]" { return true }
        if ["localhost", "test", "local"].contains(where: { host.hasSuffix("." + $0) }) { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
