// Licensed under GPL-3.0. See LICENSE.
//
//  DevMCPFilesCheck.swift
//  Nook
//
//  DevMCP may only write under its root. Compiles the shipped source directly:
//
//    swiftc Nook/Managers/DevMCPServer/DevMCPFiles.swift scripts/tests/DevMCPFilesCheck.swift \
//           -o /tmp/devmcp-files-check && /tmp/devmcp-files-check
//

import Foundation

@main
struct DevMCPFilesCheck {
    static func main() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("devmcp-check-\(UUID().uuidString)")
        let root = tmp.appendingPathComponent("root")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("out"), withDestinationURL: tmp)
        defer { try? fm.removeItem(at: tmp) }

        precondition(DevMCPFiles.resolve("a/b.json", root: root) != nil)
        precondition(DevMCPFiles.resolve("a/../b.json", root: root) != nil)
        precondition(DevMCPFiles.resolve("", root: root) == nil)
        precondition(DevMCPFiles.resolve(".", root: root) == nil)
        precondition(DevMCPFiles.resolve("../x", root: root) == nil)
        precondition(DevMCPFiles.resolve("a/../../x", root: root) == nil)
        precondition(DevMCPFiles.resolve("/etc/hosts", root: root) == nil)
        precondition(DevMCPFiles.resolve("~/.zshrc", root: root) == nil)
        precondition(DevMCPFiles.resolve("out/x", root: root) == nil, "a symlink must not lead out")

        let u = URL(string: "https://cdn.example.com/files/a%20b/photo.JPG?v=1")!
        let name = DevMCPFiles.fileName(for: u, contentType: "image/jpeg")
        precondition(name.hasSuffix("-photo.JPG") && name.count == 9 + 9, name)
        precondition(DevMCPFiles.fileName(for: URL(string: "https://x.com/img")!, contentType: "image/png; q=1").hasSuffix("-img.png"))
        precondition(DevMCPFiles.fileName(for: URL(string: "https://x.com/")!, contentType: nil).hasSuffix("-file"))
        precondition(DevMCPFiles.fileName(for: URL(string: "https://x.com/../..")!, contentType: nil).contains("-"))
        precondition(!DevMCPFiles.fileName(for: URL(string: "https://x.com/a%2F..%2Fb")!, contentType: nil).contains("/"))

        func cookie(_ domain: String, _ path: String = "/", secure: Bool = false, expires: Date? = nil) -> HTTPCookie {
            var p: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: path, .name: "n", .value: "v"]
            if secure { p[.secure] = "TRUE" }
            if let expires { p[.expires] = expires }
            return HTTPCookie(properties: p)!
        }
        let page = URL(string: "https://www.example.com/shop/item")!
        precondition(DevMCPFiles.cookies([cookie(".example.com")], for: page).count == 1)
        precondition(DevMCPFiles.cookies([cookie("www.example.com")], for: page).count == 1)
        precondition(DevMCPFiles.cookies([cookie("example.com")], for: page).isEmpty, "host-only cookie is not sent to a subdomain")
        precondition(DevMCPFiles.cookies([cookie(".other.com")], for: page).isEmpty)
        precondition(DevMCPFiles.cookies([cookie(".example.com", "/shop")], for: page).count == 1)
        precondition(DevMCPFiles.cookies([cookie(".example.com", "/sho")], for: page).isEmpty)
        precondition(DevMCPFiles.cookies([cookie(".example.com", secure: true)], for: URL(string: "http://www.example.com/")!).isEmpty)
        precondition(DevMCPFiles.cookies([cookie(".example.com", expires: Date(timeIntervalSinceNow: -60))], for: page).isEmpty)
        print("DevMCPFilesCheck passed")
    }
}
