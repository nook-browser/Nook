// Licensed under GPL-3.0. See LICENSE.
//
//  LinkPreviewGate.swift
//  Nook
//
//  The pure part of "may Nook fetch this link for a preview". Nothing a page links to reaches
//  a private network, a local device or the person's own machine on Nook's behalf.
//

import Darwin
import Foundation

enum LinkPreviewGate {
    private static let reservedSuffixes = [".localhost", ".local", ".lan", ".internal", ".home.arpa"]

    static func mayFetch(url: URL, isPrivate: Bool, isAgent: Bool, blocked: Bool) -> Bool {
        guard !isPrivate, !isAgent, !blocked,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let raw = url.host?.lowercased() else { return false }
        var host = raw
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if reservedSuffixes.contains(where: host.hasSuffix) { return false }
        if isReservedAddress(host) { return false }
        // A single label (localhost, a router's name) only resolves on the local network.
        return host.contains(".") || host.contains(":")
    }

    /// True for an IP literal in a loopback, private, link-local, multicast or otherwise reserved range.
    /// inet_aton also reads the short, hex and single-number forms a URL may carry.
    static func isReservedAddress(_ host: String) -> Bool {
        var v4 = in_addr()
        if inet_aton(host, &v4) == 1 { return isReserved(v4: UInt32(bigEndian: v4.s_addr)) }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, host, &v6) == 1 else { return false }
        let b = withUnsafeBytes(of: &v6) { Array($0) }
        let embedded = UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])
        if b[0..<12].allSatisfy({ $0 == 0 }) { return isReserved(v4: embedded) }  // ::, ::1, ::a.b.c.d
        if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return true }  // fe80::/10
        if b[0] & 0xfe == 0xfc { return true }  // fc00::/7
        if b[0] == 0xff { return true }  // ff00::/8
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return isReserved(v4: embedded) }  // ::ffff:a.b.c.d
        if b[0..<4] == [0x00, 0x64, 0xff, 0x9b] && b[4..<12].allSatisfy({ $0 == 0 }) { return isReserved(v4: embedded) }  // 64:ff9b::/96
        return false
    }

    private static func isReserved(v4 a: UInt32) -> Bool {
        let top = a >> 24
        return top == 0 || top == 10 || top == 127 || top >= 224  // 224/4 multicast, 240/4 and broadcast
            || (a >> 20) == 0xAC1  // 172.16/12
            || (a >> 16) == 0xC0A8  // 192.168/16
            || (a >> 16) == 0xA9FE  // 169.254/16
            || (a >> 22) == 0x191  // 100.64/10
            || (a >> 17) == 0x6309  // 198.18/15
    }

    /// True when any resolved address is reserved, or nothing resolved.
    static func anyReserved(_ addresses: [String]) -> Bool {
        addresses.isEmpty || addresses.contains(where: isReservedAddress)
    }

    /// Resolves `host` off the main actor; a name that reaches a reserved address is refused.
    /// ponytail: resolve-then-connect leaves a rebinding window; pinning the connection needs a custom transport.
    static func resolvesToPublic(_ host: String) async -> Bool {
        await Task.detached { !anyReserved(addresses(of: host)) }.value
    }

    private static func addresses(of host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(list) }
        var out: [String] = []
        var cur: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cur {
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if ai.pointee.ai_family == AF_INET {
                ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    var a = $0.pointee.sin_addr
                    inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count))
                }
            } else if ai.pointee.ai_family == AF_INET6 {
                ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    var a = $0.pointee.sin6_addr
                    inet_ntop(AF_INET6, &a, &buf, socklen_t(buf.count))
                }
            }
            out.append(String(cString: buf))
            cur = ai.pointee.ai_next
        }
        return out
    }
}
