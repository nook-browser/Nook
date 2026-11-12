// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionPackageOriginCheck.swift
//  Nook
//
//  A package installed before stable IDs is traced to its store listing from its own files.
//  Compiles the shipped source directly:
//
//    swiftc Nook/Managers/ExtensionManager/ExtensionPackageOrigin.swift \
//           scripts/tests/ExtensionPackageOriginCheck.swift \
//           -o /tmp/extension-origin-check && /tmp/extension-origin-check
//

import Foundation

@main
struct ExtensionPackageOriginCheck {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("nook-origin-check-\(UUID().uuidString)")

    /// A package folder with this manifest and, when `item` is given, the store's signed file naming it.
    static func package(_ name: String, manifest: [String: Any], item: Any? = nil, rawMetadata: String? = nil) -> URL {
        let dir = root.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("_metadata"), withIntermediateDirectories: true)
        try! JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("manifest.json"))
        var metadata = rawMetadata
        if let item {
            let payload = try! JSONSerialization.data(withJSONObject: ["item_id": item, "item_version": "1.0", "protocol_version": 1, "content_hashes": [Any]()])
            let encoded = payload.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            metadata = #"[{"description":"treehash per file","signed_content":{"payload":"\#(encoded)","signatures":[]}}]"#
        }
        if let metadata { try! Data(metadata.utf8).write(to: dir.appendingPathComponent("_metadata/verified_contents.json")) }
        return dir
    }

    static func main() {
        defer { try? FileManager.default.removeItem(at: root) }
        typealias Origin = ExtensionPackageOrigin
        let id = "nmblahmglpbplmfcggghdgohohlaeiee"
        let chromeUpdates = "https://clients2.google.com/service/update2/crx"

        // A Chrome Web Store package: the store's signed file names the listing.
        precondition(Origin.read(packageAt: package("chrome", manifest: ["name": "A", "update_url": chromeUpdates], item: id)) == .chrome(id: id))
        // The same file in an Edge Add-ons package names an Edge listing.
        let edge = package("edge", manifest: ["name": "A", "update_url": "https://edge.microsoft.com/extensionwebstorebase/v1/crx"], item: id)
        precondition(Origin.read(packageAt: edge) == .edge(id: id))
        // A host that only looks like Edge's is not Edge.
        let lookalike = package("lookalike", manifest: ["update_url": "https://edge.microsoft.com.evil.test/crx"], item: id)
        precondition(Origin.read(packageAt: lookalike) == .chrome(id: id))

        // A Firefox add-on declares its own id, under either key.
        precondition(Origin.read(packageAt: package("gecko", manifest: ["browser_specific_settings": ["gecko": ["id": "{446900e4-71c2-419f-a6a7-df9c091e268b}"]]]))
            == .firefox(geckoID: "{446900e4-71c2-419f-a6a7-df9c091e268b}"))
        precondition(Origin.read(packageAt: package("gecko-old", manifest: ["applications": ["gecko": ["id": "addon@example.com"]]])) == .firefox(geckoID: "addon@example.com"))
        // The store's file wins over a declared id.
        let both = package("both", manifest: ["browser_specific_settings": ["gecko": ["id": "addon@example.com"]]], item: id)
        precondition(Origin.read(packageAt: both) == .chrome(id: id))

        // A `key` fixes a Chrome id with no store file at all.
        let key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAgFbIrnF3oWbqomZh8CHzkTE9MxD/4tVmCTJ3JYSzYhtVnX7tVAbXZRRPuYLavIFaS15tojlRNRhfOdvyTXew+RaSJjOIzdo30byBU3C4mJAtRtSjb+U9fAsJxStVpXvdQrYNNFCCx/85+eDmVDZNe6ZGC5K+PnGeEFvA4GJH9A/G1RsiBTmpyaCFrjtYUPWoDCU0HSs2A/aK6cMDTSzFTCAvR0xAIkU4gHkqAScfMP34lrwlO5LGkdXdyTMhGwNX4eVoZGlfwOAUmyMFYG3EwTC6aq1EcDrGqTLIGyeNAYzJmwtQ2SrtLK9Y2wr+Y4w3MbqC6BHOvYFn4r6pXOy9LQIDAQAB"
        precondition(Origin.chromeID(fromManifestKey: key)?.count == 32)
        precondition(Origin.read(packageAt: package("keyed", manifest: ["name": "A", "key": key])) == Origin.chromeID(fromManifestKey: key).map { .chrome(id: $0) })
        precondition(Origin.read(packageAt: package("bad-key", manifest: ["name": "A", "key": "not base64 !!"])) == nil)
        // The store's file wins over a key, and Edge's host is read whatever its case.
        precondition(Origin.read(packageAt: package("key-and-file", manifest: ["key": key], item: id)) == .chrome(id: id))
        precondition(Origin.read(packageAt: package("edge-case", manifest: ["update_url": "https://EDGE.Microsoft.com/extensionwebstorebase/v1/crx"], item: id)) == .edge(id: id))
        // One entry that is not the store's does not hide the one that is.
        let payload = try! JSONSerialization.data(withJSONObject: ["item_id": id]).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let mixed = #"[{"signed_content":{"payload":"e30"}},{"signed_content":{"payload":"\#(payload)"}}]"#
        precondition(Origin.read(packageAt: package("mixed", manifest: ["name": "A"], rawMetadata: mixed)) == .chrome(id: id))
        // A file far larger than the store writes is not read.
        let huge = "[" + String(repeating: " ", count: 9_000_000) + String(mixed.dropFirst())
        precondition(Origin.read(packageAt: package("huge", manifest: ["name": "A"], rawMetadata: huge)) == nil)

        // Nothing to go on: a Safari build, or a folder someone unpacked by hand.
        precondition(Origin.read(packageAt: package("plain", manifest: ["name": "__MSG_extName__", "manifest_version": 2])) == nil)
        precondition(Origin.read(packageAt: root.appendingPathComponent("missing")) == nil)

        // An id that is not a store id is not used: it becomes a folder name and part of a URL.
        for bad in ["../../etc", "NMBLAHMGLPBPLMFCGGGHDGOHOHLAEIEE", "nmblahmglpbplmfcggghdgohohlaeie", "nmblahmglpbplmfcggghdgohohlaeiez", ""] {
            precondition(Origin.read(packageAt: package("bad", manifest: ["name": "A"], item: bad)) == nil, bad)
        }
        precondition(Origin.read(packageAt: package("number", manifest: ["name": "A"], item: 7)) == nil)
        // A file that is not what the store writes.
        for raw in ["", "not json", "{}", "[]", #"[{"signed_content":{"payload":"!!!"}}]"#, #"[{"signed_content":{"payload":"e30"}}]"#, #"[7]"#] {
            precondition(Origin.read(packageAt: package("raw", manifest: ["name": "A"], rawMetadata: raw)) == nil, raw)
        }
        // A declared Firefox id of no use.
        precondition(Origin.read(packageAt: package("empty-gecko", manifest: ["browser_specific_settings": ["gecko": ["id": ""]]])) == nil)
        precondition(Origin.read(packageAt: package("odd-gecko", manifest: ["browser_specific_settings": ["gecko": ["id": 5]]])) == nil)

        print("ExtensionPackageOriginCheck passed")
    }
}
