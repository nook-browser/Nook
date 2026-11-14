// Licensed under GPL-3.0. See LICENSE.
//
//  LocalNetworkHost.swift
//  Nook
//
//  Hosts on the person's own network, which may offer to accept a self-signed certificate.
//

import Foundation
import Network

public enum LocalNetworkHost {
    /// Names reserved for local networks: mDNS, home routers (RFC 8375), ICANN's private TLD.
    private static let localSuffixes = [".local", ".lan", ".home.arpa", ".internal", ".localhost"]

    /// Private, link-local and loopback address literals, local-only names and single-label names.
    ///
    /// Address literals must parse strictly. Splitting on "." and dropping the components that
    /// are not numbers classified `10.0.0.1.attacker.example` as private.
    public static func contains(_ host: String) -> Bool {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if host == "localhost" { return true }

        // URLs carry IPv6 literals in brackets.
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        if let v6 = IPv6Address(bare) {
            let bytes = Array(v6.rawValue)
            if v6.isLoopback { return true }                                     // ::1
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }     // fe80::/10 link-local
            return (bytes[0] & 0xFE) == 0xFC                                     // fc00::/7 unique-local
        }
        if let v4 = IPv4Address(bare) {
            let parts = Array(v4.rawValue)
            switch parts[0] {
            case 10, 127: return true                                            // 10/8, 127/8
            case 172: return (16...31).contains(parts[1])                        // 172.16/12
            case 192: return parts[1] == 168                                     // 192.168/16
            case 169: return parts[1] == 254                                     // 169.254/16 link-local
            default: return false
            }
        }

        // A dotless name only resolves through the local search domain.
        if !host.contains(".") {
            return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && !host.allSatisfy(\.isNumber)
        }
        return localSuffixes.contains { host.hasSuffix($0) }
    }
}
