// Licensed under GPL-3.0. See LICENSE.
//
//  DevHostsCheck.swift
//  Nook
//
//    swiftc -parse-as-library Packages/NookWeb/Sources/NookWeb/DevTools/DevHosts.swift \
//           Packages/NookWeb/Checks/DevHostsCheck.swift -o /tmp/devhosts && /tmp/devhosts
//

import Foundation

@main
struct DevHostsCheck {
    static func main() {
        let dev = ["http://localhost:3000/", "http://127.0.0.1:8080", "http://[::1]:5173/", "http://app.localhost/",
                   "https://shop.test/", "http://mac.local:4000", "http://10.0.0.5/", "http://192.168.1.140:8123",
                   "http://172.16.0.1/", "http://172.31.255.1/", "http://0.0.0.0:8000"]
        let notDev = ["https://example.com/", "https://localhost.example.com/", "https://test.com/", "http://172.32.0.1/",
                      "http://11.0.0.1/", "https://192.168.1.1.evil.com/", "file:///tmp/x.html", "about:blank",
                      "http://300.1.1.1/", "https://local/"]
        for s in dev { precondition(DevHosts.isDevHost(URL(string: s)!), s) }
        for s in notDev { precondition(!DevHosts.isDevHost(URL(string: s)!), s) }
        print("DevHostsCheck passed")
    }
}
