// Licensed under GPL-3.0. See LICENSE.
//
//  Quarantine.swift
//  NookWeb
//
//  Marks a file Nook wrote from the web, so Gatekeeper checks it before it opens.
//

import Foundation

/// Sets `com.apple.quarantine`: flags 0083 ("downloaded from the web, not yet opened"), time, agent, id.
public func setQuarantineAttribute(on fileURL: URL) {
    let value = "0083;\(String(format: "%08x", Int(Date().timeIntervalSince1970)));Nook;\(UUID().uuidString)"
    let data = Data(value.utf8)
    fileURL.withUnsafeFileSystemRepresentation { path in
        guard let path else { return }
        _ = data.withUnsafeBytes { setxattr(path, "com.apple.quarantine", $0.baseAddress, data.count, 0, 0) }
    }
}
