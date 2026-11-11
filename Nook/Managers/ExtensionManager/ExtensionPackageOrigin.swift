// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionPackageOrigin.swift
//  Nook
//
//  What an installed package says about where it came from. An install from before stable IDs
//  has a random id and no store on record; this is how it is traced back. Foundation only.
//

import CryptoKit
import Foundation

enum ExtensionPackageOrigin: Equatable {
    /// A Chrome Web Store or Edge Add-ons listing, by the id the store signed into the package.
    case chrome(id: String)
    case edge(id: String)
    /// A Firefox add-on, by the id its manifest declares. Mozilla's site resolves it to a listing.
    case firefox(geckoID: String)

    /// Nothing here is checked against a signature. The answer is used only to fetch that listing
    /// from the store itself, so what a package gains by lying is to be replaced by the store's own
    /// build, which then holds whatever data the lying package had stored.
    static func read(packageAt root: URL) -> ExtensionPackageOrigin? {
        let manifest = json(root.appendingPathComponent("manifest.json")) as? [String: Any] ?? [:]
        if let id = storeItemID(packageAt: root) {
            let updates = manifest["update_url"] as? String ?? ""
            return URL(string: updates)?.host?.lowercased() == "edge.microsoft.com" ? .edge(id: id) : .chrome(id: id)
        }
        for key in ["browser_specific_settings", "applications"] {
            let gecko = (manifest[key] as? [String: Any])?["gecko"] as? [String: Any]
            if let id = gecko?["id"] as? String, !id.isEmpty, id.count <= 255 { return .firefox(geckoID: id) }
        }
        // A `key` fixes the id Chrome gives the package, wherever it was installed from.
        return (manifest["key"] as? String).flatMap(chromeID(fromManifestKey:)).map { .chrome(id: $0) }
    }

    /// Chrome's id for a manifest `key` (base64 DER public key): the first 16 bytes of its SHA-256,
    /// each hex digit written as a letter from a to p.
    static func chromeID(fromManifestKey key: String) -> String? {
        guard let der = Data(base64Encoded: key.filter { !$0.isWhitespace }), !der.isEmpty else { return nil }
        let hex = SHA256.hash(data: der).prefix(16).map { String(format: "%02x", $0) }.joined()
        return String(hex.compactMap { digit in
            Int(String(digit), radix: 16).map { Character(UnicodeScalar(UInt8(97 + $0))) }
        })
    }

    /// Both stores ship `_metadata/verified_contents.json`, whose signed payload names the listing.
    static func storeItemID(packageAt root: URL) -> String? {
        let file = root.appendingPathComponent("_metadata/verified_contents.json")
        for entry in json(file) as? [[String: Any]] ?? [] {
            guard let payload = (entry["signed_content"] as? [String: Any])?["payload"] as? String,
                  let data = Data(base64URLEncoded: payload),
                  let id = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["item_id"] as? String,
                  id.count == 32, id.utf8.allSatisfy({ $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "p") })
            else { continue }
            return id
        }
        return nil
    }

    private static func json(_ file: URL) -> Any? {
        // Nothing real is larger: the hash list of a big package runs to a few hundred kilobytes.
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 8_000_000,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

private extension Data {
    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
