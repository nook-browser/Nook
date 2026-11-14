// Licensed under GPL-3.0. See LICENSE.
//
//  LocalNetworkHostCheck.swift
//  Nook
//
//  Which hosts may offer the self-signed certificate prompt:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/LocalNetworkHost.swift \
//           Packages/NookWeb/Checks/LocalNetworkHostCheck.swift -o /tmp/local-host && /tmp/local-host
//
//  Created by Bain Gurley on 13/11/2026.
//

import Foundation

@main
struct LocalNetworkHostCheck {
    static func main() {
        let local = ["localhost", "127.0.0.1", "10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.140",
                     "169.254.1.1", "[::1]", "::1", "fe80::1", "fd00::1",
                     "tower.local", "TOWER.LOCAL", "tower.local.", "nas.lan", "router.home.arpa", "box.internal",
                     "app.localhost", "unraid", "homeassistant"]
        let notLocal = ["example.com", "172.32.0.1", "11.0.0.1", "8.8.8.8", "2001:4860::8888",
                        "10.0.0.1.attacker.example", "192.168.1.1.evil.com", "local.example.com",
                        "lan.example.com", "evil.com.local.example.com", "", ".", "300.1.1.1"]
        for host in local { precondition(LocalNetworkHost.contains(host), "should be local: \(host)") }
        for host in notLocal { precondition(!LocalNetworkHost.contains(host), "should not be local: \(host)") }
        print("LocalNetworkHostCheck passed")
    }
}
